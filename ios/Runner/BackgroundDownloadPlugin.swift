import Flutter
import Foundation
import Network
import UIKit

/// Hybrid native iOS download engine engineered for IPTV/Xtream VOD streams.
///
/// Why hybrid instead of a single `URLSessionDownloadTask` with `resumeData`?
/// Apple's `URLSessionDownloadTask` resume mechanism requires `ETag` or `Last-Modified`
/// headers and binds `resumeData` to the post-redirect URL. Xtream IPTV panels rarely
/// emit `ETag` and frequently 302-redirect to IP-bound temporary CDN URLs, causing
/// Apple's `nsurlsessiond` to silently discard hundreds of megabytes and restart from
/// byte 0 whenever the user switches Wi-Fi <-> Cellular or pauses/resumes.
///
/// How this engine solves it:
/// 1. All downloaded bytes live permanently in `<destination>.part` (excluded from iCloud
///    backup). Progress is never lost across Wi-Fi <-> Cellular switches, pauses, or restarts.
/// 2. While the app is in the foreground, a `URLSessionDataTask` streams directly into
///    `<destination>.part` with `Range: bytes=<partSize>-` against the original URL
///    (preserving `Range` and `User-Agent` across 302 redirects). `NWPathMonitor` detects
///    network interface switches (Wi-Fi <-> Cellular) and seamlessly reconnects from the
///    exact byte offset on disk.
/// 3. When the app enters the background (screen locked or app switched), the foreground
///    stream flushes `<destination>.part` and hands off to `URLSessionConfiguration.background`
///    in 64 MiB `Range` slices, appending each finished slice to `<destination>.part` so even
///    mid-background network changes keep previously downloaded data intact.
final class BackgroundDownloadPlugin: NSObject, FlutterPlugin, URLSessionDataDelegate, URLSessionDownloadDelegate {
  private static let channelName = "iptv/background_downloads"
  private static let backgroundChunkSize: Int64 = 64 * 1024 * 1024 // 64 MiB slices
  private static let maxAutoRetries = 6

  private static var sharedInstance: BackgroundDownloadPlugin?
  private static var pendingCompletionHandlers: [String: () -> Void] = [:]

  private var channel: FlutterMethodChannel?
  private var fgSession: URLSession!
  private var bgSession: URLSession!
  private let stateQueue = DispatchQueue(label: "com.iptv.downloads.state")
  private let pathMonitor = NWPathMonitor()
  private var lastInterfaceSignature: String?

  private var fgJobs: [String: ForegroundJob] = [:]
  private var bgTasksById: [String: URLSessionDownloadTask] = [:]
  private var bgMetaById: [String: BgTaskMeta] = [:]
  private var bgRetryCounts: [String: Int] = [:]
  private var pausingIds: Set<String> = []
  private var cancellingIds: Set<String> = []
  private var lastBgProgressSent: [String: TimeInterval] = [:]
  private var lastBgProgressBytes: [String: Int64] = [:]
  private var isInBackground: Bool = false

  private final class ForegroundJob {
    let id: String
    let urlString: String
    let destination: String
    let userAgent: String
    var task: URLSessionDataTask?
    var fileHandle: FileHandle?
    var currentOffset: Int64
    var totalBytes: Int64
    var supportsRange: Bool = true
    var lastProgressSent: TimeInterval = 0
    var lastProgressBytes: Int64
    var lastDataReceivedAt: TimeInterval = Date().timeIntervalSince1970
    var retryCount: Int = 0
    var retryWorkItem: DispatchWorkItem?
    var receivedResponse: Bool = false

    init(id: String, urlString: String, destination: String, userAgent: String, existingBytes: Int64, totalBytes: Int64) {
      self.id = id
      self.urlString = urlString
      self.destination = destination
      self.userAgent = userAgent
      self.currentOffset = existingBytes
      self.totalBytes = totalBytes
      self.lastProgressBytes = existingBytes
    }

    func closeHandle() {
      if let handle = fileHandle {
        try? handle.synchronize()
        try? handle.close()
        fileHandle = nil
      }
    }
  }

  private struct BgTaskMeta: Codable {
    let id: String
    let url: String
    let destination: String
    let userAgent: String
    let baseOffset: Int64
    let expectedSliceEnd: Int64? // inclusive byte index when chunked; nil when open-ended
    let knownTotalBytes: Int64
    let supportsRange: Bool
  }

  static var sessionIdentifier: String {
    let bundle = Bundle.main.bundleIdentifier ?? "com.iptv.app"
    return "\(bundle).backgroundDownloads.v2"
  }

  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "BackgroundDownloadPlugin") else { return }
    register(with: registrar)
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    let instance = sharedInstance ?? BackgroundDownloadPlugin()
    sharedInstance = instance
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addApplicationDelegate(instance)
  }

  func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) -> Bool {
    guard identifier == Self.sessionIdentifier else {
      return false
    }
    stateQueue.async {
      self.isInBackground = true
      Self.pendingCompletionHandlers[identifier] = completionHandler
    }
    return true
  }

  private override init() {
    super.init()
    if Thread.isMainThread {
      self.isInBackground = UIApplication.shared.applicationState == .background
    } else {
      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        let bg = UIApplication.shared.applicationState == .background
        self.stateQueue.async { self.isInBackground = bg }
      }
    }

    let fgConfig = URLSessionConfiguration.default
    fgConfig.allowsCellularAccess = true
    fgConfig.waitsForConnectivity = false
    fgConfig.timeoutIntervalForRequest = 20
    fgConfig.timeoutIntervalForResource = 60 * 60 * 6
    fgConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
    fgConfig.urlCache = nil
    self.fgSession = URLSession(configuration: fgConfig, delegate: self, delegateQueue: nil)

    let bgConfig = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
    bgConfig.isDiscretionary = false
    bgConfig.sessionSendsLaunchEvents = true
    bgConfig.allowsCellularAccess = true
    bgConfig.waitsForConnectivity = true
    bgConfig.httpMaximumConnectionsPerHost = 1
    self.bgSession = URLSession(configuration: bgConfig, delegate: self, delegateQueue: nil)

    rehydrateBackgroundTasks()
    observeLifecycle()
    startNetworkMonitor()
  }

  deinit {
    pathMonitor.cancel()
    NotificationCenter.default.removeObserver(self)
  }

  private func observeLifecycle() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleDidEnterBackground),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleDidBecomeActive),
      name: UIApplication.willEnterForegroundNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
  }

  private func startNetworkMonitor() {
    pathMonitor.pathUpdateHandler = { [weak self] path in
      guard let self = self else { return }
      let sig = Self.interfaceSignature(path)
      self.stateQueue.async {
        let prev = self.lastInterfaceSignature
        self.lastInterfaceSignature = sig
        guard path.status == .satisfied else { return }
        // Interface changed (e.g. Wi-Fi <-> Cellular) or connectivity just returned:
        // proactively reconnect any foreground job from its exact .part byte offset
        // so it does not stall on a dead socket from the previous network interface.
        if prev != nil && prev != sig && !self.isInBackground {
          self.reconnectForegroundJobsAfterNetworkChange()
        }
      }
    }
    pathMonitor.start(queue: stateQueue)
  }

  private static func interfaceSignature(_ path: NWPath) -> String {
    guard path.status == .satisfied else { return "unsatisfied" }
    var types: [String] = []
    if path.usesInterfaceType(.wifi) { types.append("wifi") }
    if path.usesInterfaceType(.cellular) { types.append("cellular") }
    if path.usesInterfaceType(.wiredEthernet) { types.append("wired") }
    return types.isEmpty ? "other" : types.joined(separator: "+")
  }

  private func rehydrateBackgroundTasks() {
    bgSession.getAllTasks { [weak self] tasks in
      guard let self = self else { return }
      self.stateQueue.async {
        for task in tasks {
          guard let dl = task as? URLSessionDownloadTask,
                let meta = Self.parseMeta(dl.taskDescription) else { continue }
          self.bgTasksById[meta.id] = dl
          self.bgMetaById[meta.id] = meta
        }
      }
    }
  }

  // MARK: - App Lifecycle Handoff

  @objc private func handleDidEnterBackground() {
    stateQueue.async {
      self.isInBackground = true
      guard !self.fgJobs.isEmpty else { return }

      let jobs = Array(self.fgJobs.values)
      for job in jobs {
        job.retryWorkItem?.cancel()
        job.retryWorkItem = nil
        job.closeHandle()
        self.fgJobs.removeValue(forKey: job.id)
        job.task?.cancel()

        let offset = Self.partFileSize(for: job.destination)
        let effectiveTotal = max(job.totalBytes, offset)
        self.enqueueBackgroundSlice(
          id: job.id,
          urlString: job.urlString,
          destination: job.destination,
          userAgent: job.userAgent,
          baseOffset: offset,
          knownTotalBytes: effectiveTotal,
          supportsRange: job.supportsRange
        )
      }
    }
  }

  @objc private func handleDidBecomeActive() {
    stateQueue.async {
      self.isInBackground = false
      // Any running background slice finishes cleanly and hands subsequent slices back
      // to foreground streaming automatically (see didFinishDownloadingTo).
    }
  }

  private func reconnectForegroundJobsAfterNetworkChange() {
    for job in fgJobs.values {
      // Cancel any pending retry timer and reconnect right away on the new interface.
      job.retryWorkItem?.cancel()
      job.retryWorkItem = nil
      job.closeHandle()
      let oldTask = job.task
      job.task = nil
      job.retryCount = 0
      launchForegroundTask(for: job)
      oldTask?.cancel()
    }
  }

  // MARK: - Flutter MethodChannel

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getDownloadDirectory":
      result(ensureDownloadDirectory()?.path)
    case "start":
      let args = call.arguments as? [String: Any] ?? [:]
      guard let id = args["id"] as? String,
            let urlStr = args["url"] as? String,
            let destination = args["destination"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing download arguments", details: nil))
        return
      }
      let userAgent = (args["userAgent"] as? String) ?? "VLC/3.0.20 LibVLC/3.0.20"
      let totalBytes = (args["totalBytes"] as? NSNumber)?.int64Value ?? 0
      startDownload(id: id, urlString: urlStr, destination: destination, userAgent: userAgent, knownTotalBytes: totalBytes)
      result(true)
    case "pause":
      let args = call.arguments as? [String: Any] ?? [:]
      guard let id = args["id"] as? String else {
        result(false)
        return
      }
      let destination = args["destination"] as? String
      pauseDownload(id: id, destination: destination) { paused in
        DispatchQueue.main.async { result(paused) }
      }
    case "cancel":
      let args = call.arguments as? [String: Any] ?? [:]
      guard let id = args["id"] as? String else {
        result(nil)
        return
      }
      let destination = args["destination"] as? String
      cancelDownload(id: id, destination: destination)
      result(nil)
    case "syncTasks":
      syncTasks { snapshot in
        DispatchQueue.main.async { result(snapshot) }
      }
    case "excludeFromBackup":
      let args = call.arguments as? [String: Any] ?? [:]
      if let path = args["path"] as? String {
        Self.markExcludedFromBackup(URL(fileURLWithPath: path))
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Directory, Part File & Metadata

  private func ensureDownloadDirectory() -> URL? {
    let fm = FileManager.default
    guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
    let dir = docs.appendingPathComponent("IPTV", isDirectory: true)
    if !fm.fileExists(atPath: dir.path) {
      try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    Self.markExcludedFromBackup(dir)
    return dir
  }

  private static func markExcludedFromBackup(_ url: URL) {
    var target = url
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? target.setResourceValues(values)
  }

  private static func partFileURL(for destination: String) -> URL {
    URL(fileURLWithPath: destination + ".part")
  }

  private static func partFileSize(for destination: String) -> Int64 {
    let path = partFileURL(for: destination).path
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
          let size = attrs[.size] as? NSNumber else {
      return 0
    }
    return max(0, size.int64Value)
  }

  private static func encodeMeta(_ meta: BgTaskMeta) -> String? {
    guard let data = try? JSONEncoder().encode(meta) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  private static func parseMeta(_ raw: String?) -> BgTaskMeta? {
    guard let raw = raw, let data = raw.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(BgTaskMeta.self, from: data)
  }

  private static func parseContentRangeTotal(_ header: String?) -> Int64? {
    guard let header = header, let slash = header.lastIndex(of: "/") else { return nil }
    let tail = header[header.index(after: slash)...].trimmingCharacters(in: .whitespaces)
    return Int64(tail)
  }

  // MARK: - Task Control

  private func startDownload(
    id: String,
    urlString: String,
    destination: String,
    userAgent: String,
    knownTotalBytes: Int64
  ) {
    guard URL(string: urlString) != nil else {
      sendEvent("failed", payload: ["id": id, "error": "Geçersiz indirme adresi"])
      return
    }
    let destURL = URL(fileURLWithPath: destination)
    let parentDir = destURL.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
    Self.markExcludedFromBackup(parentDir)

    stateQueue.async {
      if self.fgJobs[id] != nil { return }
      if let existingBg = self.bgTasksById[id], existingBg.state == .running { return }

      self.pausingIds.remove(id)
      self.cancellingIds.remove(id)
      self.bgRetryCounts.removeValue(forKey: id)
      self.lastBgProgressSent.removeValue(forKey: id)
      self.lastBgProgressBytes.removeValue(forKey: id)

      // Clean up any legacy Apple resumeData file from older versions.
      try? FileManager.default.removeItem(atPath: destination + ".resume")

      let existingBytes = Self.partFileSize(for: destination)

      if self.isInBackground {
        self.enqueueBackgroundSlice(
          id: id,
          urlString: urlString,
          destination: destination,
          userAgent: userAgent,
          baseOffset: existingBytes,
          knownTotalBytes: knownTotalBytes,
          supportsRange: true
        )
        return
      }

      let job = ForegroundJob(
        id: id,
        urlString: urlString,
        destination: destination,
        userAgent: userAgent,
        existingBytes: existingBytes,
        totalBytes: knownTotalBytes
      )
      self.fgJobs[id] = job
      self.launchForegroundTask(for: job)
    }
  }

  private func launchForegroundTask(for job: ForegroundJob) {
    guard let url = URL(string: job.urlString) else {
      fgJobs.removeValue(forKey: job.id)
      sendEvent("failed", payload: ["id": job.id, "error": "Geçersiz indirme adresi"])
      return
    }
    let existingBytes = Self.partFileSize(for: job.destination)
    job.currentOffset = existingBytes
    job.lastProgressBytes = existingBytes
    job.lastProgressSent = 0
    job.receivedResponse = false
    job.lastDataReceivedAt = Date().timeIntervalSince1970

    var req = URLRequest(url: url)
    req.setValue(job.userAgent, forHTTPHeaderField: "User-Agent")
    if existingBytes > 0 && job.supportsRange {
      req.setValue("bytes=\(existingBytes)-", forHTTPHeaderField: "Range")
    }

    let task = fgSession.dataTask(with: req)
    task.taskDescription = job.id
    job.task = task

    // Immediately keep UI anchored at the real disk offset so progress never flickers to 0.
    if existingBytes > 0 {
      sendEvent("progress", payload: [
        "id": job.id,
        "downloadedBytes": existingBytes,
        "totalBytes": max(job.totalBytes, existingBytes),
        "speedBytesPerSec": Int64(0),
      ])
    }
    task.resume()
  }

  private func enqueueBackgroundSlice(
    id: String,
    urlString: String,
    destination: String,
    userAgent: String,
    baseOffset: Int64,
    knownTotalBytes: Int64,
    supportsRange: Bool
  ) {
    guard let url = URL(string: urlString) else {
      sendEvent("failed", payload: ["id": id, "error": "Geçersiz indirme adresi"])
      return
    }

    var req = URLRequest(url: url)
    req.setValue(userAgent, forHTTPHeaderField: "User-Agent")

    var expectedSliceEnd: Int64? = nil
    if supportsRange {
      if knownTotalBytes > 0 {
        let end = min(knownTotalBytes - 1, baseOffset + Self.backgroundChunkSize - 1)
        if end >= baseOffset {
          req.setValue("bytes=\(baseOffset)-\(end)", forHTTPHeaderField: "Range")
          expectedSliceEnd = end
        }
      } else if baseOffset > 0 {
        let end = baseOffset + Self.backgroundChunkSize - 1
        req.setValue("bytes=\(baseOffset)-\(end)", forHTTPHeaderField: "Range")
        expectedSliceEnd = end
      } else {
        // First request starting directly in background: probe a 64 MiB range slice.
        let end = Self.backgroundChunkSize - 1
        req.setValue("bytes=0-\(end)", forHTTPHeaderField: "Range")
        expectedSliceEnd = end
      }
    }

    let meta = BgTaskMeta(
      id: id,
      url: urlString,
      destination: destination,
      userAgent: userAgent,
      baseOffset: baseOffset,
      expectedSliceEnd: expectedSliceEnd,
      knownTotalBytes: knownTotalBytes,
      supportsRange: supportsRange
    )
    let task = bgSession.downloadTask(with: req)
    task.taskDescription = Self.encodeMeta(meta)
    bgTasksById[id] = task
    bgMetaById[id] = meta
    lastBgProgressSent.removeValue(forKey: id)
    lastBgProgressBytes[id] = baseOffset
    task.resume()
  }

  private func pauseDownload(id: String, destination: String?, completion: @escaping (Bool) -> Void) {
    stateQueue.async {
      self.pausingIds.insert(id)
      var found = false

      if let job = self.fgJobs.removeValue(forKey: id) {
        found = true
        job.retryWorkItem?.cancel()
        job.retryWorkItem = nil
        job.closeHandle()
        job.task?.cancel()
      }
      if let bgTask = self.bgTasksById.removeValue(forKey: id) {
        found = true
        self.bgMetaById.removeValue(forKey: id)
        bgTask.cancel()
      }

      if found {
        self.sendEvent("paused", payload: ["id": id])
      }
      completion(found)
    }
  }

  private func cancelDownload(id: String, destination: String?) {
    stateQueue.async {
      self.cancellingIds.insert(id)
      self.pausingIds.remove(id)
      self.bgRetryCounts.removeValue(forKey: id)

      var dest = destination
      if let job = self.fgJobs.removeValue(forKey: id) {
        dest = dest ?? job.destination
        job.retryWorkItem?.cancel()
        job.retryWorkItem = nil
        job.closeHandle()
        job.task?.cancel()
      }
      if let bgTask = self.bgTasksById.removeValue(forKey: id) {
        dest = dest ?? self.bgMetaById.removeValue(forKey: id)?.destination
        bgTask.cancel()
      } else {
        dest = dest ?? self.bgMetaById.removeValue(forKey: id)?.destination
      }

      if let dest = dest {
        try? FileManager.default.removeItem(at: Self.partFileURL(for: dest))
        try? FileManager.default.removeItem(atPath: dest + ".resume")
      }
    }
  }

  private func syncTasks(completion: @escaping ([[String: Any]]) -> Void) {
    bgSession.getAllTasks { [weak self] tasks in
      guard let self = self else {
        completion([])
        return
      }
      self.stateQueue.async {
        var list: [[String: Any]] = []
        for task in tasks {
          guard let dl = task as? URLSessionDownloadTask,
                let meta = Self.parseMeta(dl.taskDescription) else { continue }
          self.bgTasksById[meta.id] = dl
          self.bgMetaById[meta.id] = meta
          let stateStr: String
          switch dl.state {
          case .running: stateStr = "downloading"
          case .suspended: stateStr = "paused"
          case .canceling: stateStr = "canceling"
          case .completed: stateStr = "completed"
          @unknown default: stateStr = "downloading"
          }
          let total = meta.knownTotalBytes > 0
            ? meta.knownTotalBytes
            : (meta.baseOffset + max(0, dl.countOfBytesExpectedToReceive))
          list.append([
            "id": meta.id,
            "destination": meta.destination,
            "state": stateStr,
            "downloadedBytes": meta.baseOffset + dl.countOfBytesReceived,
            "totalBytes": total,
          ])
        }
        completion(list)
      }
    }
  }

  // MARK: - Redirect Header Preservation (Critical for IPTV 302 CDN redirects)

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    var updated = request
    if let orig = task.originalRequest {
      if let ua = orig.value(forHTTPHeaderField: "User-Agent"),
         updated.value(forHTTPHeaderField: "User-Agent") == nil {
        updated.setValue(ua, forHTTPHeaderField: "User-Agent")
      }
      if let range = orig.value(forHTTPHeaderField: "Range"),
         updated.value(forHTTPHeaderField: "Range") == nil {
        updated.setValue(range, forHTTPHeaderField: "Range")
      }
    }
    completionHandler(updated)
  }

  // MARK: - Foreground URLSessionDataDelegate (Zero-Loss Direct .part Streaming)

  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    guard session === fgSession, let id = dataTask.taskDescription else {
      completionHandler(.allow)
      return
    }
    stateQueue.async {
      guard let job = self.fgJobs[id], job.task === dataTask else {
        completionHandler(.cancel)
        return
      }
      guard let http = response as? HTTPURLResponse else {
        completionHandler(.allow)
        return
      }

      // 416 Range Not Satisfiable: file already complete or changed on server.
      if http.statusCode == 416 && job.currentOffset > 0 {
        if let total = Self.parseContentRangeTotal(http.value(forHTTPHeaderField: "Content-Range")),
           total > 0 && job.currentOffset >= total {
          self.fgJobs.removeValue(forKey: id)
          completionHandler(.cancel)
          self.finalizePartFile(id: id, destination: job.destination, knownTotal: total)
          return
        }
        // Server file changed; reset .part and retry cleanly from 0.
        try? FileManager.default.removeItem(at: Self.partFileURL(for: job.destination))
        job.currentOffset = 0
        job.totalBytes = 0
        completionHandler(.cancel)
        self.launchForegroundTask(for: job)
        return
      }

      let isPartial = http.statusCode == 206
      if http.statusCode != 200 && !isPartial {
        let msg: String
        switch http.statusCode {
        case 401, 403, 509:
          msg = "Sunucu indirmeyi reddetti (HTTP \(http.statusCode) — bağlantı sınırı dolu veya hesap yetkisiz olabilir)"
        case 404:
          msg = "Dosya sunucuda bulunamadı (HTTP 404)"
        default:
          msg = "Sunucu HTTP \(http.statusCode) döndürdü"
        }
        self.fgJobs.removeValue(forKey: id)
        completionHandler(.cancel)
        self.sendEvent("failed", payload: ["id": id, "error": msg])
        return
      }

      let partURL = Self.partFileURL(for: job.destination)
      let fm = FileManager.default
      do {
        if !fm.fileExists(atPath: partURL.path) {
          fm.createFile(atPath: partURL.path, contents: nil)
        }
        Self.markExcludedFromBackup(partURL)
        let handle = try FileHandle(forWritingTo: partURL)
        if isPartial {
          try handle.seekToEnd()
          if let parsedTotal = Self.parseContentRangeTotal(http.value(forHTTPHeaderField: "Content-Range")),
             parsedTotal > 0 {
            job.totalBytes = parsedTotal
          } else if response.expectedContentLength > 0 {
            job.totalBytes = job.currentOffset + response.expectedContentLength
          }
          job.supportsRange = true
        } else {
          // 200 OK: either starting at 0 or server does not support Range.
          if job.currentOffset > 0 {
            job.supportsRange = false
          }
          try handle.truncate(atOffset: 0)
          job.currentOffset = 0
          job.lastProgressBytes = 0
          if response.expectedContentLength > 0 {
            job.totalBytes = response.expectedContentLength
          }
        }
        job.fileHandle = handle
        job.receivedResponse = true
        job.retryCount = 0
        completionHandler(.allow)
      } catch {
        self.fgJobs.removeValue(forKey: id)
        completionHandler(.cancel)
        self.sendEvent("failed", payload: ["id": id, "error": "Dosya açılamadı: \(error.localizedDescription)"])
      }
    }
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    guard session === fgSession, let id = dataTask.taskDescription else { return }
    stateQueue.async {
      guard let job = self.fgJobs[id], job.task === dataTask, let handle = job.fileHandle else { return }
      do {
        try handle.write(contentsOf: data)
      } catch {
        job.closeHandle()
        self.fgJobs.removeValue(forKey: id)
        dataTask.cancel()
        self.sendEvent("failed", payload: ["id": id, "error": "Disk yazma hatası: \(error.localizedDescription)"])
        return
      }

      job.currentOffset += Int64(data.count)
      let now = Date().timeIntervalSince1970
      job.lastDataReceivedAt = now

      let elapsed = now - job.lastProgressSent
      if job.lastProgressSent == 0 || elapsed >= 0.25 {
        let speed: Int64 = (job.lastProgressSent > 0 && elapsed > 0.05)
          ? Int64(Double(max(0, job.currentOffset - job.lastProgressBytes)) / elapsed)
          : 0
        job.lastProgressSent = now
        job.lastProgressBytes = job.currentOffset
        self.sendEvent("progress", payload: [
          "id": id,
          "downloadedBytes": job.currentOffset,
          "totalBytes": max(0, job.totalBytes),
          "speedBytesPerSec": speed,
        ])
      }
    }
  }

  // MARK: - Background URLSessionDownloadDelegate (64 MiB Slices Appended to .part)

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard session === bgSession, let meta = Self.parseMeta(downloadTask.taskDescription) else { return }
    let now = Date().timeIntervalSince1970
    stateQueue.async {
      let prevTime = self.lastBgProgressSent[meta.id] ?? 0
      let elapsed = now - prevTime
      if prevTime > 0 && elapsed < 0.25 { return }

      let combinedDownloaded = meta.baseOffset + totalBytesWritten
      var combinedTotal = meta.knownTotalBytes
      if combinedTotal <= 0 {
        if let http = downloadTask.response as? HTTPURLResponse,
           let parsedTotal = Self.parseContentRangeTotal(http.value(forHTTPHeaderField: "Content-Range")),
           parsedTotal > 0 {
          combinedTotal = parsedTotal
        } else if totalBytesExpectedToWrite > 0 {
          combinedTotal = meta.baseOffset + totalBytesExpectedToWrite
        }
      }

      let prevBytes = self.lastBgProgressBytes[meta.id] ?? meta.baseOffset
      let speed: Int64 = (prevTime > 0 && elapsed > 0.05)
        ? Int64(Double(max(0, combinedDownloaded - prevBytes)) / elapsed)
        : 0
      self.lastBgProgressSent[meta.id] = now
      self.lastBgProgressBytes[meta.id] = combinedDownloaded

      self.sendEvent("progress", payload: [
        "id": meta.id,
        "downloadedBytes": combinedDownloaded,
        "totalBytes": max(0, combinedTotal),
        "speedBytesPerSec": speed,
      ])
    }
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    guard session === bgSession, let meta = Self.parseMeta(downloadTask.taskDescription) else { return }

    // IMPORTANT: `location` is deleted by iOS immediately after this delegate returns,
    // so file I/O must run synchronously before returning from this method.
    if let http = downloadTask.response as? HTTPURLResponse, http.statusCode >= 400 {
      stateQueue.async {
        self.bgTasksById.removeValue(forKey: meta.id)
        self.bgMetaById.removeValue(forKey: meta.id)
      }
      sendEvent("failed", payload: [
        "id": meta.id,
        "error": "Sunucu HTTP \(http.statusCode) döndürdü",
      ])
      return
    }

    let http = downloadTask.response as? HTTPURLResponse
    let isPartial = http?.statusCode == 206
    let parsedTotal = Self.parseContentRangeTotal(http?.value(forHTTPHeaderField: "Content-Range")) ?? 0
    let totalBytes = parsedTotal > 0 ? parsedTotal : meta.knownTotalBytes
    let partURL = Self.partFileURL(for: meta.destination)
    let fm = FileManager.default

    do {
      let parent = partURL.deletingLastPathComponent()
      if !fm.fileExists(atPath: parent.path) {
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
      }
      Self.markExcludedFromBackup(parent)

      if isPartial {
        try Self.appendFile(from: location, to: partURL, expectedOffset: meta.baseOffset)
      } else {
        // Server sent 200 OK (full file): replace destination directly.
        let destURL = URL(fileURLWithPath: meta.destination)
        if fm.fileExists(atPath: destURL.path) { try fm.removeItem(at: destURL) }
        try fm.moveItem(at: location, to: destURL)
        Self.markExcludedFromBackup(destURL)
        try? fm.removeItem(at: partURL)
        let finalSize = (try? fm.attributesOfItem(atPath: destURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        stateQueue.async {
          self.bgTasksById.removeValue(forKey: meta.id)
          self.bgMetaById.removeValue(forKey: meta.id)
          self.lastBgProgressSent.removeValue(forKey: meta.id)
          self.lastBgProgressBytes.removeValue(forKey: meta.id)
        }
        sendEvent("completed", payload: [
          "id": meta.id,
          "filePath": destURL.path,
          "totalBytes": finalSize,
        ])
        return
      }

      let newOffset = Self.partFileSize(for: meta.destination)
      let done = (totalBytes > 0 && newOffset >= totalBytes) || meta.expectedSliceEnd == nil

      stateQueue.async {
        self.bgTasksById.removeValue(forKey: meta.id)
        self.bgMetaById.removeValue(forKey: meta.id)
        self.bgRetryCounts.removeValue(forKey: meta.id)
        self.lastBgProgressSent.removeValue(forKey: meta.id)
        self.lastBgProgressBytes.removeValue(forKey: meta.id)

        if self.pausingIds.contains(meta.id) || self.cancellingIds.contains(meta.id) {
          return
        }

        if done {
          self.finalizePartFile(id: meta.id, destination: meta.destination, knownTotal: max(totalBytes, newOffset))
        } else if self.isInBackground {
          self.enqueueBackgroundSlice(
            id: meta.id,
            urlString: meta.url,
            destination: meta.destination,
            userAgent: meta.userAgent,
            baseOffset: newOffset,
            knownTotalBytes: totalBytes,
            supportsRange: true
          )
        } else {
          // App returned to foreground while slice was downloading: switch back to
          // direct zero-loss foreground streaming from the exact new .part offset.
          let job = ForegroundJob(
            id: meta.id,
            urlString: meta.url,
            destination: meta.destination,
            userAgent: meta.userAgent,
            existingBytes: newOffset,
            totalBytes: totalBytes
          )
          self.fgJobs[meta.id] = job
          self.launchForegroundTask(for: job)
        }
      }
    } catch {
      stateQueue.async {
        self.bgTasksById.removeValue(forKey: meta.id)
        self.bgMetaById.removeValue(forKey: meta.id)
      }
      sendEvent("failed", payload: [
        "id": meta.id,
        "error": "Dosya birleştirilemedi: \(error.localizedDescription)",
      ])
    }
  }

  /// Streams bytes from `source` to the end of `destination` using a small 256 KiB buffer
  /// so appending 64 MiB slices in background never spikes memory.
  private static func appendFile(from source: URL, to destination: URL, expectedOffset: Int64) throws {
    let fm = FileManager.default
    if !fm.fileExists(atPath: destination.path) {
      fm.createFile(atPath: destination.path, contents: nil)
    }
    markExcludedFromBackup(destination)

    let reader = try FileHandle(forReadingFrom: source)
    let writer = try FileHandle(forWritingTo: destination)
    defer {
      try? reader.close()
      try? writer.synchronize()
      try? writer.close()
    }
    try writer.truncate(atOffset: UInt64(max(0, expectedOffset)))
    try writer.seekToEnd()

    let bufferSize = 256 * 1024
    while true {
      let chunk = try autoreleasepool { () -> Data? in
        try reader.read(upToCount: bufferSize)
      }
      guard let data = chunk, !data.isEmpty else { break }
      try writer.write(contentsOf: data)
    }
  }

  // MARK: - Task Completion & Automatic Network-Switch Recovery

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if session === fgSession {
      handleForegroundCompletion(task: task, error: error)
    } else if session === bgSession {
      handleBackgroundCompletion(task: task, error: error)
    }
  }

  private func handleForegroundCompletion(task: URLSessionTask, error: Error?) {
    guard let id = task.taskDescription else { return }
    stateQueue.async {
      guard let job = self.fgJobs[id] else {
        self.pausingIds.remove(id)
        self.cancellingIds.remove(id)
        return
      }
      // Ignore stale callbacks from an earlier replaced task (e.g. network-change reconnect).
      if job.task !== task { return }
      job.closeHandle()
      job.task = nil

      if self.pausingIds.remove(id) != nil {
        self.fgJobs.removeValue(forKey: id)
        return
      }
      if self.cancellingIds.remove(id) != nil {
        self.fgJobs.removeValue(forKey: id)
        return
      }

      if let error = error {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
          return
        }
        // Transient network / interface-change errors (Wi-Fi -> Cellular, timeout, dropped TCP):
        // keep all bytes already in .part and automatically reconnect from that exact offset.
        if Self.isRecoverableNetworkError(nsError) && job.retryCount < Self.maxAutoRetries {
          job.retryCount += 1
          let delay = min(8.0, pow(1.5, Double(job.retryCount)))
          let work = DispatchWorkItem { [weak self] in
            guard let self = self, let current = self.fgJobs[id], current === job else { return }
            self.launchForegroundTask(for: current)
          }
          job.retryWorkItem = work
          self.stateQueue.asyncAfter(deadline: .now() + delay, execute: work)
          return
        }

        self.fgJobs.removeValue(forKey: id)
        self.sendEvent("failed", payload: ["id": id, "error": error.localizedDescription])
        return
      }

      // Stream ended without an explicit URLSession error: verify total bytes before finalizing.
      let diskSize = Self.partFileSize(for: job.destination)
      if job.totalBytes > 0 && diskSize < job.totalBytes {
        if job.retryCount < Self.maxAutoRetries {
          job.retryCount += 1
          let delay = min(6.0, Double(job.retryCount) * 1.5)
          let work = DispatchWorkItem { [weak self] in
            guard let self = self, let current = self.fgJobs[id], current === job else { return }
            self.launchForegroundTask(for: current)
          }
          job.retryWorkItem = work
          self.stateQueue.asyncAfter(deadline: .now() + delay, execute: work)
          return
        }
        self.fgJobs.removeValue(forKey: id)
        self.sendEvent("failed", payload: ["id": id, "error": "Bağlantı indirme bitmeden kesildi"])
        return
      }

      self.fgJobs.removeValue(forKey: id)
      self.finalizePartFile(id: id, destination: job.destination, knownTotal: max(job.totalBytes, diskSize))
    }
  }

  private func handleBackgroundCompletion(task: URLSessionTask, error: Error?) {
    guard let error = error, let meta = Self.parseMeta(task.taskDescription) else { return }
    let nsError = error as NSError
    stateQueue.async {
      self.bgTasksById.removeValue(forKey: meta.id)
      self.bgMetaById.removeValue(forKey: meta.id)
      self.lastBgProgressSent.removeValue(forKey: meta.id)
      self.lastBgProgressBytes.removeValue(forKey: meta.id)

      if self.pausingIds.remove(meta.id) != nil {
        return
      }
      if self.cancellingIds.remove(meta.id) != nil {
        return
      }
      if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
        return
      }

      // If the background slice failed due to a network change while already on disk,
      // retry from the exact .part offset instead of losing prior slices.
      let currentOffset = Self.partFileSize(for: meta.destination)
      let retries = (self.bgRetryCounts[meta.id] ?? 0) + 1
      if Self.isRecoverableNetworkError(nsError) && retries <= Self.maxAutoRetries {
        self.bgRetryCounts[meta.id] = retries
        if self.isInBackground {
          self.enqueueBackgroundSlice(
            id: meta.id,
            urlString: meta.url,
            destination: meta.destination,
            userAgent: meta.userAgent,
            baseOffset: currentOffset,
            knownTotalBytes: meta.knownTotalBytes,
            supportsRange: meta.supportsRange
          )
        } else {
          let job = ForegroundJob(
            id: meta.id,
            urlString: meta.url,
            destination: meta.destination,
            userAgent: meta.userAgent,
            existingBytes: currentOffset,
            totalBytes: meta.knownTotalBytes
          )
          self.fgJobs[meta.id] = job
          self.launchForegroundTask(for: job)
        }
        return
      }

      self.bgRetryCounts.removeValue(forKey: meta.id)
      self.sendEvent("failed", payload: [
        "id": meta.id,
        "error": error.localizedDescription,
      ])
    }
  }

  private func finalizePartFile(id: String, destination: String, knownTotal: Int64) {
    let fm = FileManager.default
    let partURL = Self.partFileURL(for: destination)
    let destURL = URL(fileURLWithPath: destination)
    do {
      if fm.fileExists(atPath: destURL.path) {
        try fm.removeItem(at: destURL)
      }
      try fm.moveItem(at: partURL, to: destURL)
      Self.markExcludedFromBackup(destURL)
      let attrs = try? fm.attributesOfItem(atPath: destURL.path)
      let fileSize = (attrs?[.size] as? NSNumber)?.int64Value ?? knownTotal
      sendEvent("completed", payload: [
        "id": id,
        "filePath": destURL.path,
        "totalBytes": fileSize,
      ])
    } catch {
      sendEvent("failed", payload: [
        "id": id,
        "error": "Dosya kaydedilemedi: \(error.localizedDescription)",
      ])
    }
  }

  private static func isRecoverableNetworkError(_ error: NSError) -> Bool {
    if error.domain == NSURLErrorDomain {
      switch error.code {
      case NSURLErrorTimedOut,
           NSURLErrorCannotFindHost,
           NSURLErrorCannotConnectToHost,
           NSURLErrorNetworkConnectionLost,
           NSURLErrorDNSLookupFailed,
           NSURLErrorNotConnectedToInternet,
           NSURLErrorDataNotAllowed,
           NSURLErrorInternationalRoamingOff,
           NSURLErrorCallIsActive:
        return true
      default:
        return false
      }
    }
    return error.domain == NSPOSIXErrorDomain
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    guard let identifier = session.configuration.identifier else { return }
    stateQueue.async {
      let handler = Self.pendingCompletionHandlers.removeValue(forKey: identifier)
      if let handler = handler {
        DispatchQueue.main.async { handler() }
      }
    }
  }

  // MARK: - Event Dispatch

  private func sendEvent(_ method: String, payload: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      self?.channel?.invokeMethod(method, arguments: payload)
    }
  }
}

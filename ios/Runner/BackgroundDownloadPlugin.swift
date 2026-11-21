import Flutter
import Foundation
import Network
import UIKit

/// High-throughput hybrid native iOS download engine engineered for IPTV/Xtream VOD streams.
///
/// Architecture:
/// 1. All downloaded bytes live permanently in `<destination>.part` (excluded from iCloud backup)
///    alongside a tiny `<destination>.part.meta` byte-range map so parallel chunks, Wi-Fi <-> Cellular
///    switches, pauses, and app restarts never lose progress.
/// 2. In the foreground, adaptive multi-connection HTTP `Range` workers (up to `maxConnections`,
///    default 6) download 4 MiB chunks in parallel with 512 KiB coalesced writes, `Accept-Encoding:
///    identity`, and redirect header preservation. Strict single-connection IPTV servers are detected
///    automatically (HTTP 401/403/429/503/509 or primary kick) and safely drop back to 1 stream.
/// 3. When the app enters the background, foreground buffers flush cleanly to `.part` + `.part.meta`
///    and hand remaining gaps to `URLSessionConfiguration.background` in 64 MiB slices. Returning
///    to the foreground immediately resumes full-speed multi-connection streaming instead of staying
///    stuck on an OS-throttled background slice.
final class BackgroundDownloadPlugin: NSObject, FlutterPlugin, URLSessionDataDelegate, URLSessionDownloadDelegate {
  private static let channelName = "iptv/background_downloads"
  private static let backgroundChunkSize: Int64 = 64 * 1024 * 1024 // 64 MiB background slices
  private static let minSegmentedBytes: Int64 = 2 * 1024 * 1024 // 2 MiB threshold for multi-connection
  private static let writeBufferBytes = 512 * 1024 // 512 KiB coalesced writes
  private static let minStealBytes: Int64 = 512 * 1024
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
  private var handoffToFgIds: Set<String> = []
  private var lastBgProgressSent: [String: TimeInterval] = [:]
  private var lastBgProgressBytes: [String: Int64] = [:]
  private var isInBackground: Bool = false

  // MARK: - Byte-Range Map & Sliding-Window Speed Meter

  private struct ByteRange: Codable {
    var start: Int64
    var end: Int64 // exclusive
  }

  private struct RangeMetaFile: Codable {
    let v: Int
    let totalBytes: Int64
    let ranges: [[Int64]]
  }

  private final class RangeTracker {
    var ranges: [ByteRange] = []

    var completedBytes: Int64 {
      ranges.reduce(0) { $0 + ($1.end - $1.start) }
    }

    var maxEnd: Int64 {
      ranges.last?.end ?? 0
    }

    var isEmpty: Bool {
      ranges.isEmpty
    }

    func clear() {
      ranges.removeAll()
    }

    func add(start: Int64, end: Int64) {
      guard end > start, start >= 0 else { return }
      var s = start
      var e = end
      var next: [ByteRange] = []
      next.reserveCapacity(ranges.count + 1)
      var inserted = false
      for r in ranges {
        if r.end < s {
          next.append(r)
        } else if e < r.start {
          if !inserted {
            next.append(ByteRange(start: s, end: e))
            inserted = true
          }
          next.append(r)
        } else {
          s = min(s, r.start)
          e = max(e, r.end)
        }
      }
      if !inserted {
        next.append(ByteRange(start: s, end: e))
      }
      ranges = next
    }

    func clamp(toLength maxLength: Int64) {
      guard maxLength > 0 else {
        ranges.removeAll()
        return
      }
      var next: [ByteRange] = []
      for r in ranges {
        if r.start >= maxLength { break }
        let clampedEnd = min(r.end, maxLength)
        if clampedEnd > r.start {
          next.append(ByteRange(start: r.start, end: clampedEnd))
        }
      }
      ranges = next
    }

    func isComplete(totalBytes: Int64) -> Bool {
      totalBytes > 0 && ranges.count == 1 && ranges[0].start == 0 && ranges[0].end >= totalBytes
    }

    func missingRanges(totalBytes: Int64) -> [ByteRange] {
      guard totalBytes > 0 else { return [] }
      var gaps: [ByteRange] = []
      var cursor: Int64 = 0
      for r in ranges {
        if r.start >= totalBytes { break }
        if r.start > cursor {
          gaps.append(ByteRange(start: cursor, end: min(r.start, totalBytes)))
        }
        if r.end > cursor { cursor = r.end }
        if cursor >= totalBytes { break }
      }
      if cursor < totalBytes {
        gaps.append(ByteRange(start: cursor, end: totalBytes))
      }
      return gaps
    }

    func isCompletelyMissing(start: Int64, end: Int64) -> Bool {
      guard end > start else { return false }
      for r in ranges {
        if r.end <= start { continue }
        if r.start >= end { break }
        return false
      }
      return true
    }

    func save(to metaURL: URL, totalBytes: Int64) {
      guard totalBytes > 0 else { return }
      let payload = RangeMetaFile(v: 1, totalBytes: totalBytes, ranges: ranges.map { [$0.start, $0.end] })
      if let data = try? JSONEncoder().encode(payload) {
        try? data.write(to: metaURL, options: .atomic)
        BackgroundDownloadPlugin.markExcludedFromBackup(metaURL)
      }
    }

    static func load(partURL: URL, metaURL: URL) -> (tracker: RangeTracker, totalBytes: Int64)? {
      let fm = FileManager.default
      guard fm.fileExists(atPath: partURL.path),
            fm.fileExists(atPath: metaURL.path),
            let data = try? Data(contentsOf: metaURL),
            let decoded = try? JSONDecoder().decode(RangeMetaFile.self, from: data),
            decoded.totalBytes > 0 else {
        return nil
      }
      let tracker = RangeTracker()
      for pair in decoded.ranges where pair.count >= 2 {
        let s = pair[0]
        let e = min(pair[1], decoded.totalBytes)
        if s >= 0 && e > s {
          tracker.add(start: s, end: e)
        }
      }
      let partLen = (try? fm.attributesOfItem(atPath: partURL.path)[.size] as? NSNumber)?.int64Value ?? 0
      tracker.clamp(toLength: max(0, partLen))
      return (tracker, decoded.totalBytes)
    }
  }

  private final class SpeedMeter {
    private var samples: [(time: TimeInterval, bytes: Int64)] = []
    private var windowBytes: Int64 = 0
    private let windowSec: TimeInterval = 1.5

    func add(bytes: Int64, now: TimeInterval) {
      guard bytes > 0 else { return }
      samples.append((now, bytes))
      windowBytes += bytes
      prune(now: now)
    }

    func bytesPerSecond(now: TimeInterval) -> Int64 {
      prune(now: now)
      guard let first = samples.first, windowBytes > 0 else { return 0 }
      let span = max(0.25, now - first.time)
      return Int64(Double(windowBytes) / span)
    }

    func reset() {
      samples.removeAll()
      windowBytes = 0
    }

    private func prune(now: TimeInterval) {
      let cutoff = now - windowSec
      var dropCount = 0
      while dropCount < samples.count && samples[dropCount].time < cutoff {
        windowBytes -= samples[dropCount].bytes
        dropCount += 1
      }
      if dropCount > 0 {
        samples.removeFirst(dropCount)
      }
      if windowBytes < 0 { windowBytes = 0 }
    }
  }

  // MARK: - Foreground Multi-Worker Job & Background Metadata

  private final class WorkerSlot {
    let workerId: Int
    let isPrimary: Bool
    var task: URLSessionDataTask?
    var start: Int64
    var cursor: Int64
    var end: Int64 // exclusive
    var writePos: Int64
    var openEnded: Bool
    var buffer: Data
    var receivedBytes: Int64 = 0
    var firedFirstBytes: Bool = false
    var streaming: Bool = false
    var usedResolvedURL: Bool = false
    var retriedOriginal: Bool = false
    var cancelledByPool: Bool = false

    init(workerId: Int, isPrimary: Bool, start: Int64, end: Int64, openEnded: Bool) {
      self.workerId = workerId
      self.isPrimary = isPrimary
      self.start = start
      self.cursor = start
      self.end = end
      self.writePos = start
      self.openEnded = openEnded
      self.buffer = Data()
      self.buffer.reserveCapacity(BackgroundDownloadPlugin.writeBufferBytes)
    }

    var remaining: Int64 {
      max(0, end - cursor)
    }
  }

  private final class ForegroundJob {
    let id: String
    let urlString: String
    let destination: String
    let userAgent: String
    let desiredMaxWorkers: Int

    var resolvedURL: URL?
    var resolvedURLReusable: Bool = true
    var fileHandle: FileHandle?
    var tracker = RangeTracker()
    var speedMeter = SpeedMeter()
    var workers: [Int: WorkerSlot] = [:]
    var nextWorkerId: Int = 1

    var totalBytes: Int64
    var chunkSize: Int64 = 4 * 1024 * 1024
    var supportsRange: Bool = true
    var effectiveMaxWorkers: Int
    var probeStarted: Bool = false
    var probeSucceeded: Bool = false
    var singleConnKickDetected: Bool = false
    var lastScaleUpAt: TimeInterval = 0

    var lastProgressSent: TimeInterval = 0
    var lastMetaSavedAt: TimeInterval = 0
    var retryCount: Int = 0
    var retryWorkItem: DispatchWorkItem?
    var receivedAnyBytesThisCycle: Bool = false

    init(
      id: String,
      urlString: String,
      destination: String,
      userAgent: String,
      totalBytes: Int64,
      maxConnections: Int
    ) {
      self.id = id
      self.urlString = urlString
      self.destination = destination
      self.userAgent = userAgent
      self.totalBytes = totalBytes
      self.desiredMaxWorkers = max(1, min(8, maxConnections))
      self.effectiveMaxWorkers = self.desiredMaxWorkers
    }

    func computeChunkSize() -> Int64 {
      if totalBytes >= 16 * 1024 * 1024 { return 4 * 1024 * 1024 }
      if totalBytes >= 4 * 1024 * 1024 { return 1 * 1024 * 1024 }
      return 512 * 1024
    }

    func activeStreamingCount() -> Int {
      max(1, workers.values.filter { $0.streaming }.count)
    }

    func liveCompletedBytes() -> Int64 {
      let merged = RangeTracker()
      for r in tracker.ranges {
        merged.add(start: r.start, end: r.end)
      }
      for w in workers.values where w.cursor > w.start {
        merged.add(start: w.start, end: w.cursor)
      }
      return merged.completedBytes
    }

    func flushAllBuffers() {
      guard let handle = fileHandle else { return }
      for w in workers.values where !w.buffer.isEmpty {
        do {
          try handle.seek(toOffset: UInt64(max(0, w.writePos)))
          try handle.write(contentsOf: w.buffer)
          let len = Int64(w.buffer.count)
          tracker.add(start: w.writePos, end: w.writePos + len)
          w.writePos += len
          w.buffer.removeAll(keepingCapacity: true)
        } catch {
          w.buffer.removeAll(keepingCapacity: false)
        }
      }
    }

    func flushAndCloseHandle() {
      flushAllBuffers()
      if let handle = fileHandle {
        try? handle.synchronize()
        try? handle.close()
        fileHandle = nil
      }
      if totalBytes > 0 && !tracker.isEmpty {
        tracker.save(to: BackgroundDownloadPlugin.metaFileURL(for: destination), totalBytes: totalBytes)
      }
    }

    func cancelAllWorkerTasks() {
      for w in workers.values {
        w.cancelledByPool = true
        w.task?.cancel()
        w.task = nil
      }
      workers.removeAll()
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
    let maxConnections: Int?
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
    fgConfig.httpMaximumConnectionsPerHost = 8
    fgConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
    fgConfig.urlCache = nil
    self.fgSession = URLSession(configuration: fgConfig, delegate: self, delegateQueue: nil)

    let bgConfig = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
    bgConfig.isDiscretionary = false
    bgConfig.sessionSendsLaunchEvents = true
    bgConfig.allowsCellularAccess = true
    bgConfig.waitsForConnectivity = true
    bgConfig.httpMaximumConnectionsPerHost = 2
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
        job.flushAndCloseHandle()
        job.cancelAllWorkerTasks()
        self.fgJobs.removeValue(forKey: job.id)

        let nextGap = self.nextMissingBackgroundSlice(
          destination: job.destination,
          knownTotalBytes: job.totalBytes,
          supportsRange: job.supportsRange
        )
        self.enqueueBackgroundSlice(
          id: job.id,
          urlString: job.urlString,
          destination: job.destination,
          userAgent: job.userAgent,
          baseOffset: nextGap.start,
          sliceEndInclusive: nextGap.endInclusive,
          knownTotalBytes: max(job.totalBytes, nextGap.totalBytes),
          supportsRange: job.supportsRange,
          maxConnections: job.desiredMaxWorkers
        )
      }
    }
  }

  @objc private func handleDidBecomeActive() {
    stateQueue.async {
      self.isInBackground = false
      // Immediately upgrade any OS-throttled background slice back to full-speed
      // multi-connection foreground streaming without losing saved .part/.part.meta ranges.
      let activeBgIds = Array(self.bgTasksById.keys)
      for id in activeBgIds {
        guard let bgTask = self.bgTasksById.removeValue(forKey: id),
              let meta = self.bgMetaById.removeValue(forKey: id) else { continue }
        guard bgTask.state == .running || bgTask.state == .suspended else { continue }
        self.handoffToFgIds.insert(id)
        bgTask.cancel()
        self.lastBgProgressSent.removeValue(forKey: id)
        self.lastBgProgressBytes.removeValue(forKey: id)

        if self.fgJobs[id] == nil {
          let job = ForegroundJob(
            id: meta.id,
            urlString: meta.url,
            destination: meta.destination,
            userAgent: meta.userAgent,
            totalBytes: meta.knownTotalBytes,
            maxConnections: meta.maxConnections ?? 6
          )
          job.supportsRange = meta.supportsRange
          self.fgJobs[meta.id] = job
          self.startForegroundCycle(for: job)
        }
      }
    }
  }

  private func reconnectForegroundJobsAfterNetworkChange() {
    for job in fgJobs.values {
      job.retryWorkItem?.cancel()
      job.retryWorkItem = nil
      job.flushAndCloseHandle()
      job.cancelAllWorkerTasks()
      job.retryCount = 0
      startForegroundCycle(for: job)
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
      let maxConnections = (args["maxConnections"] as? NSNumber)?.intValue ?? 6
      startDownload(
        id: id,
        urlString: urlStr,
        destination: destination,
        userAgent: userAgent,
        knownTotalBytes: totalBytes,
        maxConnections: maxConnections
      )
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

  private static func metaFileURL(for destination: String) -> URL {
    URL(fileURLWithPath: destination + ".part.meta")
  }

  private static func partFileSize(for destination: String) -> Int64 {
    let path = partFileURL(for: destination).path
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
          let size = attrs[.size] as? NSNumber else {
      return 0
    }
    return max(0, size.int64Value)
  }

  private static func loadTrackerForDestination(_ destination: String) -> (tracker: RangeTracker, totalBytes: Int64) {
    let partURL = partFileURL(for: destination)
    let metaURL = metaFileURL(for: destination)
    if let loaded = RangeTracker.load(partURL: partURL, metaURL: metaURL) {
      return loaded
    }
    let tracker = RangeTracker()
    let size = partFileSize(for: destination)
    if size > 0 {
      tracker.add(start: 0, end: size)
    }
    return (tracker, 0)
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

  private static func taskIdentifier(jobId: String, workerId: Int) -> String {
    "\(jobId)|\(workerId)"
  }

  private static func parseTaskIdentifier(_ raw: String?) -> (jobId: String, workerId: Int)? {
    guard let raw = raw, let bar = raw.lastIndex(of: "|") else { return nil }
    let jobId = String(raw[..<bar])
    guard let wid = Int(raw[raw.index(after: bar)...]) else { return nil }
    return (jobId, wid)
  }

  private func nextMissingBackgroundSlice(
    destination: String,
    knownTotalBytes: Int64,
    supportsRange: Bool
  ) -> (start: Int64, endInclusive: Int64?, totalBytes: Int64) {
    let loaded = Self.loadTrackerForDestination(destination)
    let total = max(knownTotalBytes, loaded.totalBytes)
    guard supportsRange else {
      return (0, nil, total)
    }
    if total > 0 {
      let gaps = loaded.tracker.missingRanges(totalBytes: total)
      if let first = gaps.first {
        let end = min(first.end - 1, first.start + Self.backgroundChunkSize - 1)
        return (first.start, end, total)
      }
      return (total, nil, total)
    }
    let offset = loaded.tracker.maxEnd
    return (offset, offset + Self.backgroundChunkSize - 1, 0)
  }

  // MARK: - Task Control

  private func startDownload(
    id: String,
    urlString: String,
    destination: String,
    userAgent: String,
    knownTotalBytes: Int64,
    maxConnections: Int
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
      self.handoffToFgIds.remove(id)
      self.bgRetryCounts.removeValue(forKey: id)
      self.lastBgProgressSent.removeValue(forKey: id)
      self.lastBgProgressBytes.removeValue(forKey: id)

      try? FileManager.default.removeItem(atPath: destination + ".resume")

      if self.isInBackground {
        let gap = self.nextMissingBackgroundSlice(
          destination: destination,
          knownTotalBytes: knownTotalBytes,
          supportsRange: true
        )
        self.enqueueBackgroundSlice(
          id: id,
          urlString: urlString,
          destination: destination,
          userAgent: userAgent,
          baseOffset: gap.start,
          sliceEndInclusive: gap.endInclusive,
          knownTotalBytes: gap.totalBytes,
          supportsRange: true,
          maxConnections: maxConnections
        )
        return
      }

      let job = ForegroundJob(
        id: id,
        urlString: urlString,
        destination: destination,
        userAgent: userAgent,
        totalBytes: knownTotalBytes,
        maxConnections: maxConnections
      )
      self.fgJobs[id] = job
      self.startForegroundCycle(for: job)
    }
  }

  private func startForegroundCycle(for job: ForegroundJob) {
    guard let url = URL(string: job.urlString) else {
      fgJobs.removeValue(forKey: job.id)
      sendEvent("failed", payload: ["id": job.id, "error": "Geçersiz indirme adresi"])
      return
    }

    job.cancelAllWorkerTasks()
    job.flushAndCloseHandle()
    job.speedMeter.reset()
    job.probeStarted = false
    job.probeSucceeded = false
    job.receivedAnyBytesThisCycle = false
    job.lastProgressSent = 0
    job.lastMetaSavedAt = Date().timeIntervalSince1970

    let loaded = Self.loadTrackerForDestination(job.destination)
    job.tracker = loaded.tracker
    if loaded.totalBytes > 0 {
      job.totalBytes = loaded.totalBytes
    }
    if job.totalBytes > 0 && job.tracker.isComplete(totalBytes: job.totalBytes) {
      fgJobs.removeValue(forKey: job.id)
      finalizePartFile(id: job.id, destination: job.destination, knownTotal: job.totalBytes)
      return
    }
    if job.totalBytes > 0 {
      job.chunkSize = job.computeChunkSize()
    }

    // Open shared FileHandle for random-access writing.
    let partURL = Self.partFileURL(for: job.destination)
    let fm = FileManager.default
    do {
      if !fm.fileExists(atPath: partURL.path) {
        fm.createFile(atPath: partURL.path, contents: nil)
      }
      Self.markExcludedFromBackup(partURL)
      job.fileHandle = try FileHandle(forWritingTo: partURL)
    } catch {
      fgJobs.removeValue(forKey: job.id)
      sendEvent("failed", payload: ["id": job.id, "error": "Dosya açılamadı: \(error.localizedDescription)"])
      return
    }

    let existingCompleted = job.tracker.completedBytes
    if existingCompleted > 0 {
      sendEvent("progress", payload: [
        "id": job.id,
        "downloadedBytes": existingCompleted,
        "totalBytes": max(job.totalBytes, existingCompleted),
        "speedBytesPerSec": Int64(0),
        "activeConnections": 1,
      ])
    }

    // Launch primary worker 0.
    let hasMeta = loaded.totalBytes > 0 && !job.tracker.isEmpty
    var req = URLRequest(url: url)
    req.setValue(job.userAgent, forHTTPHeaderField: "User-Agent")
    req.setValue("*/*", forHTTPHeaderField: "Accept")
    req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

    let startOffset: Int64
    let endOffset: Int64
    let openEnded: Bool

    if hasMeta && job.supportsRange {
      let gaps = job.tracker.missingRanges(totalBytes: job.totalBytes)
      guard let firstGap = gaps.first else {
        job.flushAndCloseHandle()
        fgJobs.removeValue(forKey: job.id)
        finalizePartFile(id: job.id, destination: job.destination, knownTotal: job.totalBytes)
        return
      }
      startOffset = firstGap.start
      let shouldSegment = job.effectiveMaxWorkers > 1 && job.totalBytes >= Self.minSegmentedBytes
      if shouldSegment {
        endOffset = min(firstGap.end, firstGap.start + job.chunkSize)
        openEnded = false
        req.setValue("bytes=\(startOffset)-\(endOffset - 1)", forHTTPHeaderField: "Range")
      } else if firstGap.end >= job.totalBytes {
        endOffset = job.totalBytes
        openEnded = true
        req.setValue("bytes=\(startOffset)-", forHTTPHeaderField: "Range")
      } else {
        endOffset = firstGap.end
        openEnded = false
        req.setValue("bytes=\(startOffset)-\(endOffset - 1)", forHTTPHeaderField: "Range")
      }
    } else if !job.tracker.isEmpty && job.supportsRange {
      startOffset = job.tracker.maxEnd
      endOffset = job.totalBytes > 0 ? job.totalBytes : Int64.max
      openEnded = true
      req.setValue("bytes=\(startOffset)-", forHTTPHeaderField: "Range")
    } else {
      startOffset = 0
      endOffset = job.totalBytes > 0 ? job.totalBytes : Int64.max
      openEnded = true
    }

    let slot = WorkerSlot(workerId: 0, isPrimary: true, start: startOffset, end: endOffset, openEnded: openEnded)
    let task = fgSession.dataTask(with: req)
    task.taskDescription = Self.taskIdentifier(jobId: job.id, workerId: 0)
    slot.task = task
    job.workers[0] = slot
    task.resume()
  }

  private func spawnExtraWorkersIfAllowed(for job: ForegroundJob) {
    guard !isInBackground,
          job.supportsRange,
          job.totalBytes >= Self.minSegmentedBytes,
          job.effectiveMaxWorkers > 1 else {
      return
    }
    let target = job.probeSucceeded ? job.effectiveMaxWorkers : min(2, job.effectiveMaxWorkers)
    while job.workers.count < target {
      let wid = job.nextWorkerId
      job.nextWorkerId += 1
      guard let slot = claimNextSlot(for: job, workerId: wid) else { break }
      if !job.probeStarted { job.probeStarted = true }
      job.lastScaleUpAt = Date().timeIntervalSince1970
      launchExtraSlot(slot, for: job)
    }
  }

  private func launchExtraSlot(_ slot: WorkerSlot, for job: ForegroundJob) {
    let targetURL: URL
    if job.resolvedURLReusable, let resolved = job.resolvedURL, !slot.retriedOriginal {
      targetURL = resolved
      slot.usedResolvedURL = true
    } else if let orig = URL(string: job.urlString) {
      targetURL = orig
      slot.usedResolvedURL = false
    } else {
      job.workers.removeValue(forKey: slot.workerId)
      return
    }

    var req = URLRequest(url: targetURL)
    req.setValue(job.userAgent, forHTTPHeaderField: "User-Agent")
    req.setValue("*/*", forHTTPHeaderField: "Accept")
    req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
    req.setValue("bytes=\(slot.cursor)-\(slot.end - 1)", forHTTPHeaderField: "Range")

    let task = fgSession.dataTask(with: req)
    task.taskDescription = Self.taskIdentifier(jobId: job.id, workerId: slot.workerId)
    slot.task = task
    job.workers[slot.workerId] = slot
    task.resume()
  }

  private func claimNextSlot(for job: ForegroundJob, workerId: Int) -> WorkerSlot? {
    guard job.totalBytes > 0 else { return nil }
    let covered = RangeTracker()
    for r in job.tracker.ranges {
      covered.add(start: r.start, end: r.end)
    }
    for w in job.workers.values where w.cursor < w.end {
      covered.add(start: w.cursor, end: w.end)
    }

    let unclaimed = covered.missingRanges(totalBytes: job.totalBytes)
    if let gap = unclaimed.first {
      let end = min(gap.start + job.chunkSize, gap.end)
      let slot = WorkerSlot(workerId: workerId, isPrimary: false, start: gap.start, end: end, openEnded: false)
      job.workers[workerId] = slot
      return slot
    }

    // Tail work-stealing: split largest remaining active span in half so slow stragglers never stall the finish.
    var victim: WorkerSlot?
    for w in job.workers.values where w.remaining >= Self.minStealBytes * 2 {
      if victim == nil || w.remaining > victim!.remaining {
        victim = w
      }
    }
    if let v = victim {
      let mid = v.cursor + (v.remaining / 2)
      let stolenEnd = v.end
      v.end = mid
      let slot = WorkerSlot(workerId: workerId, isPrimary: false, start: mid, end: stolenEnd, openEnded: false)
      job.workers[workerId] = slot
      return slot
    }
    return nil
  }

  private func tryExtendOpenEndedSlot(_ slot: WorkerSlot, for job: ForegroundJob) -> Bool {
    guard job.totalBytes > 0, slot.end < job.totalBytes else { return false }
    let nextStart = slot.end
    let nextEnd = min(nextStart + job.chunkSize, job.totalBytes)
    guard job.tracker.isCompletelyMissing(start: nextStart, end: nextEnd) else { return false }
    for other in job.workers.values where other.workerId != slot.workerId {
      if other.cursor < nextEnd && other.end > nextStart {
        return false
      }
    }
    slot.end = nextEnd
    return true
  }

  private func flushSlotBuffer(_ slot: WorkerSlot, for job: ForegroundJob) throws {
    guard !slot.buffer.isEmpty, let handle = job.fileHandle else { return }
    try handle.seek(toOffset: UInt64(max(0, slot.writePos)))
    try handle.write(contentsOf: slot.buffer)
    let len = Int64(slot.buffer.count)
    job.tracker.add(start: slot.writePos, end: slot.writePos + len)
    slot.writePos += len
    slot.buffer.removeAll(keepingCapacity: true)
  }

  private func enqueueBackgroundSlice(
    id: String,
    urlString: String,
    destination: String,
    userAgent: String,
    baseOffset: Int64,
    sliceEndInclusive: Int64?,
    knownTotalBytes: Int64,
    supportsRange: Bool,
    maxConnections: Int
  ) {
    guard let url = URL(string: urlString) else {
      sendEvent("failed", payload: ["id": id, "error": "Geçersiz indirme adresi"])
      return
    }

    var req = URLRequest(url: url)
    req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    req.setValue("*/*", forHTTPHeaderField: "Accept")
    req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

    if supportsRange, let end = sliceEndInclusive, end >= baseOffset {
      req.setValue("bytes=\(baseOffset)-\(end)", forHTTPHeaderField: "Range")
    }

    let meta = BgTaskMeta(
      id: id,
      url: urlString,
      destination: destination,
      userAgent: userAgent,
      baseOffset: baseOffset,
      expectedSliceEnd: supportsRange ? sliceEndInclusive : nil,
      knownTotalBytes: knownTotalBytes,
      supportsRange: supportsRange,
      maxConnections: maxConnections
    )
    let task = bgSession.downloadTask(with: req)
    task.taskDescription = Self.encodeMeta(meta)
    bgTasksById[id] = task
    bgMetaById[id] = meta
    lastBgProgressSent.removeValue(forKey: id)
    lastBgProgressBytes[id] = Self.loadTrackerForDestination(destination).tracker.completedBytes
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
        job.flushAndCloseHandle()
        job.cancelAllWorkerTasks()
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
      self.handoffToFgIds.remove(id)
      self.bgRetryCounts.removeValue(forKey: id)

      var dest = destination
      if let job = self.fgJobs.removeValue(forKey: id) {
        dest = dest ?? job.destination
        job.retryWorkItem?.cancel()
        job.retryWorkItem = nil
        job.cancelAllWorkerTasks()
        if let handle = job.fileHandle {
          try? handle.close()
          job.fileHandle = nil
        }
      }
      if let bgTask = self.bgTasksById.removeValue(forKey: id) {
        dest = dest ?? self.bgMetaById.removeValue(forKey: id)?.destination
        bgTask.cancel()
      } else {
        dest = dest ?? self.bgMetaById.removeValue(forKey: id)?.destination
      }

      if let dest = dest {
        try? FileManager.default.removeItem(at: Self.partFileURL(for: dest))
        try? FileManager.default.removeItem(at: Self.metaFileURL(for: dest))
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
          let persisted = Self.loadTrackerForDestination(meta.destination)
          let total = max(meta.knownTotalBytes, persisted.totalBytes)
          let effectiveTotal = total > 0 ? total : (meta.baseOffset + max(0, dl.countOfBytesExpectedToReceive))
          list.append([
            "id": meta.id,
            "destination": meta.destination,
            "state": stateStr,
            "downloadedBytes": persisted.tracker.completedBytes + dl.countOfBytesReceived,
            "totalBytes": effectiveTotal,
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
      if updated.value(forHTTPHeaderField: "Accept-Encoding") == nil {
        updated.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
      }
      if updated.value(forHTTPHeaderField: "Accept") == nil {
        updated.setValue("*/*", forHTTPHeaderField: "Accept")
      }
    }
    completionHandler(updated)
  }

  // MARK: - Foreground URLSessionDataDelegate (Multi-Connection Segmented Streaming)

  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    guard session === fgSession, let parsed = Self.parseTaskIdentifier(dataTask.taskDescription) else {
      completionHandler(.allow)
      return
    }
    stateQueue.async {
      guard let job = self.fgJobs[parsed.jobId],
            let slot = job.workers[parsed.workerId],
            slot.task === dataTask else {
        completionHandler(.cancel)
        return
      }
      guard let http = response as? HTTPURLResponse else {
        completionHandler(.allow)
        return
      }

      // Extra worker response handling (safe auto-fallback, never fails the download).
      if !slot.isPrimary {
        if (http.statusCode == 401 || http.statusCode == 403 || http.statusCode == 404 || http.statusCode == 410),
           slot.usedResolvedURL, !slot.retriedOriginal {
          job.resolvedURLReusable = false
          slot.retriedOriginal = true
          slot.cancelledByPool = true
          completionHandler(.cancel)
          self.launchExtraSlot(slot, for: job)
          return
        }
        if http.statusCode == 200 {
          // Server ignored Range header.
          job.supportsRange = false
          job.effectiveMaxWorkers = 1
          slot.cancelledByPool = true
          job.workers.removeValue(forKey: slot.workerId)
          completionHandler(.cancel)
          return
        }
        if http.statusCode != 206 {
          let isLimit = [401, 403, 429, 503, 509].contains(http.statusCode)
          slot.cancelledByPool = true
          job.workers.removeValue(forKey: slot.workerId)
          if isLimit {
            job.effectiveMaxWorkers = max(1, job.workers.count)
          }
          completionHandler(.cancel)
          return
        }
        slot.streaming = true
        completionHandler(.allow)
        return
      }

      // Primary worker 0 response handling.
      if let finalURL = response.url {
        job.resolvedURL = finalURL
      }

      if http.statusCode == 416 && slot.start > 0 {
        if let total = Self.parseContentRangeTotal(http.value(forHTTPHeaderField: "Content-Range")),
           total > 0 && job.tracker.completedBytes >= total {
          job.flushAndCloseHandle()
          self.fgJobs.removeValue(forKey: job.id)
          completionHandler(.cancel)
          self.finalizePartFile(id: job.id, destination: job.destination, knownTotal: total)
          return
        }
        // Server file changed; reset .part + .part.meta and restart cleanly from 0.
        job.flushAndCloseHandle()
        try? FileManager.default.removeItem(at: Self.partFileURL(for: job.destination))
        try? FileManager.default.removeItem(at: Self.metaFileURL(for: job.destination))
        job.totalBytes = 0
        job.tracker.clear()
        completionHandler(.cancel)
        self.startForegroundCycle(for: job)
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
        job.flushAndCloseHandle()
        job.cancelAllWorkerTasks()
        self.fgJobs.removeValue(forKey: job.id)
        completionHandler(.cancel)
        self.sendEvent("failed", payload: ["id": job.id, "error": msg])
        return
      }

      if let acceptRanges = http.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased(),
         acceptRanges == "none" {
        job.supportsRange = false
        job.effectiveMaxWorkers = 1
      }

      if isPartial {
        if let parsedTotal = Self.parseContentRangeTotal(http.value(forHTTPHeaderField: "Content-Range")),
           parsedTotal > 0 {
          if job.totalBytes > 0 && job.totalBytes != parsedTotal {
            job.flushAndCloseHandle()
            try? FileManager.default.removeItem(at: Self.partFileURL(for: job.destination))
            try? FileManager.default.removeItem(at: Self.metaFileURL(for: job.destination))
            job.totalBytes = 0
            job.tracker.clear()
            completionHandler(.cancel)
            self.startForegroundCycle(for: job)
            return
          }
          job.totalBytes = parsedTotal
        } else if response.expectedContentLength > 0 && job.totalBytes == 0 {
          job.totalBytes = slot.start + response.expectedContentLength
        }
      } else {
        // 200 OK: fresh download OR server does not support Range.
        if slot.start > 0 {
          job.supportsRange = false
          job.effectiveMaxWorkers = 1
          job.tracker.clear()
          try? job.fileHandle?.truncate(atOffset: 0)
        }
        slot.start = 0
        slot.cursor = 0
        slot.writePos = 0
        if response.expectedContentLength > 0 {
          job.totalBytes = response.expectedContentLength
        }
      }

      if job.totalBytes > 0 {
        job.chunkSize = job.computeChunkSize()
        if slot.openEnded {
          slot.end = (job.supportsRange && job.effectiveMaxWorkers > 1 && job.totalBytes >= Self.minSegmentedBytes)
            ? min(slot.start + job.chunkSize, job.totalBytes)
            : job.totalBytes
        }
      }

      slot.streaming = true
      job.retryCount = 0
      completionHandler(.allow)

      // Ramp up Probe Worker 1 if file is eligible for parallel Range downloading.
      if job.supportsRange && job.effectiveMaxWorkers > 1 && job.totalBytes >= Self.minSegmentedBytes {
        self.spawnExtraWorkersIfAllowed(for: job)
      }
    }
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    guard session === fgSession, let parsed = Self.parseTaskIdentifier(dataTask.taskDescription) else { return }
    stateQueue.async {
      guard let job = self.fgJobs[parsed.jobId],
            let slot = job.workers[parsed.workerId],
            slot.task === dataTask else { return }
      guard !data.isEmpty else { return }

      var remaining = slot.end - slot.cursor
      if remaining <= 0 && slot.openEnded && job.totalBytes > 0 {
        if self.tryExtendOpenEndedSlot(slot, for: job) {
          remaining = slot.end - slot.cursor
        }
      }
      if remaining <= 0 {
        slot.cancelledByPool = true
        dataTask.cancel()
        self.finishWorkerSlotCleanly(slot, for: job)
        return
      }

      let takeLen = min(Int64(data.count), remaining)
      if takeLen == Int64(data.count) {
        slot.buffer.append(data)
      } else {
        slot.buffer.append(data.prefix(Int(takeLen)))
      }
      slot.cursor += takeLen
      slot.receivedBytes += takeLen
      job.receivedAnyBytesThisCycle = true

      let now = Date().timeIntervalSince1970
      job.speedMeter.add(bytes: takeLen, now: now)

      if !slot.isPrimary && !slot.firedFirstBytes && slot.receivedBytes >= 8 * 1024 {
        slot.firedFirstBytes = true
        if !job.probeSucceeded && !job.singleConnKickDetected {
          job.probeSucceeded = true
          self.spawnExtraWorkersIfAllowed(for: job)
        }
      }

      if slot.buffer.count >= Self.writeBufferBytes {
        do {
          try self.flushSlotBuffer(slot, for: job)
        } catch {
          job.flushAndCloseHandle()
          job.cancelAllWorkerTasks()
          self.fgJobs.removeValue(forKey: job.id)
          self.sendEvent("failed", payload: ["id": job.id, "error": "Disk yazma hatası: \(error.localizedDescription)"])
          return
        }
      }

      if job.totalBytes > 0 && (now - job.lastMetaSavedAt) >= 1.5 {
        job.lastMetaSavedAt = now
        job.flushAllBuffers()
        job.tracker.save(to: Self.metaFileURL(for: job.destination), totalBytes: job.totalBytes)
      }

      if job.lastProgressSent == 0 || (now - job.lastProgressSent) >= 0.25 {
        job.lastProgressSent = now
        let speed = job.speedMeter.bytesPerSecond(now: now)
        self.sendEvent("progress", payload: [
          "id": job.id,
          "downloadedBytes": job.liveCompletedBytes(),
          "totalBytes": max(0, job.totalBytes),
          "speedBytesPerSec": speed,
          "activeConnections": job.activeStreamingCount(),
        ])
      }

      if slot.cursor >= slot.end {
        if slot.openEnded && job.totalBytes > 0 && self.tryExtendOpenEndedSlot(slot, for: job) {
          return
        }
        slot.cancelledByPool = true
        dataTask.cancel()
        self.finishWorkerSlotCleanly(slot, for: job)
      }
    }
  }

  private func finishWorkerSlotCleanly(_ slot: WorkerSlot, for job: ForegroundJob) {
    do {
      try flushSlotBuffer(slot, for: job)
    } catch {
      job.flushAndCloseHandle()
      job.cancelAllWorkerTasks()
      fgJobs.removeValue(forKey: job.id)
      sendEvent("failed", payload: ["id": job.id, "error": "Disk yazma hatası: \(error.localizedDescription)"])
      return
    }

    if !slot.isPrimary && !slot.firedFirstBytes && slot.receivedBytes > 0 {
      slot.firedFirstBytes = true
      if !job.probeSucceeded && !job.singleConnKickDetected {
        job.probeSucceeded = true
      }
    }

    job.workers.removeValue(forKey: slot.workerId)
    if job.totalBytes > 0 {
      job.tracker.save(to: Self.metaFileURL(for: job.destination), totalBytes: job.totalBytes)
    }

    if job.totalBytes > 0 && job.tracker.isComplete(totalBytes: job.totalBytes) {
      job.flushAndCloseHandle()
      job.cancelAllWorkerTasks()
      fgJobs.removeValue(forKey: job.id)
      finalizePartFile(id: job.id, destination: job.destination, knownTotal: job.totalBytes)
      return
    }

    // Grab the next missing chunk for this worker slot (or let primary join the bounded pool).
    if job.supportsRange && job.totalBytes > 0 && job.workers.count < job.effectiveMaxWorkers {
      let wid = job.nextWorkerId
      job.nextWorkerId += 1
      if let nextSlot = claimNextSlot(for: job, workerId: wid) {
        launchExtraSlot(nextSlot, for: job)
      }
      spawnExtraWorkersIfAllowed(for: job)
    } else if job.workers.isEmpty && job.totalBytes == 0 {
      // Unknown Content-Length stream reached EOF cleanly.
      let diskSize = Self.partFileSize(for: job.destination)
      job.flushAndCloseHandle()
      fgJobs.removeValue(forKey: job.id)
      finalizePartFile(id: job.id, destination: job.destination, knownTotal: diskSize)
    }
  }

  // MARK: - Background URLSessionDownloadDelegate (64 MiB Slices Written at Exact Offset)

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

      let persisted = Self.loadTrackerForDestination(meta.destination)
      let combinedDownloaded = persisted.tracker.completedBytes + totalBytesWritten
      var combinedTotal = max(meta.knownTotalBytes, persisted.totalBytes)
      if combinedTotal <= 0 {
        if let http = downloadTask.response as? HTTPURLResponse,
           let parsedTotal = Self.parseContentRangeTotal(http.value(forHTTPHeaderField: "Content-Range")),
           parsedTotal > 0 {
          combinedTotal = parsedTotal
        } else if totalBytesExpectedToWrite > 0 {
          combinedTotal = meta.baseOffset + totalBytesExpectedToWrite
        }
      }

      let prevBytes = self.lastBgProgressBytes[meta.id] ?? persisted.tracker.completedBytes
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
        "activeConnections": 1,
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
    let metaURL = Self.metaFileURL(for: meta.destination)
    let fm = FileManager.default

    do {
      let parent = partURL.deletingLastPathComponent()
      if !fm.fileExists(atPath: parent.path) {
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
      }
      Self.markExcludedFromBackup(parent)

      if !isPartial {
        // Server sent 200 OK (full file): replace destination directly.
        let destURL = URL(fileURLWithPath: meta.destination)
        if fm.fileExists(atPath: destURL.path) { try fm.removeItem(at: destURL) }
        try fm.moveItem(at: location, to: destURL)
        Self.markExcludedFromBackup(destURL)
        try? fm.removeItem(at: partURL)
        try? fm.removeItem(at: metaURL)
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

      // Write partial slice into .part at exact `meta.baseOffset` WITHOUT truncating higher ranges.
      let written = try Self.writeSlice(from: location, to: partURL, atOffset: meta.baseOffset)
      let loaded = Self.loadTrackerForDestination(meta.destination)
      let effectiveTotal = max(totalBytes, loaded.totalBytes)
      loaded.tracker.add(start: meta.baseOffset, end: meta.baseOffset + written)
      if effectiveTotal > 0 {
        loaded.tracker.save(to: metaURL, totalBytes: effectiveTotal)
      }

      let done = (effectiveTotal > 0 && loaded.tracker.isComplete(totalBytes: effectiveTotal))
        || meta.expectedSliceEnd == nil

      stateQueue.async {
        self.bgTasksById.removeValue(forKey: meta.id)
        self.bgMetaById.removeValue(forKey: meta.id)
        self.bgRetryCounts.removeValue(forKey: meta.id)
        self.lastBgProgressSent.removeValue(forKey: meta.id)
        self.lastBgProgressBytes.removeValue(forKey: meta.id)

        if self.pausingIds.contains(meta.id) || self.cancellingIds.contains(meta.id) || self.handoffToFgIds.remove(meta.id) != nil {
          return
        }

        if done {
          self.finalizePartFile(id: meta.id, destination: meta.destination, knownTotal: max(effectiveTotal, loaded.tracker.completedBytes))
        } else if self.isInBackground {
          let nextGap = self.nextMissingBackgroundSlice(
            destination: meta.destination,
            knownTotalBytes: effectiveTotal,
            supportsRange: true
          )
          self.enqueueBackgroundSlice(
            id: meta.id,
            urlString: meta.url,
            destination: meta.destination,
            userAgent: meta.userAgent,
            baseOffset: nextGap.start,
            sliceEndInclusive: nextGap.endInclusive,
            knownTotalBytes: nextGap.totalBytes,
            supportsRange: true,
            maxConnections: meta.maxConnections ?? 6
          )
        } else {
          let job = ForegroundJob(
            id: meta.id,
            urlString: meta.url,
            destination: meta.destination,
            userAgent: meta.userAgent,
            totalBytes: effectiveTotal,
            maxConnections: meta.maxConnections ?? 6
          )
          self.fgJobs[meta.id] = job
          self.startForegroundCycle(for: job)
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

  /// Streams bytes from `source` into `destination` at exact `atOffset` using a 256 KiB buffer
  /// without truncating any bytes beyond the slice (preserving parallel foreground segments).
  private static func writeSlice(from source: URL, to destination: URL, atOffset offset: Int64) throws -> Int64 {
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
    try writer.seek(toOffset: UInt64(max(0, offset)))

    var written: Int64 = 0
    let bufferSize = 256 * 1024
    while true {
      let chunk = try autoreleasepool { () -> Data? in
        try reader.read(upToCount: bufferSize)
      }
      guard let data = chunk, !data.isEmpty else { break }
      try writer.write(contentsOf: data)
      written += Int64(data.count)
    }
    return written
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
    guard let parsed = Self.parseTaskIdentifier(task.taskDescription) else { return }
    stateQueue.async {
      guard let job = self.fgJobs[parsed.jobId] else {
        self.pausingIds.remove(parsed.jobId)
        self.cancellingIds.remove(parsed.jobId)
        return
      }
      guard let slot = job.workers[parsed.workerId], slot.task === task else { return }

      if slot.cancelledByPool {
        return
      }

      try? self.flushSlotBuffer(slot, for: job)
      if job.totalBytes > 0 {
        job.tracker.save(to: Self.metaFileURL(for: job.destination), totalBytes: job.totalBytes)
      }

      if self.pausingIds.remove(job.id) != nil {
        job.flushAndCloseHandle()
        job.cancelAllWorkerTasks()
        self.fgJobs.removeValue(forKey: job.id)
        return
      }
      if self.cancellingIds.remove(job.id) != nil {
        job.cancelAllWorkerTasks()
        self.fgJobs.removeValue(forKey: job.id)
        return
      }

      if let error = error {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
          return
        }

        // Detect strict 1-connection IPTV server kicking Primary Worker 0 right after ramp-up.
        let now = Date().timeIntervalSince1970
        let recentlyScaledUp = job.lastScaleUpAt > 0 && (now - job.lastScaleUpAt) <= 3.5
        if slot.isPrimary && recentlyScaledUp && job.effectiveMaxWorkers > 1 {
          job.singleConnKickDetected = true
          job.effectiveMaxWorkers = 1
          job.probeSucceeded = false
          job.workers.removeValue(forKey: slot.workerId)
          if job.workers.isEmpty {
            self.startForegroundCycle(for: job)
          }
          return
        }

        // If an extra worker failed while other workers are still healthy, simply back off concurrency!
        if !slot.isPrimary && job.workers.count > 1 {
          job.workers.removeValue(forKey: slot.workerId)
          job.effectiveMaxWorkers = max(1, job.workers.count)
          return
        }

        job.workers.removeValue(forKey: slot.workerId)
        if !job.workers.isEmpty {
          return
        }

        if Self.isRecoverableNetworkError(nsError) && job.retryCount < Self.maxAutoRetries {
          if job.receivedAnyBytesThisCycle { job.retryCount = 0 }
          job.retryCount += 1
          let delay = min(8.0, pow(1.5, Double(job.retryCount)))
          let work = DispatchWorkItem { [weak self] in
            guard let self = self, let current = self.fgJobs[job.id], current === job else { return }
            self.startForegroundCycle(for: current)
          }
          job.retryWorkItem = work
          self.stateQueue.asyncAfter(deadline: .now() + delay, execute: work)
          return
        }

        job.flushAndCloseHandle()
        self.fgJobs.removeValue(forKey: job.id)
        self.sendEvent("failed", payload: ["id": job.id, "error": error.localizedDescription])
        return
      }

      // Stream ended without an explicit URLSession error: check whether this slot finished its range.
      if job.totalBytes > 0 && slot.cursor < slot.end {
        // Premature EOF before span end!
        let now = Date().timeIntervalSince1970
        let recentlyScaledUp = job.lastScaleUpAt > 0 && (now - job.lastScaleUpAt) <= 3.5
        if slot.isPrimary && recentlyScaledUp && job.effectiveMaxWorkers > 1 {
          job.singleConnKickDetected = true
          job.effectiveMaxWorkers = 1
          job.probeSucceeded = false
          job.workers.removeValue(forKey: slot.workerId)
          if job.workers.isEmpty {
            self.startForegroundCycle(for: job)
          }
          return
        }
        job.workers.removeValue(forKey: slot.workerId)
        if !job.workers.isEmpty {
          return
        }
        if job.retryCount < Self.maxAutoRetries {
          if job.receivedAnyBytesThisCycle { job.retryCount = 0 }
          job.retryCount += 1
          let delay = min(6.0, Double(job.retryCount) * 1.5)
          let work = DispatchWorkItem { [weak self] in
            guard let self = self, let current = self.fgJobs[job.id], current === job else { return }
            self.startForegroundCycle(for: current)
          }
          job.retryWorkItem = work
          self.stateQueue.asyncAfter(deadline: .now() + delay, execute: work)
          return
        }
        job.flushAndCloseHandle()
        self.fgJobs.removeValue(forKey: job.id)
        self.sendEvent("failed", payload: ["id": job.id, "error": "Bağlantı indirme bitmeden kesildi"])
        return
      }

      self.finishWorkerSlotCleanly(slot, for: job)
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

      if self.pausingIds.remove(meta.id) != nil { return }
      if self.cancellingIds.remove(meta.id) != nil { return }
      if self.handoffToFgIds.remove(meta.id) != nil { return }
      if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }

      let retries = (self.bgRetryCounts[meta.id] ?? 0) + 1
      if Self.isRecoverableNetworkError(nsError) && retries <= Self.maxAutoRetries {
        self.bgRetryCounts[meta.id] = retries
        if self.isInBackground {
          let gap = self.nextMissingBackgroundSlice(
            destination: meta.destination,
            knownTotalBytes: meta.knownTotalBytes,
            supportsRange: meta.supportsRange
          )
          self.enqueueBackgroundSlice(
            id: meta.id,
            urlString: meta.url,
            destination: meta.destination,
            userAgent: meta.userAgent,
            baseOffset: gap.start,
            sliceEndInclusive: gap.endInclusive,
            knownTotalBytes: gap.totalBytes,
            supportsRange: meta.supportsRange,
            maxConnections: meta.maxConnections ?? 6
          )
        } else if self.fgJobs[meta.id] == nil {
          let job = ForegroundJob(
            id: meta.id,
            urlString: meta.url,
            destination: meta.destination,
            userAgent: meta.userAgent,
            totalBytes: meta.knownTotalBytes,
            maxConnections: meta.maxConnections ?? 6
          )
          self.fgJobs[meta.id] = job
          self.startForegroundCycle(for: job)
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
    let metaURL = Self.metaFileURL(for: destination)
    let destURL = URL(fileURLWithPath: destination)
    do {
      try? fm.removeItem(at: metaURL)
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

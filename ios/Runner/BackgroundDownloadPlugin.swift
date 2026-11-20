import Flutter
import Foundation
import UIKit

/// Native iOS background download bridge powered by `URLSessionConfiguration.background`.
///
/// Downloads continue reliably when the screen locks or the user switches apps.
/// Files are saved under the app's `Documents/IPTV` directory (visible in the iOS
/// Files app via `UIFileSharingEnabled`) and marked `isExcludedFromBackup = true`
/// so large videos never consume the user's iCloud backup quota.
final class BackgroundDownloadPlugin: NSObject, FlutterPlugin, URLSessionDownloadDelegate {
  private static let channelName = "iptv/background_downloads"
  private static var sharedInstance: BackgroundDownloadPlugin?
  private static var pendingCompletionHandlers: [String: () -> Void] = [:]

  private var channel: FlutterMethodChannel?
  private var session: URLSession!
  private let stateQueue = DispatchQueue(label: "com.iptv.downloads.state")

  private var tasksById: [String: URLSessionDownloadTask] = [:]
  private var pausingIds: Set<String> = []
  private var cancellingIds: Set<String> = []
  private var lastProgressSent: [String: TimeInterval] = [:]
  private var lastProgressBytes: [String: Int64] = [:]

  static var sessionIdentifier: String {
    let bundle = Bundle.main.bundleIdentifier ?? "com.iptv.app"
    return "\(bundle).backgroundDownloads"
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
      Self.pendingCompletionHandlers[identifier] = completionHandler
    }
    return true
  }

  private override init() {
    super.init()
    let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
    config.isDiscretionary = false
    config.sessionSendsLaunchEvents = true
    config.allowsCellularAccess = true
    config.waitsForConnectivity = true
    config.httpMaximumConnectionsPerHost = 1
    self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    rehydrateTasks()
  }

  private func rehydrateTasks() {
    session.getAllTasks { [weak self] tasks in
      guard let self = self else { return }
      self.stateQueue.async {
        for task in tasks {
          guard let dl = task as? URLSessionDownloadTask,
                let meta = Self.parseMeta(dl.taskDescription) else { continue }
          self.tasksById[meta.id] = dl
        }
      }
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
      startDownload(id: id, urlString: urlStr, destination: destination, userAgent: userAgent)
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

  // MARK: - Directory & Metadata

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

  private static func resumeFileURL(for destination: String) -> URL {
    URL(fileURLWithPath: destination + ".resume")
  }

  private struct TaskMeta: Codable {
    let id: String
    let destination: String
  }

  private static func encodeMeta(id: String, destination: String) -> String? {
    guard let data = try? JSONEncoder().encode(TaskMeta(id: id, destination: destination)) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  private static func parseMeta(_ raw: String?) -> TaskMeta? {
    guard let raw = raw, let data = raw.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(TaskMeta.self, from: data)
  }

  // MARK: - Task Control

  private func startDownload(id: String, urlString: String, destination: String, userAgent: String) {
    guard let url = URL(string: urlString) else {
      sendEvent("failed", payload: ["id": id, "error": "Geçersiz indirme adresi"])
      return
    }
    let destURL = URL(fileURLWithPath: destination)
    let parentDir = destURL.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
    Self.markExcludedFromBackup(parentDir)

    stateQueue.async {
      if let existing = self.tasksById[id] {
        if existing.state == .running { return }
        if existing.state == .suspended {
          existing.resume()
          return
        }
      }
      self.pausingIds.remove(id)
      self.cancellingIds.remove(id)
      self.lastProgressSent.removeValue(forKey: id)
      self.lastProgressBytes.removeValue(forKey: id)

      let resumeURL = Self.resumeFileURL(for: destination)
      let task: URLSessionDownloadTask
      if let resumeData = try? Data(contentsOf: resumeURL), !resumeData.isEmpty {
        try? FileManager.default.removeItem(at: resumeURL)
        task = self.session.downloadTask(withResumeData: resumeData)
      } else {
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        task = self.session.downloadTask(with: req)
      }
      task.taskDescription = Self.encodeMeta(id: id, destination: destination)
      self.tasksById[id] = task
      task.resume()
    }
  }

  private func pauseDownload(id: String, destination: String?, completion: @escaping (Bool) -> Void) {
    stateQueue.async {
      guard let task = self.tasksById[id] else {
        completion(false)
        return
      }
      self.pausingIds.insert(id)
      let dest = destination ?? Self.parseMeta(task.taskDescription)?.destination
      task.cancel { resumeData in
        if let data = resumeData, !data.isEmpty, let dest = dest {
          let resumeURL = Self.resumeFileURL(for: dest)
          try? data.write(to: resumeURL, options: .atomic)
          Self.markExcludedFromBackup(resumeURL)
        }
        self.stateQueue.async {
          self.tasksById.removeValue(forKey: id)
        }
        completion(true)
      }
    }
  }

  private func cancelDownload(id: String, destination: String?) {
    stateQueue.async {
      self.cancellingIds.insert(id)
      self.pausingIds.remove(id)
      if let task = self.tasksById.removeValue(forKey: id) {
        let dest = destination ?? Self.parseMeta(task.taskDescription)?.destination
        task.cancel()
        if let dest = dest {
          try? FileManager.default.removeItem(at: Self.resumeFileURL(for: dest))
        }
      } else if let dest = destination {
        try? FileManager.default.removeItem(at: Self.resumeFileURL(for: dest))
      }
    }
  }

  private func syncTasks(completion: @escaping ([[String: Any]]) -> Void) {
    session.getAllTasks { [weak self] tasks in
      guard let self = self else {
        completion([])
        return
      }
      self.stateQueue.async {
        var list: [[String: Any]] = []
        for task in tasks {
          guard let dl = task as? URLSessionDownloadTask,
                let meta = Self.parseMeta(dl.taskDescription) else { continue }
          self.tasksById[meta.id] = dl
          let stateStr: String
          switch dl.state {
          case .running: stateStr = "downloading"
          case .suspended: stateStr = "paused"
          case .canceling: stateStr = "canceling"
          case .completed: stateStr = "completed"
          @unknown default: stateStr = "downloading"
          }
          list.append([
            "id": meta.id,
            "destination": meta.destination,
            "state": stateStr,
            "downloadedBytes": dl.countOfBytesReceived,
            "totalBytes": max(0, dl.countOfBytesExpectedToReceive),
          ])
        }
        completion(list)
      }
    }
  }

  // MARK: - URLSessionDownloadDelegate

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard let meta = Self.parseMeta(downloadTask.taskDescription) else { return }
    let now = Date().timeIntervalSince1970
    stateQueue.async {
      let prevTime = self.lastProgressSent[meta.id] ?? 0
      let elapsed = now - prevTime
      if prevTime > 0 && elapsed < 0.25 { return }
      let prevBytes = self.lastProgressBytes[meta.id] ?? 0
      let speed: Int64 = (prevTime > 0 && elapsed > 0.05)
        ? Int64(Double(max(0, totalBytesWritten - prevBytes)) / elapsed)
        : 0
      self.lastProgressSent[meta.id] = now
      self.lastProgressBytes[meta.id] = totalBytesWritten
      self.sendEvent("progress", payload: [
        "id": meta.id,
        "downloadedBytes": totalBytesWritten,
        "totalBytes": max(0, totalBytesExpectedToWrite),
        "speedBytesPerSec": speed,
      ])
    }
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    guard let meta = Self.parseMeta(downloadTask.taskDescription) else { return }
    if let http = downloadTask.response as? HTTPURLResponse, http.statusCode >= 400 {
      stateQueue.async {
        self.tasksById.removeValue(forKey: meta.id)
      }
      sendEvent("failed", payload: [
        "id": meta.id,
        "error": "Sunucu HTTP \(http.statusCode) döndürdü",
      ])
      return
    }

    let fm = FileManager.default
    let destURL = URL(fileURLWithPath: meta.destination)
    do {
      let parent = destURL.deletingLastPathComponent()
      if !fm.fileExists(atPath: parent.path) {
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
      }
      if fm.fileExists(atPath: destURL.path) {
        try fm.removeItem(at: destURL)
      }
      try fm.moveItem(at: location, to: destURL)
      Self.markExcludedFromBackup(destURL)
      try? fm.removeItem(at: Self.resumeFileURL(for: meta.destination))

      let attrs = try? fm.attributesOfItem(atPath: destURL.path)
      let fileSize = (attrs?[.size] as? NSNumber)?.int64Value ?? downloadTask.countOfBytesReceived

      stateQueue.async {
        self.tasksById.removeValue(forKey: meta.id)
        self.pausingIds.remove(meta.id)
        self.cancellingIds.remove(meta.id)
        self.lastProgressSent.removeValue(forKey: meta.id)
        self.lastProgressBytes.removeValue(forKey: meta.id)
      }
      sendEvent("completed", payload: [
        "id": meta.id,
        "filePath": destURL.path,
        "totalBytes": fileSize,
      ])
    } catch {
      stateQueue.async {
        self.tasksById.removeValue(forKey: meta.id)
      }
      sendEvent("failed", payload: [
        "id": meta.id,
        "error": "Dosya kaydedilemedi: \(error.localizedDescription)",
      ])
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let error = error, let meta = Self.parseMeta(task.taskDescription) else { return }
    let nsError = error as NSError
    stateQueue.async {
      self.tasksById.removeValue(forKey: meta.id)
      self.lastProgressSent.removeValue(forKey: meta.id)
      self.lastProgressBytes.removeValue(forKey: meta.id)

      if self.pausingIds.remove(meta.id) != nil {
        self.sendEvent("paused", payload: ["id": meta.id])
        return
      }
      if self.cancellingIds.remove(meta.id) != nil {
        return
      }
      if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
        return
      }
      if let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data, !resumeData.isEmpty {
        let resumeURL = Self.resumeFileURL(for: meta.destination)
        try? resumeData.write(to: resumeURL, options: .atomic)
        Self.markExcludedFromBackup(resumeURL)
      }
      self.sendEvent("failed", payload: [
        "id": meta.id,
        "error": error.localizedDescription,
      ])
    }
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

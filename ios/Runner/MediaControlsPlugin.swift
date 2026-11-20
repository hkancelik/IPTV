import AVFoundation
import Flutter
import MediaPlayer
import UIKit

/// Bridges Flutter playback state with iOS Lock Screen, Control Center, Dynamic Island,
/// CarPlay, and AirPods via `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`.
final class MediaControlsPlugin: NSObject, FlutterPlugin {
  private static let channelName = "iptv/system_media_controls"
  private static let maxArtworkCacheEntries = 16
  private static let maxArtworkBytes = 8 * 1024 * 1024

  private let channel: FlutterMethodChannel
  private let artworkSession: URLSession

  private var commandsRegistered = false
  private var commandTargets: [(MPRemoteCommand, Any)] = []

  // Current playback snapshot
  private var isActive = false
  private var title: String = ""
  private var subtitle: String = ""
  private var album: String = ""
  private var currentArtUrl: String = ""
  private var isLive = false
  private var isPlaying = false
  private var positionMs: Int64 = 0
  private var durationMs: Int64 = 0
  private var rate: Double = 1.0
  private var canGoNext = false
  private var canGoPrevious = false
  private var canSeek = false
  private var skipSeconds: Int = 10
  private var userAgent: String = "VLC/3.0.20 LibVLC/3.0.20"

  // Artwork cache (main thread only)
  private var artworkCache: [String: UIImage] = [:]
  private var artworkOrder: [String] = []
  private var currentArtworkImage: UIImage?
  private var artworkTask: URLSessionDataTask?
  private var cachedFallbackIcon: UIImage?
  private var loadedFallbackIcon = false

  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "MediaControlsPlugin") else { return }
    register(with: registrar)
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    let instance = MediaControlsPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  private init(channel: FlutterMethodChannel) {
    self.channel = channel
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 10
    config.timeoutIntervalForResource = 15
    config.urlCache = URLCache.shared
    self.artworkSession = URLSession(configuration: config)
    super.init()
    observeAudioSession()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    artworkTask?.cancel()
    artworkSession.invalidateAndCancel()
    for (command, target) in commandTargets {
      command.removeTarget(target)
    }
    commandTargets.removeAll()
  }

  // MARK: - Flutter MethodChannel

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "update":
        let args = call.arguments as? [String: Any] ?? [:]
        self.handleUpdate(args)
        result(nil)
      case "seeked":
        let args = call.arguments as? [String: Any] ?? [:]
        self.handleSeeked(args)
        result(nil)
      case "clear":
        self.handleClear()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func handleUpdate(_ args: [String: Any]) {
    let wasActive = isActive
    isActive = true

    title = (args["title"] as? String) ?? ""
    subtitle = (args["subtitle"] as? String) ?? ""
    album = (args["album"] as? String) ?? ""
    isLive = (args["live"] as? Bool) ?? false
    isPlaying = (args["playing"] as? Bool) ?? false
    positionMs = max(Int64(0), (args["positionMs"] as? NSNumber)?.int64Value ?? 0)
    durationMs = max(Int64(0), (args["durationMs"] as? NSNumber)?.int64Value ?? 0)
    let incomingRate = (args["rate"] as? NSNumber)?.doubleValue ?? 1.0
    rate = incomingRate > 0 ? incomingRate : 1.0
    canGoNext = (args["canGoNext"] as? Bool) ?? false
    canGoPrevious = (args["canGoPrevious"] as? Bool) ?? false
    canSeek = (args["canSeek"] as? Bool) ?? false
    let incomingSkip = (args["skipSeconds"] as? NSNumber)?.intValue ?? 10
    skipSeconds = max(5, min(60, incomingSkip))
    if let ua = args["userAgent"] as? String, !ua.isEmpty {
      userAgent = ua
    }

    if !wasActive {
      activateAudioSession()
      registerRemoteCommandsIfNeeded()
    }

    let nextArtUrl = ((args["artUrl"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    updateArtworkIfNeeded(for: nextArtUrl)
    syncRemoteCommandAvailability()
    applyNowPlayingInfo()
  }

  private func handleSeeked(_ args: [String: Any]) {
    guard isActive else { return }
    positionMs = max(Int64(0), (args["positionMs"] as? NSNumber)?.int64Value ?? positionMs)
    applyNowPlayingInfo()
  }

  private func handleClear() {
    isActive = false
    isPlaying = false
    currentArtUrl = ""
    currentArtworkImage = nil
    artworkTask?.cancel()
    artworkTask = nil

    disableAllRemoteCommands()

    let center = MPNowPlayingInfoCenter.default()
    center.nowPlayingInfo = nil
    center.playbackState = .stopped

    do {
      try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    } catch {
      // Non-fatal: another audio subsystem may still hold the session.
    }
  }

  // MARK: - Audio Session

  private func activateAudioSession() {
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .moviePlayback)
      try session.setActive(true)
    } catch {
      // Non-fatal: mpv / AVPlayer will configure audio on playback start.
    }
  }

  private func observeAudioSession() {
    let nc = NotificationCenter.default
    nc.addObserver(
      self,
      selector: #selector(handleAudioInterruption(_:)),
      name: AVAudioSession.interruptionNotification,
      object: AVAudioSession.sharedInstance()
    )
    nc.addObserver(
      self,
      selector: #selector(handleRouteChange(_:)),
      name: AVAudioSession.routeChangeNotification,
      object: AVAudioSession.sharedInstance()
    )
  }

  @objc private func handleAudioInterruption(_ notification: Notification) {
    guard let info = notification.userInfo,
          let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else {
      return
    }
    var shouldResume = false
    if type == .ended, let optsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt {
      let opts = AVAudioSession.InterruptionOptions(rawValue: optsRaw)
      shouldResume = opts.contains(.shouldResume)
    }
    DispatchQueue.main.async { [weak self] in
      guard let self = self, self.isActive else { return }
      switch type {
      case .began:
        self.channel.invokeMethod("audioInterruptionBegan", arguments: nil)
      case .ended:
        self.channel.invokeMethod("audioInterruptionEnded", arguments: ["shouldResume": shouldResume])
      @unknown default:
        break
      }
    }
  }

  @objc private func handleRouteChange(_ notification: Notification) {
    guard let info = notification.userInfo,
          let reasonRaw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
          let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw),
          reason == .oldDeviceUnavailable else {
      return
    }
    DispatchQueue.main.async { [weak self] in
      guard let self = self, self.isActive else { return }
      self.channel.invokeMethod("audioBecomingNoisy", arguments: nil)
    }
  }

  // MARK: - MPRemoteCommandCenter

  private func onMainSync<T>(_ block: () -> T) -> T {
    if Thread.isMainThread {
      return block()
    }
    return DispatchQueue.main.sync(execute: block)
  }

  private func registerRemoteCommandsIfNeeded() {
    guard !commandsRegistered else { return }
    commandsRegistered = true

    let cc = MPRemoteCommandCenter.shared()

    let playToken = cc.playCommand.addTarget { [weak self] (_: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus in
      guard let self = self else { return .noActionableNowPlayingItem }
      return self.onMainSync {
        guard self.isActive else { return .noActionableNowPlayingItem }
        self.channel.invokeMethod("play", arguments: nil)
        return .success
      }
    }
    commandTargets.append((cc.playCommand, playToken))

    let pauseToken = cc.pauseCommand.addTarget { [weak self] (_: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus in
      guard let self = self else { return .noActionableNowPlayingItem }
      return self.onMainSync {
        guard self.isActive else { return .noActionableNowPlayingItem }
        self.channel.invokeMethod("pause", arguments: nil)
        return .success
      }
    }
    commandTargets.append((cc.pauseCommand, pauseToken))

    let toggleToken = cc.togglePlayPauseCommand.addTarget { [weak self] (_: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus in
      guard let self = self else { return .noActionableNowPlayingItem }
      return self.onMainSync {
        guard self.isActive else { return .noActionableNowPlayingItem }
        self.channel.invokeMethod("playPause", arguments: nil)
        return .success
      }
    }
    commandTargets.append((cc.togglePlayPauseCommand, toggleToken))

    let stopToken = cc.stopCommand.addTarget { [weak self] (_: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus in
      guard let self = self else { return .noActionableNowPlayingItem }
      return self.onMainSync {
        guard self.isActive else { return .noActionableNowPlayingItem }
        self.channel.invokeMethod("stop", arguments: nil)
        return .success
      }
    }
    commandTargets.append((cc.stopCommand, stopToken))

    let nextToken = cc.nextTrackCommand.addTarget { [weak self] (_: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus in
      guard let self = self else { return .noActionableNowPlayingItem }
      return self.onMainSync {
        guard self.isActive, self.canGoNext else { return .commandFailed }
        self.channel.invokeMethod("next", arguments: nil)
        return .success
      }
    }
    commandTargets.append((cc.nextTrackCommand, nextToken))

    let prevToken = cc.previousTrackCommand.addTarget { [weak self] (_: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus in
      guard let self = self else { return .noActionableNowPlayingItem }
      return self.onMainSync {
        guard self.isActive, self.canGoPrevious else { return .commandFailed }
        self.channel.invokeMethod("previous", arguments: nil)
        return .success
      }
    }
    commandTargets.append((cc.previousTrackCommand, prevToken))

    let skipFwdToken = cc.skipForwardCommand.addTarget { [weak self] (event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus in
      guard let self = self else { return .noActionableNowPlayingItem }
      let eventInterval = (event as? MPSkipIntervalCommandEvent)?.interval
      return self.onMainSync {
        guard self.isActive, !self.isLive, self.canSeek else { return .commandFailed }
        let secs = eventInterval ?? Double(self.skipSeconds)
        let offsetMs = Int64((secs * 1000.0).rounded())
        self.channel.invokeMethod("seekBy", arguments: ["offsetMs": offsetMs])
        return .success
      }
    }
    commandTargets.append((cc.skipForwardCommand, skipFwdToken))

    let skipBackToken = cc.skipBackwardCommand.addTarget { [weak self] (event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus in
      guard let self = self else { return .noActionableNowPlayingItem }
      let eventInterval = (event as? MPSkipIntervalCommandEvent)?.interval
      return self.onMainSync {
        guard self.isActive, !self.isLive, self.canSeek else { return .commandFailed }
        let secs = eventInterval ?? Double(self.skipSeconds)
        let offsetMs = -Int64((secs * 1000.0).rounded())
        self.channel.invokeMethod("seekBy", arguments: ["offsetMs": offsetMs])
        return .success
      }
    }
    commandTargets.append((cc.skipBackwardCommand, skipBackToken))

    let scrubToken = cc.changePlaybackPositionCommand.addTarget { [weak self] (event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus in
      guard let self = self,
            let posEvent = event as? MPChangePlaybackPositionCommandEvent else {
        return .commandFailed
      }
      let targetMs = Int64(max(0.0, posEvent.positionTime) * 1000.0)
      return self.onMainSync {
        guard self.isActive, !self.isLive, self.canSeek else { return .commandFailed }
        self.positionMs = targetMs
        self.applyNowPlayingInfo()
        self.channel.invokeMethod("seek", arguments: ["positionMs": targetMs])
        return .success
      }
    }
    commandTargets.append((cc.changePlaybackPositionCommand, scrubToken))
  }

  private func syncRemoteCommandAvailability() {
    let cc = MPRemoteCommandCenter.shared()
    cc.playCommand.isEnabled = isActive
    cc.pauseCommand.isEnabled = isActive
    cc.togglePlayPauseCommand.isEnabled = isActive
    cc.stopCommand.isEnabled = isActive

    // On iOS Lock Screen, only two side slots flank Play/Pause:
    // - Live TV & multi-episode Series queues expose Previous/Next (also mapped to AirPods 2x/3x press).
    // - Standalone VOD movies expose Skip Backward / Skip Forward (±skipSeconds).
    let useTrackNav = isLive || canGoNext || canGoPrevious
    if useTrackNav {
      cc.nextTrackCommand.isEnabled = isActive && canGoNext
      cc.previousTrackCommand.isEnabled = isActive && canGoPrevious
      cc.skipForwardCommand.isEnabled = false
      cc.skipBackwardCommand.isEnabled = false
    } else {
      cc.nextTrackCommand.isEnabled = false
      cc.previousTrackCommand.isEnabled = false
      let interval = NSNumber(value: skipSeconds)
      cc.skipForwardCommand.preferredIntervals = [interval]
      cc.skipBackwardCommand.preferredIntervals = [interval]
      cc.skipForwardCommand.isEnabled = isActive && canSeek
      cc.skipBackwardCommand.isEnabled = isActive && canSeek
    }

    cc.changePlaybackPositionCommand.isEnabled = isActive && !isLive && canSeek
  }

  private func disableAllRemoteCommands() {
    let cc = MPRemoteCommandCenter.shared()
    cc.playCommand.isEnabled = false
    cc.pauseCommand.isEnabled = false
    cc.togglePlayPauseCommand.isEnabled = false
    cc.stopCommand.isEnabled = false
    cc.nextTrackCommand.isEnabled = false
    cc.previousTrackCommand.isEnabled = false
    cc.skipForwardCommand.isEnabled = false
    cc.skipBackwardCommand.isEnabled = false
    cc.changePlaybackPositionCommand.isEnabled = false
  }

  // MARK: - MPNowPlayingInfoCenter

  private func applyNowPlayingInfo() {
    guard isActive else { return }

    var info: [String: Any] = [
      MPMediaItemPropertyTitle: title,
      MPNowPlayingInfoPropertyMediaType: NSNumber(value: MPNowPlayingInfoMediaType.video.rawValue),
      MPNowPlayingInfoPropertyIsLiveStream: NSNumber(value: isLive),
      MPNowPlayingInfoPropertyDefaultPlaybackRate: NSNumber(value: 1.0),
      MPNowPlayingInfoPropertyPlaybackRate: NSNumber(value: isPlaying ? rate : 0.0),
    ]

    if !subtitle.isEmpty {
      info[MPMediaItemPropertyArtist] = subtitle
    }
    if !album.isEmpty && album != subtitle {
      info[MPMediaItemPropertyAlbumTitle] = album
    }

    if !isLive && durationMs > 0 {
      info[MPMediaItemPropertyPlaybackDuration] = NSNumber(value: Double(durationMs) / 1000.0)
      info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = NSNumber(value: Double(positionMs) / 1000.0)
    }

    if let image = currentArtworkImage ?? fallbackAppIcon(),
       image.size.width > 0,
       image.size.height > 0 {
      let artwork = MPMediaItemArtwork(boundsSize: image.size) { (_: CGSize) -> UIImage in
        return image
      }
      info[MPMediaItemPropertyArtwork] = artwork
    }

    let center = MPNowPlayingInfoCenter.default()
    center.nowPlayingInfo = info
    center.playbackState = isPlaying ? .playing : .paused
  }

  // MARK: - Artwork Loading & Caching

  private func updateArtworkIfNeeded(for artUrl: String) {
    if artUrl == currentArtUrl {
      return
    }
    currentArtUrl = artUrl
    artworkTask?.cancel()
    artworkTask = nil

    if artUrl.isEmpty {
      currentArtworkImage = nil
      return
    }

    if let cached = artworkCache[artUrl] {
      currentArtworkImage = cached
      return
    }

    currentArtworkImage = nil

    guard let url = URL(string: artUrl) else { return }

    if url.isFileURL {
      let requestedUrl = artUrl
      DispatchQueue.global(qos: .utility).async { [weak self] in
        guard let data = try? Data(contentsOf: url),
              data.count <= Self.maxArtworkBytes,
              let image = UIImage(data: data) else {
          return
        }
        DispatchQueue.main.async {
          guard let self = self, self.isActive, self.currentArtUrl == requestedUrl else { return }
          self.storeArtwork(image, for: requestedUrl)
          self.currentArtworkImage = image
          self.applyNowPlayingInfo()
        }
      }
      return
    }

    var req = URLRequest(url: url)
    req.setValue(userAgent, forHTTPHeaderField: "User-Agent")

    let requestedUrl = artUrl
    let task = artworkSession.dataTask(with: req) { [weak self] (data: Data?, response: URLResponse?, error: Error?) in
      guard error == nil,
            let data = data,
            !data.isEmpty,
            data.count <= Self.maxArtworkBytes else {
        return
      }
      if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
        return
      }
      guard let image = UIImage(data: data) else { return }
      DispatchQueue.main.async {
        guard let self = self, self.isActive, self.currentArtUrl == requestedUrl else { return }
        self.storeArtwork(image, for: requestedUrl)
        self.currentArtworkImage = image
        self.applyNowPlayingInfo()
      }
    }
    artworkTask = task
    task.resume()
  }

  private func storeArtwork(_ image: UIImage, for key: String) {
    if artworkCache[key] == nil {
      artworkOrder.append(key)
      while artworkOrder.count > Self.maxArtworkCacheEntries {
        let evicted = artworkOrder.removeFirst()
        artworkCache.removeValue(forKey: evicted)
      }
    }
    artworkCache[key] = image
  }

  private func fallbackAppIcon() -> UIImage? {
    if loadedFallbackIcon {
      return cachedFallbackIcon
    }
    loadedFallbackIcon = true
    if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
       let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
       let files = primary["CFBundleIconFiles"] as? [String],
       let last = files.last,
       let icon = UIImage(named: last) {
      cachedFallbackIcon = icon
      return icon
    }
    if let icon = UIImage(named: "AppIcon") {
      cachedFallbackIcon = icon
      return icon
    }
    return nil
  }
}

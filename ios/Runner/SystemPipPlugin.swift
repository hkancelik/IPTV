import AVFoundation
import AVKit
import CoreMedia
import CoreVideo
import Flutter
import UIKit

/// Hidden 16:9 `AVSampleBufferDisplayLayer` host view attached to the key window so iOS
/// recognizes an active inline video surface for `AVPictureInPictureController`.
private final class PipSampleBufferHostView: UIView {
  override class var layerClass: AnyClass {
    AVSampleBufferDisplayLayer.self
  }

  var displayLayer: AVSampleBufferDisplayLayer {
    // Safe cast guaranteed by `layerClass`.
    return layer as! AVSampleBufferDisplayLayer
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    backgroundColor = .clear
    // Must stay non-zero alpha and non-hidden for iOS automatic PiP-from-inline.
    alpha = 0.001
    displayLayer.videoGravity = .resizeAspect
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

/// Bridges Flutter playback with Apple's native `AVPictureInPictureController`.
///
/// Strategy:
/// - While playing in the foreground, `media_kit` (`mpv`) renders inside Flutter and
///   this plugin keeps a lightweight `AVSampleBufferDisplayLayer` armed with zero extra
///   network connections.
/// - When PiP starts (automatically upon leaving the app if `autoStart` is enabled, or
///   via the manual PiP button), Flutter immediately pauses/releases `mpv` (preserving
///   single-connection IPTV accounts and avoiding background OpenGL ES calls) while a
///   native `AVPlayer` + `AVPlayerItemVideoOutput` feeds hardware-decoded frames directly
///   into `AVSampleBufferDisplayLayer`.
/// - When PiP stops, `AVPlayer` is released immediately and Flutter resumes `mpv` at the
///   latest VOD timestamp if the user restored the app.
final class SystemPipPlugin: NSObject, FlutterPlugin, AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate {
  private let channel: FlutterMethodChannel

  private var hostView: PipSampleBufferHostView?
  private var pipController: AVPictureInPictureController?

  // Latest metadata synced from Flutter
  private var streamUrl: String?
  private var originalUrl: String?
  private var streamTitle: String = ""
  private var isLive: Bool = false
  private var isForegroundPlaying: Bool = false
  private var initialPositionMs: Int64 = 0
  private var knownDurationMs: Int64 = 0
  private var autoStartEnabled: Bool = true
  private var userAgent: String = "VLC/3.0.20 LibVLC/3.0.20"

  // Native background PiP playback state
  private var avPlayer: AVPlayer?
  private var videoOutput: AVPlayerItemVideoOutput?
  private var itemStatusObserver: NSKeyValueObservation?
  private var frameTimer: DispatchSourceTimer?
  private var pipRunning: Bool = false
  private var pipPlaying: Bool = false
  private var restoreRequested: Bool = false
  private var triedOriginalFallback: Bool = false

  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "SystemPipPlugin") else { return }
    register(with: registrar)
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "iptv/system_pip", binaryMessenger: registrar.messenger())
    let instance = SystemPipPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  private init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
  }

  deinit {
    teardownAvPlayer()
  }

  // MARK: - Flutter MethodChannel

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "configure":
        let args = call.arguments as? [String: Any] ?? [:]
        self.handleConfigure(args)
        result(nil)
      case "setAutoStart":
        let args = call.arguments as? [String: Any] ?? [:]
        self.autoStartEnabled = (args["enabled"] as? Bool) ?? true
        self.syncPipFlags()
        result(nil)
      case "start":
        result(self.startManualPip())
      case "stop":
        self.stopPip()
        result(nil)
      case "clear":
        self.clearPip()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func handleConfigure(_ args: [String: Any]) {
    guard AVPictureInPictureController.isPictureInPictureSupported() else { return }

    streamUrl = args["url"] as? String
    originalUrl = (args["originalUrl"] as? String) ?? streamUrl
    streamTitle = (args["title"] as? String) ?? ""
    isLive = (args["live"] as? Bool) ?? false
    isForegroundPlaying = (args["playing"] as? Bool) ?? false
    initialPositionMs = (args["positionMs"] as? NSNumber)?.int64Value ?? 0
    knownDurationMs = (args["durationMs"] as? NSNumber)?.int64Value ?? 0
    autoStartEnabled = (args["autoStart"] as? Bool) ?? autoStartEnabled
    if let ua = args["userAgent"] as? String, !ua.isEmpty {
      userAgent = ua
    }

    ensurePipController()
    if !pipRunning {
      enqueuePlaceholderFrame()
    }
    syncPipFlags()
  }

  private func syncPipFlags() {
    guard let pip = pipController else { return }
    pip.requiresLinearPlayback = isLive
    let shouldAuto = autoStartEnabled && isForegroundPlaying && (streamUrl != nil)
    pip.canStartPictureInPictureAutomaticallyFromInline = shouldAuto
    pip.invalidatePlaybackState()
  }

  private func startManualPip() -> Bool {
    guard AVPictureInPictureController.isPictureInPictureSupported(), streamUrl != nil else {
      return false
    }
    activateAudioSession()
    ensurePipController()
    if !pipRunning {
      enqueuePlaceholderFrame()
    }
    syncPipFlags()
    guard let pip = pipController else { return false }
    if pip.isPictureInPictureActive {
      return true
    }
    pip.startPictureInPicture()
    return true
  }

  private func stopPip() {
    if let pip = pipController, pip.isPictureInPictureActive {
      pip.stopPictureInPicture()
    } else {
      teardownAvPlayer()
    }
  }

  private func clearPip() {
    streamUrl = nil
    originalUrl = nil
    isForegroundPlaying = false
    if let pip = pipController {
      pip.canStartPictureInPictureAutomaticallyFromInline = false
      if pip.isPictureInPictureActive {
        pip.stopPictureInPicture()
      }
    }
    teardownAvPlayer()
  }

  // MARK: - Window & Controller Setup

  private func activeKeyWindow() -> UIWindow? {
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      if let key = windowScene.windows.first(where: { $0.isKeyWindow }) {
        return key
      }
      if let first = windowScene.windows.first {
        return first
      }
    }
    return nil
  }

  private func ensurePipController() {
    guard let window = activeKeyWindow() else { return }
    if hostView == nil {
      let view = PipSampleBufferHostView(frame: CGRect(x: 0, y: 0, width: 16, height: 9))
      window.addSubview(view)
      hostView = view
    } else if let view = hostView, view.superview !== window {
      view.removeFromSuperview()
      window.addSubview(view)
    }

    if pipController == nil, let view = hostView {
      let contentSource = AVPictureInPictureController.ContentSource(
        sampleBufferDisplayLayer: view.displayLayer,
        playbackDelegate: self
      )
      let controller = AVPictureInPictureController(contentSource: contentSource)
      controller.delegate = self
      pipController = controller
    }
  }

  private func activateAudioSession() {
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .moviePlayback)
      try session.setActive(true)
    } catch {
      // Non-fatal
    }
  }

  // MARK: - Native AVPlayer Handoff (Single Connection)

  private func startAvPlayer(urlString: String) {
    teardownAvPlayer()
    guard let url = URL(string: urlString) else {
      notifyFailure("Geçersiz yayın adresi")
      return
    }

    activateAudioSession()
    let headers = ["User-Agent": userAgent]
    let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
    let item = AVPlayerItem(asset: asset)
    let outputAttrs: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
    ]
    let output = AVPlayerItemVideoOutput(pixelBufferAttributes: outputAttrs)
    item.add(output)

    let player = AVPlayer(playerItem: item)
    player.automaticallyWaitsToMinimizeStalling = true
    player.allowsExternalPlayback = false

    self.avPlayer = player
    self.videoOutput = output
    self.pipPlaying = true

    itemStatusObserver = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
      DispatchQueue.main.async {
        guard let self = self, self.avPlayer?.currentItem === observedItem else { return }
        switch observedItem.status {
        case .readyToPlay:
          if !self.isLive, self.initialPositionMs > 1000 {
            let target = CMTime(value: self.initialPositionMs, timescale: 1000)
            self.avPlayer?.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] (_: Bool) in
              DispatchQueue.main.async {
                self?.avPlayer?.play()
                self?.pipController?.invalidatePlaybackState()
              }
            }
          } else {
            self.avPlayer?.play()
          }
          self.startFramePump()
          self.pipController?.invalidatePlaybackState()
        case .failed:
          if self.isLive, !self.triedOriginalFallback, let orig = self.originalUrl, orig != urlString {
            self.triedOriginalFallback = true
            self.startAvPlayer(urlString: orig)
            return
          }
          let reason = observedItem.error?.localizedDescription ?? "Bu yayın biçimi iOS PiP ile desteklenmiyor"
          self.notifyFailure(reason)
        default:
          break
        }
      }
    }

    player.play()
  }

  private func startFramePump() {
    frameTimer?.cancel()
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now(), repeating: .milliseconds(33), leeway: .milliseconds(4))
    timer.setEventHandler { [weak self] in
      self?.pumpNextFrame()
    }
    frameTimer = timer
    timer.resume()
  }

  private func pumpNextFrame() {
    guard pipRunning, let output = videoOutput, avPlayer != nil else { return }
    let itemTime = output.itemTime(forHostTime: CACurrentMediaTime())
    guard itemTime.isValid, output.hasNewPixelBuffer(forItemTime: itemTime) else { return }
    var displayTime = CMTime.invalid
    guard let pixelBuffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: &displayTime) else {
      return
    }
    enqueuePixelBuffer(pixelBuffer)
  }

  private func teardownAvPlayer() {
    frameTimer?.cancel()
    frameTimer = nil
    itemStatusObserver?.invalidate()
    itemStatusObserver = nil
    if let output = videoOutput, let item = avPlayer?.currentItem {
      item.remove(output)
    }
    avPlayer?.pause()
    avPlayer?.replaceCurrentItem(with: nil)
    avPlayer = nil
    videoOutput = nil
  }

  private func notifyFailure(_ reason: String) {
    channel.invokeMethod("failed", arguments: ["reason": reason])
    stopPip()
  }

  // MARK: - CMSampleBuffer Rendering

  private func enqueuePlaceholderFrame() {
    var pixelBuffer: CVPixelBuffer?
    let attrs: [String: Any] = [
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
      kCVPixelBufferIOSurfacePropertiesKey as String: [:],
    ]
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      320,
      180,
      kCVPixelFormatType_32BGRA,
      attrs as CFDictionary,
      &pixelBuffer
    )
    guard status == kCVReturnSuccess, let pb = pixelBuffer else { return }

    CVPixelBufferLockBaseAddress(pb, [])
    if let base = CVPixelBufferGetBaseAddress(pb) {
      let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
      let height = CVPixelBufferGetHeight(pb)
      let ptr = base.assumingMemoryBound(to: UInt8.self)
      // Fill with Kömür OLED ground (#0B0B0D in BGRA: B=0x0D, G=0x0B, R=0x0B, A=0xFF).
      for y in 0..<height {
        let row = ptr.advanced(by: y * bytesPerRow)
        for x in 0..<320 {
          let i = x * 4
          row[i] = 0x0D
          row[i + 1] = 0x0B
          row[i + 2] = 0x0B
          row[i + 3] = 0xFF
        }
      }
    }
    CVPixelBufferUnlockBaseAddress(pb, [])
    enqueuePixelBuffer(pb)
  }

  private func enqueuePixelBuffer(_ pixelBuffer: CVPixelBuffer) {
    guard let displayLayer = hostView?.displayLayer else { return }

    var formatDesc: CMVideoFormatDescription?
    let fmtStatus = CMVideoFormatDescriptionCreateForImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      formatDescriptionOut: &formatDesc
    )
    guard fmtStatus == noErr, let format = formatDesc else { return }

    var timing = CMSampleTimingInfo(
      duration: .invalid,
      presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
      decodeTimeStamp: .invalid
    )
    var sampleBuffer: CMSampleBuffer?
    let sbStatus = CMSampleBufferCreateReadyWithImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      formatDescription: format,
      sampleTiming: &timing,
      sampleBufferOut: &sampleBuffer
    )
    guard sbStatus == noErr, let buffer = sampleBuffer else { return }

    if let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: true),
       CFArrayGetCount(attachments) > 0,
       let rawDict = CFArrayGetValueAtIndex(attachments, 0),
       let cfTrue = kCFBooleanTrue {
      let dict = unsafeBitCast(rawDict, to: CFMutableDictionary.self)
      CFDictionarySetValue(
        dict,
        Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
        Unmanaged.passUnretained(cfTrue).toOpaque()
      )
    }

    if #available(iOS 17.0, *) {
      let renderer = displayLayer.sampleBufferRenderer
      if renderer.status == .failed {
        renderer.flush()
      }
      renderer.enqueue(buffer)
    } else {
      if displayLayer.status == .failed {
        displayLayer.flush()
      }
      displayLayer.enqueue(buffer)
    }
  }

  // MARK: - AVPictureInPictureControllerDelegate

  func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    pipRunning = true
    pipPlaying = true
    restoreRequested = false
    triedOriginalFallback = false
    channel.invokeMethod("willStart", arguments: nil)
    if let url = streamUrl {
      startAvPlayer(urlString: url)
    }
  }

  func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    channel.invokeMethod("didStart", arguments: nil)
    pictureInPictureController.invalidatePlaybackState()
  }

  func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
    pipRunning = false
    pipPlaying = false
    teardownAvPlayer()
    channel.invokeMethod("failed", arguments: ["reason": error.localizedDescription])
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
  ) {
    restoreRequested = true
    completionHandler(true)
  }

  func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    let wasPlaying = pipPlaying
    let restore = restoreRequested
    var posMs: Int64 = initialPositionMs
    if !isLive, let current = avPlayer?.currentTime(), current.isNumeric {
      let seconds = CMTimeGetSeconds(current)
      if seconds.isFinite && seconds >= 0 {
        posMs = Int64(seconds * 1000.0)
      }
    }

    pipRunning = false
    pipPlaying = false
    restoreRequested = false
    teardownAvPlayer()
    enqueuePlaceholderFrame()

    channel.invokeMethod("didStop", arguments: [
      "restoreUi": restore,
      "positionMs": posMs,
      "wasPlaying": wasPlaying,
    ])
  }

  // MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

  func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
    pipPlaying = playing
    if playing {
      avPlayer?.play()
    } else {
      avPlayer?.pause()
    }
    pictureInPictureController.invalidatePlaybackState()
  }

  func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
    if isLive {
      return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }
    if let itemDuration = avPlayer?.currentItem?.duration, itemDuration.isNumeric {
      let secs = CMTimeGetSeconds(itemDuration)
      if secs.isFinite && secs > 0 {
        return CMTimeRange(start: .zero, duration: itemDuration)
      }
    }
    if knownDurationMs > 0 {
      return CMTimeRange(start: .zero, duration: CMTime(value: knownDurationMs, timescale: 1000))
    }
    return CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 1))
  }

  func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
    return !pipPlaying
  }

  func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
    // AVSampleBufferDisplayLayer scales automatically via `.resizeAspect`.
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    skipByInterval skipInterval: CMTime,
    completion completionHandler: @escaping () -> Void
  ) {
    guard !isLive, let player = avPlayer else {
      completionHandler()
      return
    }
    let current = player.currentTime()
    var target = CMTimeAdd(current, skipInterval)
    if target < .zero {
      target = .zero
    }
    player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { (_: Bool) in
      DispatchQueue.main.async {
        pictureInPictureController.invalidatePlaybackState()
        completionHandler()
      }
    }
  }
}

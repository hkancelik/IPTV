import AVFoundation
import Flutter
import MediaPlayer
import UIKit

/// Native iOS hardware brightness and system volume controls for touch player gestures.
///
/// Channel: `iptv/device_controls`
/// - Brightness reads/writes the active `UIWindowScene`'s `UIScreen.brightness`.
/// - Volume reads `AVAudioSession.sharedInstance().outputVolume` and updates an
///   off-screen `MPVolumeView` slider only during active swipe gestures, then
///   detaches it shortly afterward so physical volume buttons keep the standard
///   iOS HUD.
final class DeviceControlsPlugin: NSObject, FlutterPlugin {
  private static let channelName = "iptv/device_controls"

  private var volumeView: MPVolumeView?
  private var detachWorkItem: DispatchWorkItem?

  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "DeviceControlsPlugin") else { return }
    register(with: registrar)
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    let instance = DeviceControlsPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  deinit {
    detachWorkItem?.cancel()
    let view = volumeView
    if Thread.isMainThread {
      view?.removeFromSuperview()
    } else {
      DispatchQueue.main.async {
        view?.removeFromSuperview()
      }
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "getBrightness":
        let b = self.activeScreen()?.brightness ?? 0.5
        result(Double(max(0.0, min(1.0, b))))
      case "setBrightness":
        let args = call.arguments as? [String: Any] ?? [:]
        let raw = (args["value"] as? NSNumber)?.doubleValue ?? 0.5
        let clamped = CGFloat(max(0.0, min(1.0, raw)))
        self.activeScreen()?.brightness = clamped
        result(nil)
      case "getVolume":
        let vol = AVAudioSession.sharedInstance().outputVolume
        result(Double(max(0.0, min(1.0, vol))))
      case "setVolume":
        let args = call.arguments as? [String: Any] ?? [:]
        let raw = (args["value"] as? NSNumber)?.doubleValue ?? 0.5
        let clamped = Float(max(0.0, min(1.0, raw)))
        result(self.applySystemVolume(clamped))
      case "endVolumeGesture":
        self.scheduleVolumeViewDetach(delay: 0.65)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func activeWindowScene() -> UIWindowScene? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    if let active = scenes.first(where: { $0.activationState == .foregroundActive }) {
      return active
    }
    return scenes.first
  }

  private func activeScreen() -> UIScreen? {
    return activeWindowScene()?.screen
  }

  private func activeKeyWindow() -> UIWindow? {
    guard let scene = activeWindowScene() else { return nil }
    return scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
  }

  private func findSlider(in view: UIView) -> UISlider? {
    for sub in view.subviews {
      if let slider = sub as? UISlider {
        return slider
      }
      if let nested = findSlider(in: sub) {
        return nested
      }
    }
    return nil
  }

  private func applySystemVolume(_ value: Float) -> Bool {
    detachWorkItem?.cancel()
    detachWorkItem = nil

    guard let window = activeKeyWindow() else { return false }

    let view: MPVolumeView
    if let existing = volumeView {
      view = existing
    } else {
      let created = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 100, height: 40))
      created.alpha = 0.01
      created.clipsToBounds = true
      created.isUserInteractionEnabled = false
      volumeView = created
      view = created
    }

    if view.superview == nil {
      window.addSubview(view)
      view.layoutIfNeeded()
    }

    guard let slider = findSlider(in: view) else {
      view.removeFromSuperview()
      volumeView = nil
      return false
    }

    slider.setValue(value, animated: false)
    slider.sendActions(for: .touchUpInside)
    // Auto-detach if the gesture ends unexpectedly without endVolumeGesture.
    scheduleVolumeViewDetach(delay: 1.4)
    return true
  }

  private func scheduleVolumeViewDetach(delay: TimeInterval) {
    detachWorkItem?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self = self else { return }
      self.volumeView?.removeFromSuperview()
      self.detachWorkItem = nil
    }
    detachWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
  }
}

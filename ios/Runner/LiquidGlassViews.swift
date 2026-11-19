import Flutter
import UIKit

/// Registers native iOS 26+ Liquid Glass platform views for IPTV (pure UIKit):
/// - `iptv/liquid_glass_surface`: `UIVisualEffectView` + `UIGlassEffect` + `UICornerConfiguration`
/// - `iptv/liquid_glass_button`: Interactive `UIButton.Configuration.glass()` control
/// - `iptv/liquid_glass_menu`: Interactive `UIButton.Configuration.glass()` + `UIMenu`
final class LiquidGlassPlugin {
  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "LiquidGlassPlugin") else { return }
    let messenger = registrar.messenger()
    registrar.register(
      LiquidGlassSurfaceFactory(messenger: messenger),
      withId: "iptv/liquid_glass_surface",
      gestureRecognizersBlockingPolicy: FlutterPlatformViewGestureRecognizersBlockingPolicyDoNotBlockGesture
    )
    registrar.register(
      LiquidGlassButtonFactory(messenger: messenger),
      withId: "iptv/liquid_glass_button",
      gestureRecognizersBlockingPolicy: FlutterPlatformViewGestureRecognizersBlockingPolicyDoNotBlockGesture
    )
    registrar.register(
      LiquidGlassMenuFactory(messenger: messenger),
      withId: "iptv/liquid_glass_menu",
      gestureRecognizersBlockingPolicy: FlutterPlatformViewGestureRecognizersBlockingPolicyDoNotBlockGesture
    )
  }
}

// MARK: - Helpers

private func decodeARGBColor(_ value: Any?) -> UIColor? {
  guard let num = value as? NSNumber else { return nil }
  let argb = UInt32(bitPattern: Int32(truncatingIfNeeded: num.int64Value))
  let a = CGFloat((argb >> 24) & 0xFF) / 255.0
  let r = CGFloat((argb >> 16) & 0xFF) / 255.0
  let g = CGFloat((argb >> 8) & 0xFF) / 255.0
  let b = CGFloat(argb & 0xFF) / 255.0
  return UIColor(red: r, green: g, blue: b, alpha: a)
}

private func symbolWeight(from name: String?) -> UIImage.SymbolWeight {
  switch name {
  case "regular": return .regular
  case "medium": return .medium
  case "bold": return .bold
  default: return .semibold
  }
}

@available(iOS 26.0, *)
private func makeGlassButtonConfiguration(
  style: String,
  isRound: Bool,
  cornerRadius: CGFloat?,
  sfSymbol: String?,
  iconSize: CGFloat,
  iconWeight: UIImage.SymbolWeight,
  label: String?,
  fontSize: CGFloat,
  foregroundColor: UIColor?,
  tintColor: UIColor?
) -> UIButton.Configuration {
  var config: UIButton.Configuration
  switch style {
  case "prominentGlass":
    config = .prominentGlass()
  case "clearGlass":
    config = .clearGlass()
  case "prominentClearGlass":
    config = .prominentClearGlass()
  default:
    config = .glass()
  }

  if isRound {
    config.cornerStyle = .capsule
  } else if let cornerRadius, cornerRadius > 0 {
    config.cornerStyle = .fixed
    config.background.cornerRadius = cornerRadius
  } else {
    config.cornerStyle = .capsule
  }

  let hasTitle = (label != nil && !label!.isEmpty)
  let hasSymbol = (sfSymbol != nil && !sfSymbol!.isEmpty)

  if hasSymbol, let sfSymbol {
    let symConfig = UIImage.SymbolConfiguration(pointSize: iconSize, weight: iconWeight)
    config.image = UIImage(systemName: sfSymbol, withConfiguration: symConfig)
    config.preferredSymbolConfigurationForImage = symConfig
  }

  if hasTitle, let label {
    let attrs = AttributeContainer([
      NSAttributedString.Key.font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
    ])
    config.attributedTitle = AttributedString(label, attributes: attrs)
  }

  if hasSymbol && hasTitle {
    config.imagePadding = 6
    config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
  } else if isRound {
    config.contentInsets = .zero
  } else {
    config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
  }

  switch style {
  case "prominentGlass", "prominentClearGlass":
    if let tintColor { config.baseBackgroundColor = tintColor }
    if let foregroundColor { config.baseForegroundColor = foregroundColor }
  default:
    if let foregroundColor {
      config.baseForegroundColor = foregroundColor
    } else if let tintColor {
      config.baseForegroundColor = tintColor
    }
  }

  return config
}

private final class LiquidGlassEmptyPlatformView: NSObject, FlutterPlatformView {
  private let empty = UIView()
  override init() {
    super.init()
    empty.backgroundColor = .clear
    empty.isUserInteractionEnabled = false
  }
  func view() -> UIView { empty }
}

// MARK: - 1. Native Liquid Glass Surface (UIKit UIGlassEffect)

final class LiquidGlassSurfaceFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    if #available(iOS 26.0, *) {
      return LiquidGlassSurfacePlatformView(
        frame: frame,
        viewId: viewId,
        args: args as? [String: Any],
        messenger: messenger
      )
    }
    return LiquidGlassEmptyPlatformView()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

@available(iOS 26.0, *)
private final class LiquidGlassSurfacePlatformView: NSObject, FlutterPlatformView {
  private let container: UIView
  private let effectView: UIVisualEffectView
  private let channel: FlutterMethodChannel

  init(frame: CGRect, viewId: Int64, args: [String: Any]?, messenger: FlutterBinaryMessenger) {
    container = UIView(frame: frame)
    container.backgroundColor = .clear
    container.isOpaque = false
    container.clipsToBounds = false
    container.isUserInteractionEnabled = false

    effectView = UIVisualEffectView(effect: nil)
    effectView.translatesAutoresizingMaskIntoConstraints = false
    effectView.isUserInteractionEnabled = false

    channel = FlutterMethodChannel(name: "iptv/liquid_glass_surface_\(viewId)", binaryMessenger: messenger)

    super.init()

    container.addSubview(effectView)
    NSLayoutConstraint.activate([
      effectView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      effectView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      effectView.topAnchor.constraint(equalTo: container.topAnchor),
      effectView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])

    apply(args)

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      if call.method == "update" {
        self.apply(call.arguments as? [String: Any])
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView { container }

  private func apply(_ dict: [String: Any]?) {
    let effectName = (dict?["effect"] as? String) ?? "regular"
    let shape = (dict?["shape"] as? String) ?? "rect"
    let cornerRadius = (dict?["cornerRadius"] as? NSNumber)?.doubleValue ?? 20.0
    let tint = decodeARGBColor(dict?["tint"])
    let interactive = (dict?["interactive"] as? NSNumber)?.boolValue ?? false
    let isDark = (dict?["isDark"] as? NSNumber)?.boolValue ?? true

    let uiStyle: UIUserInterfaceStyle = isDark ? .dark : .light
    container.overrideUserInterfaceStyle = uiStyle
    effectView.overrideUserInterfaceStyle = uiStyle

    let glass = UIGlassEffect(style: effectName == "clear" ? .clear : .regular)
    glass.tintColor = tint
    glass.isInteractive = interactive
    effectView.effect = glass

    switch shape {
    case "circle", "capsule":
      effectView.cornerConfiguration = .capsule()
    default:
      effectView.cornerConfiguration = .uniformCorners(radius: .fixed(cornerRadius))
    }
  }
}

// MARK: - 2. Native Interactive Liquid Glass Button

final class LiquidGlassButtonFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    if #available(iOS 26.0, *) {
      return LiquidGlassButtonPlatformView(
        frame: frame,
        viewId: viewId,
        args: args as? [String: Any],
        messenger: messenger
      )
    }
    return LiquidGlassEmptyPlatformView()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

@available(iOS 26.0, *)
private final class LiquidGlassButtonPlatformView: NSObject, FlutterPlatformView {
  private let container: UIView
  private let button: UIButton
  private let channel: FlutterMethodChannel

  init(frame: CGRect, viewId: Int64, args: [String: Any]?, messenger: FlutterBinaryMessenger) {
    container = UIView(frame: frame)
    container.backgroundColor = .clear
    container.isOpaque = false
    container.clipsToBounds = false
    container.layer.masksToBounds = false

    button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.clipsToBounds = false
    button.layer.masksToBounds = false

    channel = FlutterMethodChannel(name: "iptv/liquid_glass_button_\(viewId)", binaryMessenger: messenger)

    super.init()

    container.addSubview(button)
    NSLayoutConstraint.activate([
      button.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      button.topAnchor.constraint(equalTo: container.topAnchor),
      button.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])

    button.addTarget(self, action: #selector(handlePressed), for: .touchUpInside)
    apply(args)

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      if call.method == "update" {
        self.apply(call.arguments as? [String: Any])
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView { container }

  @objc private func handlePressed() {
    channel.invokeMethod("pressed", arguments: nil)
  }

  private func apply(_ dict: [String: Any]?) {
    guard let dict else { return }
    let style = (dict["style"] as? String) ?? "glass"
    let isRound = (dict["isRound"] as? NSNumber)?.boolValue ?? true
    let cornerRadius = (dict["cornerRadius"] as? NSNumber).map { CGFloat($0.doubleValue) }
    let sfSymbol = dict["sfSymbol"] as? String
    let iconSize = (dict["iconSize"] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 18
    let weight = symbolWeight(from: dict["iconWeight"] as? String)
    let label = dict["label"] as? String
    let fontSize = (dict["fontSize"] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 13.5
    let foregroundColor = decodeARGBColor(dict["foregroundColor"])
    let tintColor = decodeARGBColor(dict["tintColor"])
    let enabled = (dict["enabled"] as? NSNumber)?.boolValue ?? true
    let isDark = (dict["isDark"] as? NSNumber)?.boolValue ?? true
    let tooltip = dict["tooltip"] as? String

    let uiStyle: UIUserInterfaceStyle = isDark ? .dark : .light
    container.overrideUserInterfaceStyle = uiStyle
    button.overrideUserInterfaceStyle = uiStyle

    button.configuration = makeGlassButtonConfiguration(
      style: style,
      isRound: isRound,
      cornerRadius: cornerRadius,
      sfSymbol: sfSymbol,
      iconSize: iconSize,
      iconWeight: weight,
      label: label,
      fontSize: fontSize,
      foregroundColor: foregroundColor,
      tintColor: tintColor
    )
    button.isEnabled = enabled
    button.alpha = enabled ? 1.0 : 0.4
    if let tooltip, !tooltip.isEmpty {
      button.accessibilityLabel = tooltip
    }
  }
}

// MARK: - 3. Native Interactive Liquid Glass Menu Button (Press-Hold-Drag + Morphing UIMenu)

final class LiquidGlassMenuFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    if #available(iOS 26.0, *) {
      return LiquidGlassMenuPlatformView(
        frame: frame,
        viewId: viewId,
        args: args as? [String: Any],
        messenger: messenger
      )
    }
    return LiquidGlassEmptyPlatformView()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

private final class LiquidGlassMenuUIButton: UIButton {
  var onMenuWillShow: (() -> Void)?
  var onMenuDidHide: (() -> Void)?

  override func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction,
    willDisplayMenuFor configuration: UIContextMenuConfiguration,
    animator: UIContextMenuInteractionAnimating?
  ) {
    super.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: animator)
    onMenuWillShow?()
  }

  override func contextMenuInteraction(
    _ interaction: UIContextMenuInteraction,
    willEndFor configuration: UIContextMenuConfiguration,
    animator: UIContextMenuInteractionAnimating?
  ) {
    super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
    let finish = { [weak self] in self?.onMenuDidHide?() }
    if let animator {
      animator.addCompletion(finish)
    } else {
      finish()
    }
  }
}

@available(iOS 26.0, *)
private final class LiquidGlassMenuPlatformView: NSObject, FlutterPlatformView {
  private let container: UIView
  private let button: LiquidGlassMenuUIButton
  private let channel: FlutterMethodChannel
  private var isMenuOpen = false
  private var pendingArgs: [String: Any]?

  init(frame: CGRect, viewId: Int64, args: [String: Any]?, messenger: FlutterBinaryMessenger) {
    container = UIView(frame: frame)
    container.backgroundColor = .clear
    container.isOpaque = false
    container.clipsToBounds = false
    container.layer.masksToBounds = false

    button = LiquidGlassMenuUIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.showsMenuAsPrimaryAction = true
    button.clipsToBounds = false
    button.layer.masksToBounds = false

    channel = FlutterMethodChannel(name: "iptv/liquid_glass_menu_\(viewId)", binaryMessenger: messenger)

    super.init()

    button.onMenuWillShow = { [weak self] in
      guard let self else { return }
      self.isMenuOpen = true
      self.channel.invokeMethod("menuWillShow", arguments: nil)
    }
    button.onMenuDidHide = { [weak self] in
      guard let self else { return }
      self.isMenuOpen = false
      if let queued = self.pendingArgs {
        self.pendingArgs = nil
        self.apply(queued)
      }
      self.channel.invokeMethod("menuDidHide", arguments: nil)
    }

    container.addSubview(button)
    NSLayoutConstraint.activate([
      button.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      button.topAnchor.constraint(equalTo: container.topAnchor),
      button.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])

    apply(args)

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      if call.method == "update" {
        let next = call.arguments as? [String: Any]
        if self.isMenuOpen {
          self.pendingArgs = next
        } else {
          self.apply(next)
        }
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView { container }

  private func apply(_ dict: [String: Any]?) {
    guard let dict else { return }
    let style = (dict["style"] as? String) ?? "clearGlass"
    let isRound = (dict["isRound"] as? NSNumber)?.boolValue ?? true
    let cornerRadius = (dict["cornerRadius"] as? NSNumber).map { CGFloat($0.doubleValue) }
    let sfSymbol = (dict["sfSymbol"] as? String) ?? "ellipsis"
    let iconSize = (dict["iconSize"] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 18
    let weight = symbolWeight(from: dict["iconWeight"] as? String)
    let label = dict["label"] as? String
    let fontSize = (dict["fontSize"] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 13.5
    let foregroundColor = decodeARGBColor(dict["foregroundColor"])
    let tintColor = decodeARGBColor(dict["tintColor"])
    let enabled = (dict["enabled"] as? NSNumber)?.boolValue ?? true
    let isDark = (dict["isDark"] as? NSNumber)?.boolValue ?? true
    let tooltip = dict["tooltip"] as? String
    let menuTitle = (dict["menuTitle"] as? String) ?? ""
    let rawItems = (dict["items"] as? [[String: Any]]) ?? []

    let uiStyle: UIUserInterfaceStyle = isDark ? .dark : .light
    container.overrideUserInterfaceStyle = uiStyle
    button.overrideUserInterfaceStyle = uiStyle

    button.configuration = makeGlassButtonConfiguration(
      style: style,
      isRound: isRound,
      cornerRadius: cornerRadius,
      sfSymbol: sfSymbol,
      iconSize: iconSize,
      iconWeight: weight,
      label: label,
      fontSize: fontSize,
      foregroundColor: foregroundColor,
      tintColor: tintColor
    )
    button.isEnabled = enabled
    button.alpha = enabled ? 1.0 : 0.4
    if let tooltip, !tooltip.isEmpty {
      button.accessibilityLabel = tooltip
    }

    let elements = buildMenuElements(rawItems)
    button.menu = UIMenu(title: menuTitle, children: elements)
  }

  private func buildMenuElements(_ rawItems: [[String: Any]]) -> [UIMenuElement] {
    var result: [UIMenuElement] = []
    for item in rawItems {
      let id = (item["id"] as? String) ?? ""
      let title = (item["title"] as? String) ?? ""
      let subtitle = item["subtitle"] as? String
      let sfSymbol = item["sfSymbol"] as? String
      let selected = (item["selected"] as? NSNumber)?.boolValue ?? false
      let enabled = (item["enabled"] as? NSNumber)?.boolValue ?? true
      let destructive = (item["destructive"] as? NSNumber)?.boolValue ?? false
      let inline = (item["inline"] as? NSNumber)?.boolValue ?? false
      let image = sfSymbol.flatMap { UIImage(systemName: $0) }

      if let children = item["children"] as? [[String: Any]], !children.isEmpty {
        let childElements = buildMenuElements(children)
        let options: UIMenu.Options = inline ? .displayInline : []
        let submenu = UIMenu(
          title: title,
          subtitle: subtitle,
          image: image,
          options: options,
          children: childElements
        )
        result.append(submenu)
      } else {
        var attributes: UIMenuElement.Attributes = []
        if !enabled { attributes.insert(.disabled) }
        if destructive { attributes.insert(.destructive) }
        let action = UIAction(
          title: title,
          subtitle: subtitle,
          image: image,
          attributes: attributes,
          state: selected ? .on : .off
        ) { [weak self] _ in
          self?.channel.invokeMethod("selected", arguments: ["id": id])
        }
        result.append(action)
      }
    }
    return result
  }
}

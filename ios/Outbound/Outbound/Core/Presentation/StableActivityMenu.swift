import SwiftUI
import UIKit

/// UIKit owns the open native menu. Observable parent refreshes may update the
/// latest action dispatcher, but cannot replace identical menu content.
struct StableActivityMenu: UIViewRepresentable {
    let photo: UIImage?
    let hasRoute: Bool
    let accessibilityValue: String
    var usesReadableMapTint: Bool = false
    let onAction: (ActivityOverflowAction) -> Void
    @Environment(\.outboundTheme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(onAction: onAction) }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        // Native constraints size the button's contents; SwiftUI's toolbar
        // also needs a fixed proposal so it cannot stretch/collapse the item.
        CGSize(width: 44, height: 44)
    }
    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.showsMenuAsPrimaryAction = true
        button.accessibilityIdentifier = "today.overflow"
        button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        let photo = UIImageView(frame: CGRect(x: 3, y: 3, width: 34, height: 34))
        photo.tag = 1
        photo.contentMode = .scaleAspectFill
        photo.clipsToBounds = true
        photo.layer.cornerRadius = 17
        photo.layer.borderWidth = 2
        photo.isUserInteractionEnabled = false
        button.addSubview(photo)
        let badge = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        badge.tag = 2
        badge.frame = CGRect(x: 25, y: 25, width: 16, height: 16)
        badge.clipsToBounds = true
        badge.layer.cornerRadius = 8
        badge.layer.borderWidth = 1
        badge.layer.borderColor = UIColor.white.withAlphaComponent(0.8).cgColor
        badge.isUserInteractionEnabled = false
        let glyph = UIImageView(image: UIImage(systemName: "ellipsis", withConfiguration: UIImage.SymbolConfiguration(pointSize: 8, weight: .black)))
        glyph.frame = badge.bounds
        glyph.contentMode = .center
        glyph.tintColor = .label
        badge.contentView.addSubview(glyph)
        button.addSubview(badge)
        updateUIView(button, context: context)
        return button
    }
    func updateUIView(_ button: UIButton, context: Context) {
        let coordinator = context.coordinator
        coordinator.onAction = onAction
        button.accessibilityLabel = String(localized: "record.more_actions", defaultValue: "More activity options", locale: locale)
        button.accessibilityValue = accessibilityValue
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        let tint = usesReadableMapTint
            ? UIColor.label.resolvedColor(with: traits)
            : UIColor(theme.accentColor)
        if button.tintColor != tint { button.tintColor = tint }
        if let image = button.viewWithTag(1) as? UIImageView {
            image.image = photo
            image.isHidden = photo == nil
            image.layer.borderColor = UIColor(theme.actionColor).resolvedColor(with: traits).cgColor
        }
        button.viewWithTag(2)?.isHidden = photo == nil
        let titles = [
            photo == nil ? String(localized: "record.photo.take", defaultValue: "Take photo", locale: locale) : String(localized: "record.photo.view", defaultValue: "View photo", locale: locale),
            hasRoute ? String(localized: "record.route.change", defaultValue: "Change route", locale: locale) : String(localized: "record.route.find", defaultValue: "Find a route", locale: locale),
            String(localized: "record.group.title", defaultValue: "Group run", locale: locale),
            String(localized: "record.route.remove", defaultValue: "Remove route", locale: locale)
        ]
        guard !coordinator.configured || coordinator.photo !== photo || coordinator.hasRoute != hasRoute || coordinator.titles != titles else { return }
        coordinator.configured = true
        coordinator.photo = photo
        coordinator.hasRoute = hasRoute
        coordinator.titles = titles
        if photo != nil {
            button.setImage(nil, for: .normal)
        } else {
            let configuration = UIImage.SymbolConfiguration(textStyle: .title3)
                .applying(UIImage.SymbolConfiguration(weight: .semibold))
            button.setImage(UIImage(systemName: "ellipsis.circle", withConfiguration: configuration), for: .normal)
        }
        func action(_ title: String, symbol: String, value: ActivityOverflowAction, destructive: Bool = false) -> UIAction {
            UIAction(title: title, image: UIImage(systemName: symbol), attributes: destructive ? [.destructive] : []) { [weak coordinator] _ in
                coordinator?.onAction(value)
            }
        }
        let actions: [UIMenuElement] = [
            action(titles[0], symbol: photo == nil ? "camera.fill" : "photo.fill", value: .photo),
            UIMenu(options: .displayInline, children: [action(titles[2], symbol: "person.2.fill", value: .groupRun)])
        ]
        button.menu = UIMenu(children: actions)
    }
    final class Coordinator {
        var onAction: (ActivityOverflowAction) -> Void
        var configured = false
        var photo: UIImage?
        var hasRoute = false
        var titles: [String] = []
        init(onAction: @escaping (ActivityOverflowAction) -> Void) { self.onAction = onAction }
    }
}

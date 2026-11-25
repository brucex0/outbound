import SwiftUI
import UIKit

/// A value-only menu snapshot: callbacks never participate in menu identity.
struct StableLaunchMenuItem: Equatable {
    let id: String
    let title: String
    var symbol: String? = nil
    var selected: Bool? = nil
    var children: [StableLaunchMenuItem] = []
    var singleSelection = false
}

/// Keep the same UIKit button/menu alive across the observable Today refreshes.
/// The coordinator always dispatches to the latest model, even for an open menu.
struct StableLaunchMenu: UIViewRepresentable {
    let symbol: String
    let configured: Bool
    var showsBackground = true
    var glyphSize: CGFloat = 20
    var visualDiameter: CGFloat = 44
    var verticalDots = false
    let accessibilityLabel: String
    var accessibilityValue: String = ""
    let accessibilityIdentifier: String
    let items: [StableLaunchMenuItem]
    var singleSelection = false
    let onOpen: () -> Void
    let onAction: (String) -> Void
    @Environment(\.outboundTheme) private var theme

    func makeCoordinator() -> Coordinator { Coordinator(onOpen: onOpen, onAction: onAction) }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        CGSize(width: 44, height: 44)
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.showsMenuAsPrimaryAction = true
        let fill = UIView()
        fill.tag = 1
        fill.isUserInteractionEnabled = false
        button.insertSubview(fill, at: 0)
        button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        button.addTarget(context.coordinator, action: #selector(Coordinator.menuOpened), for: .menuActionTriggered)
        updateUIView(button, context: context)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        let coordinator = context.coordinator
        coordinator.onOpen = onOpen
        coordinator.onAction = onAction
        button.accessibilityLabel = accessibilityLabel
        button.accessibilityValue = accessibilityValue
        button.accessibilityIdentifier = accessibilityIdentifier
        let tint = configured ? UIColor(theme.actionForegroundColor) : UIColor.label
        let background = showsBackground ? (configured ? UIColor(theme.actionColor) : UIColor.systemFill) : UIColor.clear
        if button.tintColor != tint { button.tintColor = tint }
        if let fill = button.viewWithTag(1) {
            fill.frame = CGRect(x: (44 - visualDiameter) / 2, y: (44 - visualDiameter) / 2, width: visualDiameter, height: visualDiameter)
            fill.layer.cornerRadius = visualDiameter / 2
            if fill.backgroundColor != background { fill.backgroundColor = background }
        }
        if coordinator.symbol != symbol || coordinator.glyphSize != glyphSize || coordinator.verticalDots != verticalDots {
            coordinator.symbol = symbol
            coordinator.glyphSize = glyphSize
            coordinator.verticalDots = verticalDots
            let source = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: glyphSize, weight: .semibold))
            let image: UIImage?
            if verticalDots, let source {
                // Rotate the template artwork itself once. UIButton owns its
                // image-view layout and must never undo a view transform.
                let size = CGSize(width: source.size.height, height: source.size.width)
                image = UIGraphicsImageRenderer(size: size).image { context in
                    context.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
                    context.cgContext.rotate(by: .pi / 2)
                    source.draw(at: CGPoint(x: -source.size.width / 2, y: -source.size.height / 2))
                }.withRenderingMode(.alwaysTemplate)
            } else { image = source }
            button.setImage(image, for: .normal)
        }
        button.imageView?.transform = .identity
        if let fill = button.viewWithTag(1) { button.sendSubviewToBack(fill) }
        guard coordinator.items != items || coordinator.singleSelection != singleSelection else { return }
        coordinator.items = items
        coordinator.singleSelection = singleSelection
        button.menu = UIMenu(options: singleSelection ? .singleSelection : [], children: items.map(coordinator.element))
    }

    final class Coordinator: NSObject {
        var onOpen: () -> Void
        var onAction: (String) -> Void
        var symbol: String?
        var glyphSize: CGFloat?
        var verticalDots = false
        var items: [StableLaunchMenuItem] = []
        var singleSelection = false

        init(onOpen: @escaping () -> Void, onAction: @escaping (String) -> Void) {
            self.onOpen = onOpen
            self.onAction = onAction
        }

        @objc func menuOpened() { onOpen() }

        func element(_ item: StableLaunchMenuItem) -> UIMenuElement {
            let image = item.symbol.flatMap { UIImage(systemName: $0) }
            if !item.children.isEmpty {
                return UIMenu(title: item.title, image: image, identifier: UIMenu.Identifier(item.id),
                              options: item.singleSelection ? .singleSelection : [], children: item.children.map(element))
            }
            return UIAction(title: item.title, image: image, identifier: UIAction.Identifier(item.id),
                            state: item.selected == true ? .on : .off) { [weak self] _ in
                // Leave the UIKit menu action turn before presenting a SwiftUI
                // sheet. Resolve through the latest dispatcher, never old state.
                DispatchQueue.main.async { [weak self] in self?.onAction(item.id) }
            }
        }
    }
}

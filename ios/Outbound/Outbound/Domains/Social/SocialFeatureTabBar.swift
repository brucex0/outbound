import SwiftUI

enum SocialFeatureTab: String, CaseIterable, Identifiable {
    case feed
    case people
    case groups
    case routes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .feed: String(localized: "social.tab.feed", defaultValue: "Feed")
        case .people: String(localized: "social.tab.people", defaultValue: "People")
        case .groups: String(localized: "social.tab.groups", defaultValue: "Groups")
        case .routes: String(localized: "social.tab.routes", defaultValue: "Routes")
        }
    }

    var systemImage: String {
        switch self {
        case .feed: "rectangle.stack"
        case .people: "person.2"
        case .groups: "flag"
        case .routes: "map"
        }
    }
}

enum SocialTabBadge: Equatable {
    case dot
    case count(Int)

    var analyticsKind: String {
        switch self {
        case .dot: "dot"
        case .count: "count"
        }
    }
}

struct SocialFeatureTabBar: View {
    let selection: SocialFeatureTab
    let badges: [SocialFeatureTab: SocialTabBadge]
    let onSelect: (SocialFeatureTab) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SocialFeatureTab.allCases) { tab in
                Button {
                    onSelect(tab)
                } label: {
                    VStack(spacing: 3) {
                        ZStack(alignment: .topTrailing) {
                            tabIcon(tab)
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 24, height: 19)
                            if let badge = badges[tab] {
                                SocialFeatureTabBadgeView(badge: badge)
                                    .offset(x: 9, y: -5)
                            }
                        }
                        Text(tab.title)
                            .font(.caption2.weight(selection == tab ? .bold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .foregroundStyle(selection == tab ? OutboundPalette.companion : .secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityValue(accessibilityValue(for: tab))
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private func tabIcon(_ tab: SocialFeatureTab) -> some View {
        Image(systemName: tab.systemImage)
    }

    private func accessibilityValue(for tab: SocialFeatureTab) -> String {
        guard let badge = badges[tab] else {
            return selection == tab
                ? String(localized: "social.tab.accessibility.selected", defaultValue: "Selected")
                : ""
        }
        switch badge {
        case .dot:
            return String(localized: "social.tab.accessibility.new_content", defaultValue: "New content")
        case .count(let count):
            return String(localized: "social.tab.accessibility.action_count", defaultValue: "\(count) actions need attention")
        }
    }
}

private struct SocialFeatureTabBadgeView: View {
    let badge: SocialTabBadge

    var body: some View {
        switch badge {
        case .dot:
            Circle()
                .fill(OutboundPalette.companion)
                .frame(width: 7, height: 7)
                .overlay { Circle().stroke(.background, lineWidth: 1.5) }
                .accessibilityHidden(true)
        case .count(let count):
            Text(count > 9 ? "9+" : "\(count)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .frame(minWidth: 15, minHeight: 15)
                .background(OutboundPalette.companion, in: Capsule())
                .overlay { Capsule().stroke(.background, lineWidth: 1.5) }
                .accessibilityHidden(true)
        }
    }
}

import SwiftUI
import WidgetKit

struct HomeWidgetOnboardingView: View {
    static var exampleSnapshot: HomeWorkoutWidgetSnapshot {
        HomeWorkoutWidgetSnapshot(
            title: String(localized: "widget.fallback.title", table: "HomeWidget"),
            detail: String(localized: "widget.fallback.detail", table: "HomeWidget"),
            systemImageName: "figure.run"
        )
    }

    @Environment(\.analyticsManager) private var analyticsManager
    @State private var page = 0

    let snapshot: HomeWorkoutWidgetSnapshot
    let entrySource: String
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                if page == 0 {
                    introduction
                } else {
                    setupStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .task {
            await analyticsManager?.track(.init(.homeWidgetOnboardingViewed, properties: [
                .entrySource: .string(entrySource)
            ]))
        }
        .task(id: page) {
            guard page > 0 else { return }
            let stepName = switch page {
            case 1: "hold_home_screen"
            case 2: "open_widget_picker"
            default: "choose_plainstride_widget"
            }
            await analyticsManager?.track(.init(.homeWidgetSetupStepViewed, properties: [
                .entrySource: .string(entrySource),
                .stepName: .string(stepName)
            ]))
        }
    }

    private var header: some View {
        HStack {
            if page > 0 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { page -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.semibold))
                        .frame(width: 44, height: 44, alignment: .leading)
                }
                .accessibilityLabel(String(localized: "Back"))
            } else {
                Spacer().frame(width: 44, height: 44)
            }

            Spacer()

            if page > 0 {
                Text(stepCount)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Spacer().frame(width: 44, height: 44)
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 9) {
                Text(String(localized: "widget.intro.title", table: "HomeWidget"))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(localized: "widget.intro.description", table: "HomeWidget"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 6)

            HomeWorkoutWidgetCard(snapshot: snapshot, family: .systemMedium)
                .frame(height: 158)
                .accessibilityLabel(String(localized: "widget.gallery.description", table: "HomeWidget"))
        }
        .padding(.top, 20)
    }

    private var setupStep: some View {
        VStack(spacing: 20) {
            VStack(spacing: 9) {
                Text(stepTitle)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(stepDetail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            phoneIllustration
        }
        .padding(.horizontal, 4)
        .padding(.top, 22)
    }

    private var phoneIllustration: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(Color.primary.opacity(0.28), lineWidth: 4)
                .frame(width: 178, height: 276)
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(Color.primary.opacity(0.28))
                        .frame(width: 56, height: 5)
                        .padding(.top, 11)
                }

            VStack(spacing: 15) {
                Image(systemName: illustrationSymbol)
                    .font(.system(size: 54, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.teal)
                    .frame(height: 80)

                if page == 3 {
                    HomeWorkoutWidgetCard(snapshot: snapshot, family: .systemSmall)
                        .frame(width: 124, height: 124)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.teal.opacity(0.12))
                        .frame(width: 124, height: 124)
                        .overlay {
                            Image(systemName: page == 1 ? "hand.tap.fill" : "plus.square.grid.2x2.fill")
                                .font(.system(size: 38, weight: .medium))
                                .foregroundStyle(Color.teal)
                        }
                }
            }
            .padding(.top, 25)
        }
        .frame(height: 292)
        .accessibilityHidden(true)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if page == 0 {
                Button {
                    trackAction("skip")
                    onFinish()
                } label: {
                    Text(String(localized: "widget.button.skip", table: "HomeWidget"))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.plain)

                Button {
                    trackAction("add")
                    withAnimation(.easeInOut(duration: 0.2)) { page = 1 }
                } label: {
                    Text(String(localized: "widget.button.add", table: "HomeWidget"))
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.10, green: 0.45, blue: 0.61))
            } else {
                Button {
                    if page == 3 {
                        Task {
                            await analyticsManager?.track(.init(.homeWidgetSetupGuideCompleted, properties: [
                                .entrySource: .string(entrySource)
                            ]))
                        }
                        onFinish()
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) { page += 1 }
                    }
                } label: {
                    Text(String(localized: page == 3 ? "widget.button.done" : "widget.button.continue", table: "HomeWidget"))
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.10, green: 0.45, blue: 0.61))
            }
        }
        .padding(.top, 16)
    }

    private var stepCount: String {
        switch page {
        case 1: String(localized: "widget.guide.step1.count", table: "HomeWidget")
        case 2: String(localized: "widget.guide.step2.count", table: "HomeWidget")
        default: String(localized: "widget.guide.step3.count", table: "HomeWidget")
        }
    }

    private var stepTitle: String {
        switch page {
        case 1: String(localized: "widget.guide.step1.title", table: "HomeWidget")
        case 2: String(localized: "widget.guide.step2.title", table: "HomeWidget")
        default: String(localized: "widget.guide.step3.title", table: "HomeWidget")
        }
    }

    private var stepDetail: String {
        switch page {
        case 1: String(localized: "widget.guide.step1.detail", table: "HomeWidget")
        case 2: String(localized: "widget.guide.step2.detail", table: "HomeWidget")
        default: String(localized: "widget.guide.step3.detail", table: "HomeWidget")
        }
    }

    private var illustrationSymbol: String {
        switch page {
        case 1: "hand.tap.fill"
        case 2: "plus.app.fill"
        default: "magnifyingglass"
        }
    }

    private func trackAction(_ selection: String) {
        Task {
            await analyticsManager?.track(.init(.homeWidgetSetupActionSelected, properties: [
                .entrySource: .string(entrySource),
                .selectionType: .string(selection)
            ]))
        }
    }
}

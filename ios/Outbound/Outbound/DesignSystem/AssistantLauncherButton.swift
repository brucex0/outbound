import SwiftUI

struct AssistantLauncherButton: View {
    static let diameter: CGFloat = 56

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.analyticsManager) private var analyticsManager
    let accentColor: Color
    let analyticsDestination: String
    var analyticsEntrySource: String = "persistent_launcher"
    let onOpen: () -> Void

    @State private var scale = 1.0
    @State private var shimmerOpacity = 0.0
    @State private var rotation = 0.0
    @State private var ringScale = 0.72
    @State private var ringOpacity = 0.0
    @State private var hasTrackedForeground = false
    @State private var hasTrackedAnimation = false
    @State private var hasEvaluatedInitialScene = false

    var body: some View {
        Button {
            track(.assistantLauncherOpened, entrySource: analyticsEntrySource)
            onOpen()
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 2)
                    .scaleEffect(ringScale)
                    .opacity(ringOpacity)

                FoxAssistantMark()
                    .rotationEffect(.degrees(rotation))

                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .scaleEffect(1.12)
                    .opacity(shimmerOpacity)
                    .blur(radius: 0.8)
                    .offset(x: 14, y: -14)
            }
            .frame(width: Self.diameter, height: Self.diameter)
            .background(accentColor.gradient, in: Circle())
            .overlay {
                Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
            .scaleEffect(scale)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("assistant.launcher")
        .accessibilityLabel(String(localized: "Open assistant"))
        .accessibilityHint(String(localized: "Get help with this page or anywhere in Plainstride"))
        .task(id: "\(scenePhase)-\(reduceMotion)") {
            await runAnimationLoop()
        }
    }

    @MainActor
    private func runAnimationLoop() async {
        let entrySource = hasEvaluatedInitialScene ? "foreground" : "app_shell"
        hasEvaluatedInitialScene = true

        guard scenePhase == .active, !reduceMotion else {
            hasTrackedForeground = false
            hasTrackedAnimation = false
            resetVisualState()
            return
        }

        if !hasTrackedForeground {
            hasTrackedForeground = true
            track(.assistantLauncherEligibleExposure, entrySource: entrySource)
        }

        do {
            try await Task.sleep(for: .milliseconds(500))
        } catch {
            return
        }

        while !Task.isCancelled, scenePhase == .active {
            if !hasTrackedAnimation {
                hasTrackedAnimation = true
                track(.assistantLauncherAnimationShown, entrySource: "foreground_loop")
            }

            withAnimation(.easeOut(duration: 0.32)) {
                scale = 1.17
                rotation = -10
                shimmerOpacity = 0.9
                ringScale = 0.94
                ringOpacity = 0.82
            }
            do {
                try await Task.sleep(for: .milliseconds(320))
            } catch {
                return
            }

            withAnimation(.spring(duration: 0.65, bounce: 0.38)) {
                scale = 1.0
                rotation = 0
                shimmerOpacity = 0.0
                ringScale = 1.55
                ringOpacity = 0.0
            }
            do {
                try await Task.sleep(for: .milliseconds(650))
            } catch {
                return
            }

            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                ringScale = 0.72
            }
            do {
                try await Task.sleep(for: .milliseconds(2_800))
            } catch {
                return
            }
        }
    }

    @MainActor
    private func resetVisualState() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scale = 1.0
            shimmerOpacity = 0.0
            rotation = 0.0
            ringScale = 0.72
            ringOpacity = 0.0
        }
    }

    private func track(_ name: ProductEventName, entrySource: String) {
        let event = ProductAnalyticsEvent(name, properties: [
            .destination: .string(analyticsDestination),
            .entrySource: .string(entrySource)
        ])
        Task { await analyticsManager?.track(event) }
    }
}

private struct FoxAssistantMark: View {
    var body: some View {
        Image("FoxAssistantHead")
            .resizable()
            .scaledToFit()
            .frame(width: 50, height: 50)
            .accessibilityHidden(true)
    }
}


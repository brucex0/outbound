import SwiftUI

struct AssistantLauncherButton: View {
    static let diameter: CGFloat = 56

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.analyticsManager) private var analyticsManager
    let accentColor: Color
    let analyticsDestination: String
    var analyticsEntrySource: String = "persistent_launcher"
    var isPresenceActive = true
    var deliveryToken: UUID?
    var deliveryIsSubdued = false
    let onOpen: () -> Void

    @State private var rotation = 0.0
    @State private var verticalOffset = 0.0
    @State private var lastAnimatedDeliveryToken: UUID?

    var body: some View {
        Button {
            track(.assistantLauncherOpened, entrySource: analyticsEntrySource)
            onOpen()
        } label: {
            FoxAssistantMark()
                .rotationEffect(.degrees(rotation), anchor: .bottom)
                .offset(y: verticalOffset)
                .frame(width: Self.diameter, height: Self.diameter)
                .background(accentColor.gradient, in: Circle())
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("assistant.launcher")
        .accessibilityLabel(String(localized: "Open assistant"))
        .accessibilityHint(String(localized: "Get help with this page or anywhere in Plainstride"))
        .task(id: "\(scenePhase)-\(reduceMotion)-\(isPresenceActive)-\(deliveryToken?.uuidString ?? "none")") {
            await runPresence()
        }
    }

    @MainActor
    private func runPresence() async {
        resetVisualState()
        guard scenePhase == .active, isPresenceActive else { return }
        guard !reduceMotion else {
            // A static delivery is still delivered; changing the setting later
            // must not replay attention for an old message.
            lastAnimatedDeliveryToken = deliveryToken
            return
        }
        do {
            if let deliveryToken, deliveryToken != lastAnimatedDeliveryToken {
                lastAnimatedDeliveryToken = deliveryToken
                if deliveryIsSubdued {
                    try await tiltHead()
                } else {
                    withAnimation(.easeOut(duration: 0.22)) { verticalOffset = -7 }
                    try await Task.sleep(for: .milliseconds(220))
                    try Task.checkCancellation()
                    withAnimation(.spring(duration: 0.45, bounce: 0.28)) { verticalOffset = 0 }
                    try await Task.sleep(for: .milliseconds(450))
                }
            }
            try await Task.sleep(for: .seconds(20))
            while !Task.isCancelled {
                try await tiltHead()
                try await Task.sleep(for: .seconds(30))
            }
        } catch {
            // View/scene/presentation changes cancel decorative motion normally.
        }
    }

    @MainActor
    private func tiltHead() async throws {
        try Task.checkCancellation()
        withAnimation(.easeInOut(duration: 0.45)) { rotation = -5 }
        try await Task.sleep(for: .milliseconds(650))
        try Task.checkCancellation()
        withAnimation(.easeInOut(duration: 0.5)) { rotation = 0 }
        try await Task.sleep(for: .milliseconds(500))
    }

    @MainActor
    private func resetVisualState() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            rotation = 0
            verticalOffset = 0
        }
    }

    private func track(_ name: ProductEventName, entrySource: String) {
        Task {
            await analyticsManager?.track(.init(name, properties: [
                .destination: .string(analyticsDestination), .entrySource: .string(entrySource)
            ]))
        }
    }
}

struct FoxAssistantMark: View {
    var body: some View {
        Image("FoxAssistantHead")
            .resizable()
            .scaledToFit()
            .frame(width: 50, height: 50)
            .accessibilityHidden(true)
    }
}

/// This mark belongs to the successful-save surface, never activity history or import.
struct FoxCompanionCelebrationMark: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.analyticsManager) private var analyticsManager
    @State private var hasCelebrated = false
    @State private var rotation = 0.0
    @State private var offset = 0.0

    var body: some View {
        FoxAssistantMark()
            .rotationEffect(.degrees(rotation))
            .offset(y: offset)
            .accessibilityIdentifier("fox.companion.celebration")
            .task(id: "\(scenePhase)-\(reduceMotion)") {
                guard scenePhase == .active, !hasCelebrated else { return }
                hasCelebrated = true
                await analyticsManager?.track(.init(.featureExposed, properties: [
                    .feature: .string("fox_companion_presence"), .result: .string("celebration")
                ]))
                guard !Task.isCancelled, scenePhase == .active, !reduceMotion else { return }
                do {
                    withAnimation(.easeOut(duration: 0.25)) { offset = -5; rotation = -8 }
                    try await Task.sleep(for: .milliseconds(250))
                    try Task.checkCancellation()
                    withAnimation(.spring(duration: 0.55, bounce: 0.35)) { offset = 0; rotation = 6 }
                    try await Task.sleep(for: .milliseconds(550))
                    try Task.checkCancellation()
                    withAnimation(.easeOut(duration: 0.35)) { rotation = 0 }
                } catch {
                    // Leaving the success surface cancels this one-shot decoration.
                    offset = 0
                    rotation = 0
                }
            }
    }
}

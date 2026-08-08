import SwiftUI

enum SimplifiedAppTab: Hashable {
    case together
    case today
    case me
}

struct SimplifiedAppShell: View {
    let onStartRun: () -> Void
    @State private var selection: SimplifiedAppTab = .today

    var body: some View {
        TabView(selection: $selection) {
            SimplifiedTogetherView()
                .tag(SimplifiedAppTab.together)
                .tabItem { Label("Together", systemImage: "person.2") }

            SimplifiedTodayView(onStartRun: onStartRun)
                .tag(SimplifiedAppTab.today)
                .tabItem { Label("Today", systemImage: "sparkles") }

            SimplifiedMeView()
                .tag(SimplifiedAppTab.me)
                .tabItem { Label("Me", systemImage: "person.crop.circle") }
        }
        .tint(OutboundPalette.companion)
    }
}

private struct SimplifiedTodayView: View {
    let onStartRun: () -> Void

    private let phases = [
        WorkoutPhaseItem(id: "warmup", duration: "5m", title: "Warm-up", weight: 1),
        WorkoutPhaseItem(id: "relaxed", duration: "20m", title: "Relaxed", weight: 3),
        WorkoutPhaseItem(id: "cooldown", duration: "5m", title: "Cool-down", weight: 1),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: OutboundSpacing.standard) {
                    OutboundCard(style: .companion) {
                        VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                            Text("“You don’t need a perfect run. You need a beginning.”")
                                .font(.title3.weight(.semibold))
                            Text("One relaxed run completes your week.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.78))
                        }
                    }

                    OutboundCard {
                        VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                            Text("TODAY · AI ADJUSTED")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("Easy run · 30 min")
                                .font(.title3.weight(.semibold))
                            Text("Conversational effort")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            WorkoutPhaseSummary(phases: phases)
                            OutboundPrimaryButton(title: "Start run", systemImage: "figure.run", action: onStartRun)
                            HStack {
                                quickAction("15 min", image: "clock")
                                quickAction("Tired", image: "moon.zzz")
                                quickAction("Ask", image: "sparkles")
                            }
                            AIExplanationView(text: "Tuesday was harder than planned, so today stays easy.")
                        }
                    }

                    OutboundCard {
                        HStack(spacing: OutboundSpacing.standard) {
                            Image(systemName: "heart.circle.fill")
                                .font(.title2)
                                .foregroundStyle(OutboundPalette.companion)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Better together")
                                    .font(.headline)
                                Text("A family member has a compatible easy run.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Invite") {}
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
                .padding(.horizontal, OutboundSpacing.screen)
                .padding(.vertical, OutboundSpacing.standard)
            }
            .background(OutboundPalette.background)
            .navigationTitle("Today")
        }
    }

    private func quickAction(_ title: String, image: String) -> some View {
        Button {} label: {
            Label(title, systemImage: image)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 38)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control))
    }
}

private struct SimplifiedTogetherView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                    Text("UP NEXT")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    OutboundCard {
                        VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                            Text("Run with family")
                                .font(.headline)
                            Text("Today after 6:30 · Easy 30 min")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            AIExplanationView(text: "Your workouts are compatible.")
                        }
                    }

                    Text("CLUBS")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    OutboundCard {
                        VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                            Text("Saturday long run")
                                .font(.headline)
                            Text("8:00 AM · Three distance groups")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            AIExplanationView(text: "The middle-distance group matches your plan.")
                        }
                    }
                }
                .padding(OutboundSpacing.screen)
            }
            .background(OutboundPalette.background)
            .navigationTitle("Together")
        }
    }
}

private struct SimplifiedMeView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: OutboundSpacing.standard) {
                    OutboundCard {
                        VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                            Text("CURRENT FOCUS")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("Run consistently · Week 3 of 8")
                                .font(.headline)
                            Text("3 runs per week")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    OutboundCard {
                        VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                            HStack {
                                Text("This week")
                                    .font(.headline)
                                Spacer()
                                Text("2 of 3")
                                    .font(.headline)
                            }
                            ProgressView(value: 2, total: 3)
                                .tint(OutboundPalette.companion)
                            AIExplanationView(text: "One easy run completes the week.")
                        }
                    }
                }
                .padding(OutboundSpacing.screen)
            }
            .background(OutboundPalette.background)
            .navigationTitle("Me")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") {}
                }
            }
        }
    }
}

#Preview {
    SimplifiedAppShell(onStartRun: {})
}


import SwiftUI

struct CircleCompactCard: View {
    let circle: CircleDTO
    let isPrimary: Bool

    var body: some View {
        OutboundCard(style: .companion) {
            CircleCompactContent(circle: circle, isPrimary: isPrimary)
        }
    }
}

struct CircleCompactContent: View {
    let circle: CircleDTO
    let isPrimary: Bool
    var isMinimized = false
    var showsNavigationIndicator = true

    var body: some View {
        HStack(spacing: isMinimized ? OutboundSpacing.compact : OutboundSpacing.standard) {
            Image(systemName: circle.lifecycle == "archived" ? "archivebox" : "person.3.fill")
                .font(isMinimized ? .subheadline : .title2)
                .foregroundStyle(OutboundPalette.companion)
                .frame(width: isMinimized ? 34 : 44, height: isMinimized ? 34 : 44)
                .background(OutboundPalette.companion.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(circle.name).font(.headline).foregroundStyle(.primary).lineLimit(1)
                    if isPrimary { Image(systemName: "star.fill").font(.caption2).foregroundStyle(OutboundPalette.companion) }
                }
                if !isMinimized {
                    Text(statusText).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if showsNavigationIndicator {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        if circle.lifecycle == "archived" { return String(localized: "circle.status.archived", defaultValue: "Archived") }
        if circle.lifecycle == "awaiting_members" { return String(localized: "circle.status.awaiting", defaultValue: "Waiting for someone to join") }
        let personalCount = circle.members.first(where: \.isCurrentUser)?.contributedCount ?? 0
        if !circle.week.focusConfigured {
            return personalCount > 0
                ? String(localized: "circle.today.personal_contribution", defaultValue: "You contributed \(personalCount) this week")
                : String(localized: "circle.today.plan_activity", defaultValue: "Plan something active together")
        }
        if circle.week.focusMode == "none" {
            return personalCount > 0
                ? String(localized: "circle.today.personal_contribution", defaultValue: "You contributed \(personalCount) this week")
                : String(localized: "circle.today.no_target", defaultValue: "No numeric goal · Move together")
        }
        if let target = circle.week.targetCount {
            return String(localized: "circle.today.progress", defaultValue: "You: \(personalCount) · Together: \(circle.week.contributedCount) of \(target)")
        }
        return String(localized: "circle.focus.choose", defaultValue: "Choose a weekly focus")
    }
}

struct CircleCreateView: View {
    @Environment(\.analyticsManager) private var analyticsManager
    @EnvironmentObject private var circleStore: CircleStore
    @EnvironmentObject private var socialStore: TogetherStore
    @State private var name = ""
    @State private var selectedIDs: Set<String> = []
    @State private var createdCircle: CircleDTO?
    @State private var isSubmitting = false

    private var connections: [SocialConnectionDTO] { socialStore.connections.filter { $0.status == "accepted" } }
    private var inviteLimit: Int { max(1, circleStore.memberLimit - 1) }

    var body: some View {
        Group {
            if let createdCircle {
                CircleCreatedView(circle: createdCircle)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                        creationHero

                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(String(localized: "circle.create.people", defaultValue: "Who helps you keep moving?"))
                                    .font(.headline)
                                Spacer()
                                if !selectedIDs.isEmpty {
                                    Text(String(localized: "circle.create.selected", defaultValue: "\(selectedIDs.count) selected"))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(OutboundPalette.companion)
                                }
                            }
                            Text(String(localized: "circle.create.people_help", defaultValue: "Choose at least one friend or family member. You can invite more later."))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        OutboundCard {
                            VStack(spacing: 0) {
                                ForEach(Array(connections.enumerated()), id: \.element.id) { index, connection in
                                    Button { toggle(connection.person.id) } label: {
                                        HStack(spacing: 12) {
                                            SocialAvatar(name: connection.person.displayName, avatarURL: connection.person.avatarUrl)
                                            Text(connection.person.displayName).foregroundStyle(.primary)
                                            Spacer()
                                            Image(systemName: selectedIDs.contains(connection.person.id) ? "checkmark.circle.fill" : "circle")
                                                .font(.title3)
                                                .foregroundStyle(selectedIDs.contains(connection.person.id) ? OutboundPalette.companion : .secondary)
                                        }
                                        .frame(minHeight: 52)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!selectedIDs.contains(connection.person.id) && selectedIDs.count >= inviteLimit)
                                    if index < connections.count - 1 { Divider().padding(.leading, 52) }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(localized: "circle.create.name", defaultValue: "Name your Circle · Optional"))
                                .font(.headline)
                            TextField(String(localized: "circle.create.name_placeholder", defaultValue: "Weekend energy, Family movers…"), text: $name)
                                .textInputAutocapitalization(.words)
                                .padding(12)
                                .background(OutboundPalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Text(String(localized: "circle.create.name_help", defaultValue: "Leave it blank and Plainstride will suggest a name."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Label(
                            String(localized: "circle.create.closeness", defaultValue: "Made for the family and friends who know you best."),
                            systemImage: "heart.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(OutboundSpacing.screen)
                }
                .background(OutboundPalette.background)
                .safeAreaInset(edge: .bottom) {
                    Button { Task { await create() } } label: {
                        HStack {
                            Spacer()
                            if isSubmitting { ProgressView() } else { Text(String(localized: "circle.create.action", defaultValue: "Create your Circle")).fontWeight(.semibold) }
                            Spacer()
                        }
                        .frame(minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(OutboundPalette.companion)
                    .disabled(isSubmitting || selectedIDs.isEmpty)
                    .padding(.horizontal, OutboundSpacing.screen)
                    .padding(.vertical, 10)
                    .background(.bar)
                }
                .navigationTitle(String(localized: "circle.create.navigation", defaultValue: "Create your Circle"))
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .task {
            await analyticsManager?.track(.init(.circleCreationStarted, properties: [.entrySource: .string("social")]))
            if socialStore.connections.isEmpty { await socialStore.refreshConnections() }
            await socialStore.loadRemainingConnections()
        }
    }

    private var creationHero: some View {
        OutboundCard(style: .companion) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ForEach(["figure.walk", "figure.run", "figure.outdoor.cycle"], id: \.self) { symbol in
                        Image(systemName: symbol)
                            .font(.title2)
                            .foregroundStyle(OutboundPalette.companion)
                            .frame(width: 44, height: 44)
                            .background(OutboundPalette.companion.opacity(0.12), in: Circle())
                    }
                }
                Text(String(localized: "circle.create.inspiration_title", defaultValue: "Active. Positive. Together."))
                    .font(.title2.bold())
                Text(String(localized: "circle.create.inspiration_detail", defaultValue: "Share goals and progress with the people closest to you—and cheer each other on."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func toggle(_ id: String) { if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) } }

    private func create() async {
        isSubmitting = true
        defer { isSubmitting = false }
        if let created = await circleStore.create(name: name, memberUserIDs: Array(selectedIDs)) {
            createdCircle = created
            await analyticsManager?.track(.init(.circleCreationCompleted, properties: [.entrySource: .string("social"), .participantCountBucket: .string(ProductAnalyticsBucket.count(selectedIDs.count + 1))]))
            await analyticsManager?.track(.init(.circleInvitationSent, properties: [.entrySource: .string("creation"), .participantCountBucket: .string(ProductAnalyticsBucket.count(selectedIDs.count)), .result: .string("success")]))
        } else {
            await analyticsManager?.track(.init(.circleCreationFailed, properties: [.entrySource: .string("social"), .errorCategory: .string("api_unavailable")]))
        }
    }
}

private struct CircleCreatedView: View {
    @EnvironmentObject private var circleStore: CircleStore
    let circle: CircleDTO
    @State private var showsFocus = false

    private var current: CircleDTO { circleStore.circles.first(where: { $0.id == circle.id }) ?? circle }
    private var invitedPeople: [CirclePersonDTO] {
        [current.owner] + current.invitations.compactMap(\.recipient)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 66))
                    .foregroundStyle(OutboundPalette.companion)
                VStack(spacing: 8) {
                    Text(String(localized: "circle.created.title", defaultValue: "A healthier week starts together."))
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                    Text(String(localized: "circle.created.detail", defaultValue: "Your invitations are on the way. When someone joins, activities can begin building shared momentum."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: -8) {
                    ForEach(invitedPeople) { person in
                        SocialAvatar(name: person.displayName, avatarURL: person.avatarUrl)
                            .overlay(Circle().stroke(OutboundPalette.background, lineWidth: 2))
                    }
                }
                VStack(spacing: 0) {
                    createdBenefit(icon: "figure.mixed.cardio", text: String(localized: "circle.created.benefit_activity", defaultValue: "Walking, running, riding, hiking, and swimming all count."))
                    Divider().padding(.leading, 48)
                    createdBenefit(icon: "heart.fill", text: String(localized: "circle.created.benefit_cheer", defaultValue: "Notice the effort and send a Cheer."))
                    Divider().padding(.leading, 48)
                    createdBenefit(icon: "chart.xyaxis.line", text: String(localized: "circle.created.benefit_details", defaultValue: "See the workout behind the progress and celebrate it together."))
                }
                .padding(.horizontal, 14)
                .background(OutboundPalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(spacing: 10) {
                    Button(String(localized: "circle.created.choose_focus", defaultValue: "Choose a weekly focus")) { showsFocus = true }
                        .buttonStyle(.borderedProminent)
                        .tint(OutboundPalette.companion)
                        .frame(maxWidth: .infinity, minHeight: 50)
                    NavigationLink {
                        CircleDetailView(circle: current)
                    } label: {
                        Text(String(localized: "circle.created.open", defaultValue: "Open Circle"))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    Text(String(localized: "circle.created.focus_optional", defaultValue: "A numeric goal is optional. You can simply encourage each other."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(OutboundSpacing.screen)
        }
        .background(OutboundPalette.background)
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsFocus) { NavigationStack { CircleFocusEditor(circle: current) } }
    }

    private func createdBenefit(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(OutboundPalette.companion).frame(width: 28)
            Text(text).font(.subheadline)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 54)
    }
}

struct CircleDetailView: View {
    @Environment(\.analyticsManager) private var analyticsManager
    @EnvironmentObject private var circleStore: CircleStore
    @EnvironmentObject private var socialStore: TogetherStore
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    let circle: CircleDTO
    @State private var showsPlanActivity = false
    @State private var showsFocus = false

    private var current: CircleDTO { circleStore.circles.first(where: { $0.id == circle.id }) ?? circle }
    private var invitees: [CirclePersonDTO] { current.members.filter { !$0.isCurrentUser }.map(\.user) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                header
                focusCard
                membersSection
                Button { showsPlanActivity = true; track(.circlePlanActivityStarted, [.entrySource: .string("circle_detail"), .participantCountBucket: .string(ProductAnalyticsBucket.count(current.memberCount))]) } label: {
                    Label(String(localized: "circle.plan_activity", defaultValue: "Plan an activity"), systemImage: "calendar.badge.plus")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(OutboundPalette.companion)

                if !current.recentMoments.isEmpty { momentsSection }
                if let history = current.history, !history.isEmpty { historySection(history) }
            }
            .padding(OutboundSpacing.screen)
        }
        .background(OutboundPalette.background)
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            NavigationLink { CircleManagementView(circle: current) } label: { Image(systemName: "gearshape") }
                .accessibilityLabel(String(localized: "circle.management", defaultValue: "Circle settings"))
        }
        .sheet(isPresented: $showsPlanActivity) {
            CreateActivityEventView(
                sourceCircleID: current.id,
                preselectedConnectionIDs: Set(invitees.map(\.id)),
                additionalInvitees: invitees
            ) {
                track(.circlePlanActivityCompleted, [.participantCountBucket: .string(ProductAnalyticsBucket.count(invitees.count + 1)), .result: .string("success")])
            }
            .environmentObject(socialStore)
        }
        .sheet(isPresented: $showsFocus) { NavigationStack { CircleFocusEditor(circle: current) } }
        .task {
            await circleStore.refreshCircle(id: current.id)
            track(.circleProgressOpened, [.entrySource: .string("circle_detail"), .selectionType: .string(current.week.focusMode), .participantCountBucket: .string(ProductAnalyticsBucket.count(current.memberCount))])
        }
    }

    private var header: some View {
        OutboundCard(style: .companion) {
            VStack(alignment: .leading, spacing: 12) {
                Text(current.lifecycle == "awaiting_members" ? String(localized: "circle.status.awaiting", defaultValue: "Waiting for someone to join") : String(localized: "circle.private", defaultValue: "Trusted Circle"))
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(String(localized: "circle.detail.inspiration", defaultValue: "Building a positive life, one activity at a time."))
                    .font(.headline)
                HStack(spacing: -8) { ForEach(current.members.prefix(6)) { SocialAvatar(name: $0.user.displayName, avatarURL: $0.user.avatarUrl).overlay(Circle().stroke(OutboundPalette.background, lineWidth: 2)) } }
                Text(String(localized: "circle.members.count", defaultValue: "\(current.memberCount) members")).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var focusCard: some View {
        OutboundCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(String(localized: "circle.weekly_focus", defaultValue: "Weekly Focus")).font(.headline)
                    Spacer()
                    Button(!current.week.focusConfigured
                        ? String(localized: "circle.focus.choose_action", defaultValue: "Choose")
                        : String(localized: "common.edit", defaultValue: "Edit")) {
                        showsFocus = true
                    }
                }
                if !current.week.focusConfigured {
                    Text(String(localized: "circle.focus.unconfigured", defaultValue: "Choose a flexible focus when the Circle is ready."))
                        .font(.subheadline).foregroundStyle(.secondary)
                } else if current.week.focusMode == "none" {
                    Text(String(localized: "circle.focus.none.detail", defaultValue: "No numeric goal this week. Cheer each other on or plan something active."))
                } else if let target = current.week.targetCount {
                    ProgressView(value: min(Double(current.week.contributedCount) / Double(max(target, 1)), 1)).tint(OutboundPalette.companion)
                    Text(String(localized: "circle.progress.format", defaultValue: "\(current.week.contributedCount) of \(target) activities this week")).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "circle.members", defaultValue: "MEMBERS")).socialSectionLabel()
            ForEach(current.members) { member in
                OutboundCard {
                    HStack(spacing: 12) {
                        SocialAvatar(name: member.user.displayName, avatarURL: member.user.avatarUrl)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(member.user.displayName).font(.headline)
                            Text(memberStatus(member)).font(.caption).foregroundStyle(.secondary)
                            if let activity = member.recentActivity {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(activityTitle(activity))
                                        .font(.subheadline.weight(.semibold))
                                    Text(activitySummary(activity))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                .padding(.top, 5)
                            }
                        }
                        Spacer()
                        if !member.isCurrentUser {
                            Menu {
                                ForEach(["encouragement", "celebration", "support"], id: \.self) { preset in
                                    if let existing = existingCheer(to: member, preset: preset) {
                                        Button(String(format: String(localized: "circle.cheer.remove_format", defaultValue: "Remove %@"), cheerTitle(preset)), role: .destructive) {
                                            Task {
                                                if await circleStore.removeCheer(existing, from: current) != nil {
                                                    track(.circleCheerRemoved, [.selectionType: .string(preset)])
                                                }
                                            }
                                        }
                                    } else {
                                        Button(cheerTitle(preset)) {
                                            Task {
                                                if await circleStore.sendCheer(circle: current, member: member, presetType: preset) {
                                                    track(.circleCheerSent, [.selectionType: .string(preset)])
                                                }
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "heart").frame(width: 44, height: 44)
                            }
                                .accessibilityLabel(String(localized: "circle.cheer", defaultValue: "Send a Cheer"))
                        }
                    }
                }
            }
        }
    }

    private var momentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "circle.moments", defaultValue: "RECENT MOMENTS")).socialSectionLabel()
            OutboundCard { ForEach(current.recentMoments) { moment in HStack { Image(systemName: moment.type == "cheer" ? "heart.fill" : moment.type == "planned_run" ? "calendar" : "sparkles").foregroundStyle(OutboundPalette.companion); Text(momentText(moment)).font(.subheadline); Spacer(); Text(moment.createdAt, style: .relative).font(.caption).foregroundStyle(.secondary) }.frame(minHeight: 44) } }
        }
    }

    private func historySection(_ history: [CircleWeekHistoryDTO]) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(String(localized: "circle.history", defaultValue: "HISTORY")).socialSectionLabel(); OutboundCard { ForEach(history.prefix(6)) { week in HStack { Text(week.startsAt.formatted(date: .abbreviated, time: .omitted)); Spacer(); Text(week.state == "completed" ? String(localized: "circle.completed", defaultValue: "Completed") : String(localized: "circle.week.recorded", defaultValue: "Week recorded")).foregroundStyle(.secondary) }.frame(minHeight: 44) } } }
    }

    private func memberStatus(_ member: CircleMemberDTO) -> String {
        if member.commitment?.skipped == true { return String(localized: "circle.commitment.skipping", defaultValue: "Skipping this week") }
        if let target = member.commitment?.targetCount { return String(localized: "circle.member.progress", defaultValue: "\(member.contributedCount) of \(target)") }
        return String(localized: "circle.member.contributed", defaultValue: "Contributed \(member.contributedCount)")
    }
    private func activityTypeTitle(_ type: String) -> String {
        switch type {
        case "cycling": return String(localized: "circle.activity.ride", defaultValue: "Ride")
        case "hiking": return String(localized: "circle.activity.hike", defaultValue: "Hike")
        case "walking": return String(localized: "circle.activity.walk", defaultValue: "Walk")
        case "swimming": return String(localized: "circle.activity.swim", defaultValue: "Swim")
        default: return String(localized: "circle.activity.run", defaultValue: "Run")
        }
    }
    private func activityTitle(_ activity: CircleActivitySummaryDTO) -> String {
        let title = activity.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? activityTypeTitle(activity.type) : title
    }
    private func activitySummary(_ activity: CircleActivitySummaryDTO) -> String {
        var parts = [activity.startedAt.formatted(date: .abbreviated, time: .shortened)]
        if let distance = activity.distanceM, distance > 0 {
            parts.append(measurementPreferences.unitSystem.distanceString(meters: distance, fractionDigits: 1))
        }
        if let elevation = activity.elevationM, elevation > 0 {
            parts.append(measurementPreferences.unitSystem.elevationString(meters: elevation))
        }
        if let duration = activity.durationSecs, duration > 0 {
            let hours = duration / 3_600
            let minutes = max(1, (duration % 3_600) / 60)
            parts.append(hours > 0
                ? String(localized: "circle.activity.duration.hours_minutes", defaultValue: "\(hours) hr \(minutes) min")
                : String(localized: "circle.activity.duration.minutes", defaultValue: "\(minutes) min"))
        }
        if let pace = activity.avgPace, pace > 0 {
            parts.append(pace.paceString(for: measurementPreferences.unitSystem))
        }
        if let heartRate = activity.avgHeartRate, heartRate > 0 {
            parts.append(String(localized: "circle.activity.heart_rate", defaultValue: "\(heartRate) bpm"))
        }
        if let calories = activity.energyKilocalories, calories > 0 {
            parts.append(String(localized: "circle.activity.calories", defaultValue: "\(calories) cal"))
        }
        return parts.joined(separator: " · ")
    }
    private func cheerTitle(_ preset: String) -> String {
        switch preset {
        case "celebration": return String(localized: "circle.cheer.celebration", defaultValue: "Celebrate")
        case "support": return String(localized: "circle.cheer.support", defaultValue: "Support")
        default: return String(localized: "circle.cheer.encouragement", defaultValue: "Keep going")
        }
    }
    private func existingCheer(to member: CircleMemberDTO, preset: String) -> CircleCheerDTO? {
        guard let currentUserID = current.members.first(where: \.isCurrentUser)?.user.id else { return nil }
        return current.cheers.first { $0.senderUserId == currentUserID && $0.recipientUserId == member.user.id && $0.presetType == preset }
    }

    private func momentText(_ moment: CircleMomentDTO) -> String {
        switch moment.type {
        case "planned_run": return moment.title ?? String(localized: "circle.moment.activity_planned", defaultValue: "Activity planned")
        case "weekly_completion": return String(localized: "circle.moment.completed", defaultValue: "Weekly focus completed")
        default: return String(localized: "circle.moment.cheer", defaultValue: "A Cheer was sent")
        }
    }
    private func track(_ event: ProductEventName, _ properties: [ProductPropertyKey: AnalyticsValue]) { Task { await analyticsManager?.track(.init(event, properties: properties)) } }
}

struct CircleFocusEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.analyticsManager) private var analyticsManager
    @EnvironmentObject private var circleStore: CircleStore
    let circle: CircleDTO
    @State private var mode: String
    @State private var sharedTarget: Int
    @State private var personalTarget: Int
    @State private var apply = "now"
    @State private var skip = false

    init(circle: CircleDTO) {
        self.circle = circle
        let ownCommitment = circle.members.first(where: \.isCurrentUser)?.commitment
        _mode = State(initialValue: circle.week.focusMode)
        _sharedTarget = State(initialValue: circle.week.sharedTarget ?? 3)
        _personalTarget = State(initialValue: ownCommitment?.targetCount ?? 3)
        _skip = State(initialValue: ownCommitment?.skipped ?? false)
    }

    private var current: CircleDTO { circleStore.circles.first(where: { $0.id == circle.id }) ?? circle }

    var body: some View {
        Form {
            if circle.role == "owner" {
                Section { Picker(String(localized: "circle.focus.mode", defaultValue: "Focus mode"), selection: $mode) { Text(String(localized: "circle.focus.personal", defaultValue: "Personal targets · Recommended")).tag("personal_targets"); Text(String(localized: "circle.focus.shared", defaultValue: "One shared target")).tag("shared_target"); Text(String(localized: "circle.focus.none", defaultValue: "No numeric target")).tag("none") } }
                if mode == "shared_target" {
                    Section {
                        targetPresets(selection: $sharedTarget)
                        Stepper(String(localized: "circle.focus.shared_count", defaultValue: "\(sharedTarget) activities together"), value: $sharedTarget, in: 1...100)
                    }
                }
                Section { Picker(String(localized: "circle.focus.apply", defaultValue: "Apply"), selection: $apply) { Text(String(localized: "circle.apply.now", defaultValue: "Now")).tag("now"); Text(String(localized: "circle.apply.next", defaultValue: "Next week")).tag("next_week") } }
            }
            if editsCurrentPersonalFocus {
                Section(String(localized: "circle.commitment.mine", defaultValue: "My target")) {
                    targetPresets(selection: $personalTarget)
                    Stepper(String(localized: "circle.commitment.count", defaultValue: "\(personalTarget) activities"), value: $personalTarget, in: 1...100)
                    Toggle(String(localized: "circle.commitment.skip", defaultValue: "Skip this week"), isOn: $skip)
                }
            }
        }
        .navigationTitle(String(localized: "circle.weekly_focus", defaultValue: "Weekly Focus"))
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "common.close", defaultValue: "Close")) { dismiss() } } }
        .onDisappear { saveDraftIfNeeded() }
    }

    private func targetPresets(selection: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "circle.focus.suggestions", defaultValue: "Suggestions"))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                ForEach([2, 3, 4, 5], id: \.self) { value in
                    Button("\(value)") { selection.wrappedValue = value }
                        .buttonStyle(.bordered)
                        .tint(selection.wrappedValue == value ? OutboundPalette.companion : .secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel(String(localized: "circle.focus.preset_accessibility", defaultValue: "\(value) activities"))
                }
            }
        }
    }

    private var editsCurrentPersonalFocus: Bool {
        if circle.role == "owner", apply == "now" { return mode == "personal_targets" }
        return current.week.focusConfigured && current.week.focusMode == "personal_targets"
    }

    private func saveDraftIfNeeded() {
        let draftMode = mode
        let draftSharedTarget = sharedTarget
        let draftPersonalTarget = personalTarget
        let draftApply = apply
        let draftSkipped = skip
        let originalCommitment = circle.members.first(where: \.isCurrentUser)?.commitment
        let originalPersonalTarget = originalCommitment?.targetCount ?? 3
        let originalSkipped = originalCommitment?.skipped ?? false
        let normalizedSharedTarget = draftMode == "shared_target" ? draftSharedTarget : nil
        let originalSharedTarget = circle.week.focusMode == "shared_target" ? circle.week.sharedTarget : nil
        let focusChanged = circle.role == "owner" && (
            draftMode != circle.week.focusMode ||
            normalizedSharedTarget != originalSharedTarget ||
            draftApply != "now"
        )
        let intendedCurrentMode = circle.role == "owner" && draftApply == "now" ? draftMode : circle.week.focusMode
        let enteredPersonalFocus = circle.week.focusMode != "personal_targets" && intendedCurrentMode == "personal_targets"
        let commitmentChanged = intendedCurrentMode == "personal_targets" && (
            draftPersonalTarget != originalPersonalTarget || draftSkipped != originalSkipped || enteredPersonalFocus
        )
        guard focusChanged || commitmentChanged else { return }

        let circleSnapshot = current
        Task {
            var focusSaved = true
            if focusChanged {
                focusSaved = await circleStore.updateFocus(circle: circleSnapshot, mode: draftMode, sharedTarget: normalizedSharedTarget, apply: draftApply) != nil
                if focusSaved {
                    await analyticsManager?.track(.init(.circleFocusChanged, properties: [.selectionType: .string(draftMode), .sourceType: .string(draftApply)]))
                    if let normalizedSharedTarget {
                        await analyticsManager?.track(.init(.circleTargetChanged, properties: [.selectionType: .string("shared"), .targetBucket: .string(ProductAnalyticsBucket.count(normalizedSharedTarget)), .sourceType: .string(draftApply)]))
                    }
                }
            }
            guard commitmentChanged, focusSaved else { return }
            if await circleStore.updateCommitment(circle: circleSnapshot, targetCount: draftSkipped ? nil : draftPersonalTarget, skipped: draftSkipped) != nil {
                await analyticsManager?.track(.init(.circleTargetChanged, properties: [.selectionType: .string(draftSkipped ? "skipped" : "target"), .targetBucket: .string(ProductAnalyticsBucket.count(draftPersonalTarget)), .sourceType: .string("now")]))
            }
        }
    }
}

struct CircleManagementView: View {
    @Environment(\.analyticsManager) private var analyticsManager
    @EnvironmentObject private var circleStore: CircleStore
    @EnvironmentObject private var socialStore: TogetherStore
    @Environment(\.dismiss) private var dismiss
    let circle: CircleDTO
    @State private var name: String
    @State private var resetWeekday: Int
    @State private var timeZone: String
    @State private var calendarApply = "next_week"
    @State private var notificationMuted: Bool
    @State private var showsInvite = false
    @State private var savedName: String
    @State private var savedResetWeekday: Int
    @State private var savedTimeZone: String
    @State private var savedCalendarApply = "next_week"
    @State private var savedNotificationMuted: Bool

    init(circle: CircleDTO) {
        self.circle = circle
        _name = State(initialValue: circle.name)
        _resetWeekday = State(initialValue: circle.resetWeekday)
        _timeZone = State(initialValue: circle.timeZone)
        _notificationMuted = State(initialValue: circle.currentUserMuted)
        _savedName = State(initialValue: circle.name)
        _savedResetWeekday = State(initialValue: circle.resetWeekday)
        _savedTimeZone = State(initialValue: circle.timeZone)
        _savedNotificationMuted = State(initialValue: circle.currentUserMuted)
    }
    private var current: CircleDTO { circleStore.circles.first(where: { $0.id == circle.id }) ?? circle }

    var body: some View {
        Form {
            Section { NavigationLink(String(localized: "circle.weekly_focus", defaultValue: "Weekly Focus")) { CircleFocusEditor(circle: current) }; Button(current.id == circleStore.primaryCircleID ? String(localized: "circle.primary.current", defaultValue: "Primary Circle") : String(localized: "circle.primary.make", defaultValue: "Make primary")) { Task { if await circleStore.selectPrimary(current) { track(.circlePrimaryChanged, [.entrySource: .string("circle_settings")]) } } }.disabled(current.id == circleStore.primaryCircleID || !current.eligibleForToday); Toggle(String(localized: "circle.notifications.mute", defaultValue: "Mute optional notifications"), isOn: $notificationMuted) }

            if current.role == "owner" {
                Section(String(localized: "circle.management.owner", defaultValue: "Owner controls")) { TextField(String(localized: "circle.create.name", defaultValue: "Name"), text: $name); if current.lifecycle != "archived" { Button(String(localized: "circle.invite.more", defaultValue: "Invite connections")) { showsInvite = true } } }
                if !current.invitations.isEmpty {
                    Section(String(localized: "circle.invitations.pending", defaultValue: "Pending invitations")) {
                        ForEach(current.invitations) { invitation in
                            HStack {
                                Text(invitation.recipient?.displayName ?? String(localized: "circle.invitation.pending_person", defaultValue: "Invited person"))
                                Spacer()
                                Button(String(localized: "circle.invitation.cancel", defaultValue: "Cancel"), role: .destructive) {
                                    Task {
                                        if await circleStore.cancel(invitation, in: current) != nil {
                                            track(.circleInvitationCancelled, [.entrySource: .string("circle_settings")])
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                Section(String(localized: "circle.week.settings", defaultValue: "Circle week")) { Picker(String(localized: "circle.reset_day", defaultValue: "Reset day"), selection: $resetWeekday) { ForEach(1...7, id: \.self) { Text(isoWeekdayName($0)).tag($0) } }; TextField(String(localized: "circle.timezone", defaultValue: "Time zone"), text: $timeZone); Picker(String(localized: "circle.focus.apply", defaultValue: "Apply"), selection: $calendarApply) { Text(String(localized: "circle.apply.now", defaultValue: "Now")).tag("now"); Text(String(localized: "circle.apply.next", defaultValue: "Next week")).tag("next_week") } }
                Section(String(localized: "circle.members.manage", defaultValue: "Members")) { ForEach(current.members.filter { !$0.isCurrentUser }) { member in Menu { Button(String(localized: "circle.transfer", defaultValue: "Transfer ownership")) { Task { if await circleStore.transferOwnership(of: current, to: member) != nil { track(.circleOwnershipTransferred, [.participantCountBucket: .string(ProductAnalyticsBucket.count(current.memberCount))]) } } }; Button(String(localized: "circle.remove_member", defaultValue: "Remove member"), role: .destructive) { Task { if await circleStore.removeMember(member, from: current) != nil { track(.circleMemberRemoved, [.participantCountBucket: .string(ProductAnalyticsBucket.count(current.memberCount))]) } } } } label: { HStack { Text(member.user.displayName); Spacer(); Image(systemName: "ellipsis").frame(width: 44, height: 44) } } } }
                Section { if current.lifecycle == "archived" { Button(String(localized: "circle.reactivate", defaultValue: "Reactivate Circle")) { Task { if await circleStore.reactivate(current) != nil { track(.circleReactivated, [.participantCountBucket: .string(ProductAnalyticsBucket.count(current.memberCount))]) } } } } else { Button(String(localized: "circle.archive", defaultValue: "Archive Circle"), role: .destructive) { Task { if await circleStore.archive(current) { track(.circleArchived, [.participantCountBucket: .string(ProductAnalyticsBucket.count(current.memberCount))]) } } } } }
            } else {
                Section { Button(String(localized: "circle.leave", defaultValue: "Leave Circle"), role: .destructive) { Task { if await circleStore.leave(current) { track(.circleMemberLeft, [.participantCountBucket: .string(ProductAnalyticsBucket.count(current.memberCount))]); dismiss() } } } }
            }
        }
        .navigationTitle(String(localized: "circle.management", defaultValue: "Circle settings"))
        .sheet(isPresented: $showsInvite) { CircleInviteView(circle: current) }
        .onDisappear { saveDraftIfNeeded() }
    }

    private func saveDraftIfNeeded() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTimeZone = timeZone.trimmingCharacters(in: .whitespacesAndNewlines)
        let draftResetWeekday = resetWeekday
        let draftCalendarApply = calendarApply
        let draftNotificationMuted = notificationMuted
        let nameChanged = trimmedName != savedName
        let calendarChanged = draftResetWeekday != savedResetWeekday || trimmedTimeZone != savedTimeZone || draftCalendarApply != savedCalendarApply
        let notificationsChanged = draftNotificationMuted != savedNotificationMuted
        guard nameChanged || calendarChanged || notificationsChanged else { return }

        let circleSnapshot = current
        Task {
            if nameChanged, await circleStore.updateName(circle: circleSnapshot, name: trimmedName) != nil {
                savedName = trimmedName
                await analyticsManager?.track(.init(.circleNameChanged))
            }
            if calendarChanged, await circleStore.updateCalendar(circle: circleSnapshot, resetWeekday: draftResetWeekday, timeZone: trimmedTimeZone, apply: draftCalendarApply) != nil {
                savedResetWeekday = draftResetWeekday
                savedTimeZone = trimmedTimeZone
                savedCalendarApply = draftCalendarApply
                await analyticsManager?.track(.init(.circleCalendarChanged, properties: [.sourceType: .string(draftCalendarApply)]))
            }
            if notificationsChanged, await circleStore.setMuted(circleSnapshot, muted: draftNotificationMuted) {
                savedNotificationMuted = draftNotificationMuted
                await analyticsManager?.track(.init(.circleNotificationsChanged, properties: [.selectionType: .string(draftNotificationMuted ? "muted" : "unmuted")]))
            }
        }
    }

    private func isoWeekdayName(_ isoWeekday: Int) -> String {
        Calendar.current.weekdaySymbols[isoWeekday % 7]
    }
    private func track(_ event: ProductEventName, _ properties: [ProductPropertyKey: AnalyticsValue]) { Task { await analyticsManager?.track(.init(event, properties: properties)) } }
}

private struct CircleInviteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.analyticsManager) private var analyticsManager
    @EnvironmentObject private var circleStore: CircleStore
    @EnvironmentObject private var socialStore: TogetherStore
    let circle: CircleDTO
    @State private var selected: Set<String> = []
    private var eligible: [SocialConnectionDTO] { let existing = Set(circle.members.map { $0.user.id }); return socialStore.connections.filter { $0.status == "accepted" && !existing.contains($0.person.id) } }
    var body: some View { NavigationStack { List(eligible) { connection in Button { if selected.contains(connection.person.id) { selected.remove(connection.person.id) } else { selected.insert(connection.person.id) } } label: { HStack { SocialAvatar(name: connection.person.displayName, avatarURL: connection.person.avatarUrl); Text(connection.person.displayName).foregroundStyle(.primary); Spacer(); Image(systemName: selected.contains(connection.person.id) ? "checkmark.circle.fill" : "circle") } }.disabled(!selected.contains(connection.person.id) && selected.count >= max(0, circle.memberLimit - circle.memberCount - circle.invitations.count)) }.navigationTitle(String(localized: "circle.invite.more", defaultValue: "Invite connections")).toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "common.close", defaultValue: "Close")) { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(String(localized: "circle.invitation.send", defaultValue: "Send")) { Task { let invitationCount = selected.count; if await circleStore.invite(Array(selected), to: circle) != nil { await analyticsManager?.track(.init(.circleInvitationSent, properties: [.entrySource: .string("circle_settings"), .participantCountBucket: .string(ProductAnalyticsBucket.count(invitationCount)), .result: .string("success")])); dismiss() } } }.disabled(selected.isEmpty) } }.task { await socialStore.loadRemainingConnections() } } }
}

struct CircleCompletionCelebrationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let circle: CircleDTO
    let onDismiss: () -> Void
    var body: some View {
        ZStack {
            OutboundPalette.background.ignoresSafeArea()
            VStack(spacing: 20) {
                if reduceMotion {
                    Image(systemName: "sparkles")
                        .font(.system(size: 58))
                        .foregroundStyle(OutboundPalette.companion)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 58))
                        .foregroundStyle(OutboundPalette.companion)
                        .symbolEffect(.bounce, options: .repeat(2))
                }
                Text(String(localized: "circle.celebration.title", defaultValue: "Your Circle completed the week"))
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(circle.name).font(.title3).foregroundStyle(.secondary)
                Button(String(localized: "circle.celebration.continue", defaultValue: "Keep it going"), action: onDismiss)
                    .buttonStyle(.borderedProminent)
                    .tint(OutboundPalette.companion)
                    .frame(minHeight: 44)
            }
            .padding(32)
        }
    }
}

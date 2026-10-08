import SwiftUI

private func groupMemberCountLabel(_ count: Int) -> String {
    if count == 1 {
        return String(localized: "group.members.count.one", defaultValue: "1 member")
    }
    return String(localized: "group.members.count", defaultValue: "\(count) members")
}

private func groupMemberPriority(_ role: String) -> Int {
    switch role {
    case "owner": 0
    case "admin": 1
    default: 2
    }
}

struct GroupDirectoryDetailView: View {
    @EnvironmentObject private var groupStore: GroupStore
    let groupID: String
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let group = groupStore.groups.first(where: { $0.id == groupID && $0.isDetailedPayload }) {
                GroupDetailView(group: group)
            } else if loadFailed {
                VStack(spacing: OutboundSpacing.standard) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "group.loading.failed.title", defaultValue: "This Group couldn’t load"))
                        .font(.headline)
                    Text(String(localized: "group.loading.failed.detail", defaultValue: "Check your connection, then try again."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button(String(localized: "group.loading.retry", defaultValue: "Try again")) {
                        Task { await loadGroup() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(OutboundSpacing.screen)
            } else {
                ProgressView(String(localized: "group.loading", defaultValue: "Loading Group…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await loadGroup() }
    }

    @MainActor
    private func loadGroup() async {
        loadFailed = false
        loadFailed = !(await groupStore.refreshGroup(id: groupID))
    }
}

struct GroupCompactCard: View {
    let group: GroupDTO
    let isPrimary: Bool
    var displayName: String? = nil

    var body: some View {
        OutboundCard(style: .companion) {
            GroupCompactContent(group: group, isPrimary: isPrimary, displayName: displayName)
        }
    }
}

struct GroupCompactContent: View {
    @Environment(\.outboundTheme) private var theme
    let group: GroupDTO
    let isPrimary: Bool
    var displayName: String? = nil
    var isSingleRow = false
    var showsNavigationIndicator = true

    var body: some View {
        Group {
            if isSingleRow {
                singleRowContent
            } else {
                detailedContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var singleRowContent: some View {
        HStack(spacing: OutboundSpacing.compact) {
            groupIcon
                .foregroundStyle(theme.heroForegroundColor)
                .frame(width: 34, height: 34)
                .background(theme.heroForegroundColor.opacity(0.14), in: Circle())

            HStack(spacing: 4) {
                Text(displayName ?? group.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(verbatim: "(\(group.memberCount))")
                    .fixedSize()
            }
            .font(.headline)
            .foregroundStyle(theme.heroForegroundColor)

            Spacer(minLength: 16)

            unreadNoticeBadge

            if !group.upcomingActivities.isEmpty {
                Image(systemName: "calendar.badge.clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.heroForegroundColor)
                    .accessibilityHidden(true)
            }

            compactProgress
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(displayName ?? group.name), \(groupMemberCountLabel(group.memberCount)), \(statusText)\(group.unreadNoticeCount > 0 ? ", \(String(localized: "group.notices.unread", defaultValue: "Unread"))" : "")"
        )
    }

    private var detailedContent: some View {
        HStack(spacing: OutboundSpacing.standard) {
            groupIcon
                .foregroundStyle(OutboundPalette.companion)
                .frame(width: 44, height: 44)
                .background(OutboundPalette.companion.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(displayName ?? group.name).font(.headline).foregroundStyle(.primary).lineLimit(1)
                    if isPrimary { Image(systemName: "star.fill").font(.caption2).foregroundStyle(OutboundPalette.companion) }
                }
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            unreadNoticeBadge
            if showsNavigationIndicator {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var unreadNoticeBadge: some View {
        if group.unreadNoticeCount > 0 {
            Text(String(localized: "group.notices.unread", defaultValue: "Unread"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(OutboundPalette.companion)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(OutboundPalette.companion.opacity(0.12), in: Capsule())
                .accessibilityLabel(String(localized: "group.notices.unread", defaultValue: "Unread"))
        }
    }

    @ViewBuilder
    private var groupIcon: some View {
        if group.lifecycle == "archived" {
            Image(systemName: "archivebox")
                .font(.title2)
        } else if group.trustPolicy == "community" {
            CommunityGroupMark()
                .frame(width: 22, height: 22)
        } else {
            GroupMark()
                .frame(width: 22, height: 22)
        }
    }

    @ViewBuilder
    private var compactProgress: some View {
        let contributedCount = group.week.contributedCount
        if let targetCount = group.week.targetCount, targetCount > 0 {
            HStack(spacing: 6) {
                ProgressView(
                    value: Double(min(contributedCount, targetCount)),
                    total: Double(targetCount)
                )
                .progressViewStyle(.linear)
                .tint(theme.heroForegroundColor)
                .frame(width: 38)

                Text(verbatim: "\(contributedCount)/\(targetCount)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(theme.heroForegroundColor)
            }
        } else {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.group.fill")
                Text(verbatim: "\(contributedCount)")
                    .monospacedDigit()
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(theme.heroForegroundColor)
        }
    }

    private var statusText: String {
        if group.lifecycle == "archived" { return String(localized: "group.status.archived", defaultValue: "Archived") }
        if group.lifecycle == "awaiting_members" { return String(localized: "group.status.awaiting", defaultValue: "Waiting for someone to join") }
        if let activity = group.upcomingActivities.first {
            return String(
                localized: "group.next_activity_format",
                defaultValue: "Next: \(activity.title) · \(activity.startsAt.formatted(date: .abbreviated, time: .shortened))"
            )
        }
        let personalCount = group.members.first(where: \.isCurrentUser)?.contributedCount ?? 0
        if let themeTitle = GroupThemeCatalog.displayTitle(key: group.week.themeKey, customTitle: group.week.themeTitle) {
            return personalCount > 0
                ? String(localized: "group.today.theme_progress", defaultValue: "\(themeTitle) · You moved \(personalCount) times")
                : themeTitle
        }
        if !group.week.focusConfigured {
            return personalCount > 0
                ? String(localized: "group.today.personal_contribution", defaultValue: "You contributed \(personalCount) this week")
                : String(localized: "group.today.plan_activity", defaultValue: "Plan something active together")
        }
        if group.week.focusMode == "none" {
            return personalCount > 0
                ? String(localized: "group.today.personal_contribution", defaultValue: "You contributed \(personalCount) this week")
                : String(localized: "group.today.no_target", defaultValue: "No numeric goal · Move together")
        }
        if let target = group.week.targetCount {
            return String(localized: "group.today.progress", defaultValue: "You: \(personalCount) · Together: \(group.week.contributedCount) of \(target)")
        }
        return String(localized: "group.theme.choose", defaultValue: "Choose a weekly theme")
    }
}

struct GroupCreateView: View {
    @Environment(\.analyticsManager) private var analyticsManager
    @EnvironmentObject private var groupStore: GroupStore
    @EnvironmentObject private var socialStore: TogetherStore
    @State private var name = ""
    @State private var description = ""
    @State private var city = ""
    @State private var activityInterests: Set<String> = []
    @State private var selectedIDs: Set<String> = []
    @State private var selectedTemplate: String?
    @State private var createdGroup: GroupDTO?
    @State private var isSubmitting = false
    @State private var createIdempotencyKey = UUID().uuidString

    private var connections: [SocialConnectionDTO] { socialStore.connections.filter { $0.status == "accepted" } }
    private var inviteLimit: Int { selectedTemplate == "activities" ? 99 : max(1, groupStore.memberLimit - 1) }

    var body: some View {
        Group {
            if let createdGroup {
                GroupCreatedView(group: createdGroup)
            } else if selectedTemplate == nil {
                templateChooser
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                        creationHero

                        if selectedTemplate == "activities" {
                            communityFields
                        } else {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(String(localized: "group.create.people", defaultValue: "Who helps you keep moving?"))
                                    .font(.headline)
                                Spacer()
                                if !selectedIDs.isEmpty {
                                    Text(String(localized: "group.create.selected", defaultValue: "\(selectedIDs.count) selected"))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(OutboundPalette.companion)
                                }
                            }
                            Text(String(localized: "group.create.people_help", defaultValue: "Choose at least one friend or family member. You can invite more later."))
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
                                                .accessibilityHidden(true)
                                        }
                                        .frame(minHeight: 52)
                                        .contentShape(Rectangle())
                                    }
                                    .accessibilityIdentifier("group.create.connection.\(connection.person.id)")
                                    .accessibilityValue(selectedIDs.contains(connection.person.id)
                                        ? String(localized: "group.connection.selected", defaultValue: "Selected")
                                        : String(localized: "group.connection.unselected", defaultValue: "Not selected"))
                                    .buttonStyle(.plain)
                                    .disabled(!selectedIDs.contains(connection.person.id) && selectedIDs.count >= inviteLimit)
                                    if index < connections.count - 1 { Divider().padding(.leading, 52) }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(localized: "group.create.name", defaultValue: "Name your Group · Optional"))
                                .font(.headline)
                            TextField(String(localized: "group.create.name_placeholder", defaultValue: "Weekend energy, Family movers…"), text: $name)
                                .textInputAutocapitalization(.words)
                                .padding(12)
                                .background(OutboundPalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Text(String(localized: "group.create.name_help", defaultValue: "Leave it blank and Plainstride will suggest a name."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Label(
                            String(localized: "group.create.closeness", defaultValue: "Made for the family and friends who know you best."),
                            systemImage: "heart.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        }
                    }
                    .padding(OutboundSpacing.screen)
                }
                .background(OutboundPalette.background)
                .safeAreaInset(edge: .bottom) {
                    Button { Task { await create() } } label: {
                        HStack {
                            Spacer()
                            if isSubmitting { ProgressView() } else { Text(String(localized: "group.create.action", defaultValue: "Create your Group")).fontWeight(.semibold) }
                            Spacer()
                        }
                        .frame(minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(OutboundPalette.companion)
                    .disabled(isSubmitting || (selectedTemplate == "motivation" && selectedIDs.isEmpty) || (selectedTemplate == "activities" && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                    .padding(.horizontal, OutboundSpacing.screen)
                    .padding(.vertical, 10)
                    .background(.bar)
                }
                .navigationTitle(String(localized: "group.create.navigation", defaultValue: "Create your Group"))
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .task {
            await analyticsManager?.track(.init(.groupCreationStarted, properties: [.entrySource: .string("social")]))
            if socialStore.connections.isEmpty { await socialStore.refreshConnections() }
            await socialStore.loadRemainingConnections()
        }
    }

    private var templateChooser: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                Text(String(localized: "social.groups.create.choose_title", defaultValue: "What kind of group are you creating?"))
                    .font(.largeTitle.bold())
                Text(String(localized: "social.groups.create.choose_detail", defaultValue: "Choose who can join. You can adjust other settings later."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                templateCard(
                    title: String(localized: "social.groups.template.private.title", defaultValue: "Private circle · Invite only"),
                    detail: String(localized: "social.groups.template.private.detail", defaultValue: "Share progress and encourage people you trust."),
                    template: "motivation"
                )
                templateCard(
                    title: String(localized: "social.groups.template.community.title", defaultValue: "Open community · Anyone can join"),
                    detail: String(localized: "social.groups.template.community.detail", defaultValue: "Bring people together to share updates and organize activities."),
                    template: "activities"
                )
            }
            .padding(OutboundSpacing.screen)
        }
        .background(OutboundPalette.background)
        .navigationTitle(String(localized: "group.create.navigation", defaultValue: "Create Group"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func templateCard(title: String, detail: String, template: String) -> some View {
        Button { selectTemplate(template) } label: {
            OutboundCard(style: .companion) {
                HStack(spacing: 14) {
                    groupTypeMark(template: template).foregroundStyle(OutboundPalette.companion).frame(width: 24, height: 24).frame(width: 44, height: 44).background(OutboundPalette.companion.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.headline).foregroundStyle(.primary)
                        Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("group.create.template.\(template)")
    }

    private var communityFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "group.create.community.required", defaultValue: "Name your community" )).font(.headline)
            TextField(String(localized: "group.create.community.name_placeholder", defaultValue: "Saturday hikers"), text: $name)
                .textInputAutocapitalization(.words)
                .padding(12)
                .background(OutboundPalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            TextField(String(localized: "group.create.community.description_placeholder", defaultValue: "What should people know?"), text: $description, axis: .vertical)
                .lineLimit(3...6)
                .padding(12)
                .background(OutboundPalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            TextField(String(localized: "group.create.community.city_placeholder", defaultValue: "City (optional)"), text: $city)
                .padding(12)
                .background(OutboundPalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(String(localized: "group.create.community.interests", defaultValue: "Activity interests" )).font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                ForEach(["running", "walking", "hiking", "cycling", "swimming", "strength", "mixed"], id: \.self) { interest in
                    Button { if activityInterests.contains(interest) { activityInterests.remove(interest) } else { activityInterests.insert(interest) } } label: {
                        Text(interest.capitalized).frame(maxWidth: .infinity, minHeight: 40)
                    }.buttonStyle(.bordered).tint(activityInterests.contains(interest) ? OutboundPalette.companion : .secondary)
                }
            }
            Text(String(localized: "social.groups.create.community.access", defaultValue: "Anyone can find and join this community. Members’ workouts stay private."))
                .font(.caption).foregroundStyle(.secondary)
            connectionPicker(title: String(localized: "group.create.community.invite", defaultValue: "Invite people now (optional)"))
        }
    }

    private func connectionPicker(title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ForEach(connections) { connection in
                Button { toggle(connection.person.id) } label: {
                    HStack { SocialAvatar(name: connection.person.displayName, avatarURL: connection.person.avatarUrl); Text(connection.person.displayName).foregroundStyle(.primary); Spacer(); Image(systemName: selectedIDs.contains(connection.person.id) ? "checkmark.circle.fill" : "circle") }
                        .frame(minHeight: 44)
                }.buttonStyle(.plain)
            }
        }
    }

    private var creationHero: some View {
        OutboundCard(style: .companion) {
            VStack(alignment: .leading, spacing: 14) {
                groupTypeMark(template: selectedTemplate ?? "motivation").foregroundStyle(OutboundPalette.companion).frame(width: 28, height: 28).frame(width: 52, height: 52).background(OutboundPalette.companion.opacity(0.12), in: Circle())
                Text(selectedTemplate == "activities"
                    ? String(localized: "social.groups.create.community.hero_title", defaultValue: "Bring your community together.")
                    : String(localized: "social.groups.create.private.hero_title", defaultValue: "Active. Positive. Together."))
                    .font(.title2.bold())
                Text(selectedTemplate == "activities"
                    ? String(localized: "social.groups.create.community.hero_detail", defaultValue: "Create a welcoming place to share updates and plan activities.")
                    : String(localized: "social.groups.create.private.hero_detail", defaultValue: "Share goals and progress with the people closest to you—and cheer each other on."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func groupTypeMark(template: String) -> some View {
        if template == "activities" {
            CommunityGroupMark()
        } else {
            GroupMark()
        }
    }

    private func selectTemplate(_ template: String) {
        selectedTemplate = template
        Task {
            await analyticsManager?.track(.init(.groupTemplateSelected, properties: [.selectionType: .string(template)]))
        }
    }

    private func toggle(_ id: String) { if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) } }

    private func create() async {
        isSubmitting = true
        defer { isSubmitting = false }
        if let created = await groupStore.create(template: selectedTemplate ?? "motivation", name: name, description: description, city: city, activityInterests: Array(activityInterests), memberUserIDs: Array(selectedIDs), idempotencyKey: createIdempotencyKey) {
            createdGroup = created
            createIdempotencyKey = UUID().uuidString
            await analyticsManager?.track(.init(.groupCreationCompleted, properties: [.entrySource: .string("social"), .participantCountBucket: .string(ProductAnalyticsBucket.count(selectedIDs.count + 1))]))
            if !selectedIDs.isEmpty {
                await analyticsManager?.track(.init(.groupInvitationSent, properties: [.entrySource: .string("creation"), .participantCountBucket: .string(ProductAnalyticsBucket.count(selectedIDs.count)), .result: .string("success")]))
            }
        } else {
            await analyticsManager?.track(.init(.groupCreationFailed, properties: [.entrySource: .string("social"), .errorCategory: .string("api_unavailable")]))
        }
    }
}

private struct GroupCreatedView: View {
    @EnvironmentObject private var groupStore: GroupStore
    @EnvironmentObject private var socialStore: TogetherStore
    let group: GroupDTO
    @State private var showsFocus = false

    private var current: GroupDTO { groupStore.groups.first(where: { $0.id == group.id }) ?? group }
    private var invitedPeople: [GroupPersonDTO] {
        [current.owner] + current.invitations.compactMap(\.recipient)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "heart.group.fill")
                    .font(.system(size: 66))
                    .foregroundStyle(OutboundPalette.companion)
                VStack(spacing: 8) {
                    Text(String(localized: "group.created.title", defaultValue: "A healthier week starts together."))
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                    Text(String(localized: "group.created.detail", defaultValue: "Your invitations are on the way. When someone joins, activities can begin building shared momentum."))
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
                if current.trustPolicy == "community" {
                    Text(String(localized: "group.created.community_detail", defaultValue: "This community Group keeps member workouts private. Share updates and plan activities together."))
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    VStack(spacing: 10) {
                        NavigationLink {
                            CreateActivityEventView(sourceGroupID: current.id) {
                                Task { await groupStore.refreshGroup(id: current.id) }
                            }
                            .environmentObject(socialStore)
                        } label: {
                            Text(String(localized: "group.created.plan_activity", defaultValue: "Plan an activity")).frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(.borderedProminent).tint(OutboundPalette.companion)
                        NavigationLink { GroupDetailView(group: current) } label: {
                            Text(String(localized: "group.created.post_update", defaultValue: "Post an update")).frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(.bordered)
                        NavigationLink { GroupDetailView(group: current) } label: {
                            Text(String(localized: "group.created.invite_people", defaultValue: "Invite people")).frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(.bordered)
                    }
                } else {
                    VStack(spacing: 0) {
                        createdBenefit(icon: "figure.mixed.cardio", text: String(localized: "group.created.benefit_activity", defaultValue: "Walking, running, riding, hiking, and swimming all count."))
                        Divider().padding(.leading, 48)
                        createdBenefit(icon: "heart.fill", text: String(localized: "group.created.benefit_cheer", defaultValue: "Notice the effort and send a Cheer."))
                        Divider().padding(.leading, 48)
                        createdBenefit(icon: "chart.xyaxis.line", text: String(localized: "group.created.benefit_details", defaultValue: "See the workout behind the progress and celebrate it together."))
                    }
                    .padding(.horizontal, 14)
                    .background(OutboundPalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    VStack(spacing: 10) {
                        Button(String(localized: "group.created.choose_focus", defaultValue: "Choose a weekly theme")) { showsFocus = true }
                            .buttonStyle(.borderedProminent).tint(OutboundPalette.companion).frame(maxWidth: .infinity, minHeight: 50)
                        NavigationLink { GroupDetailView(group: current) } label: { Text(String(localized: "group.created.open", defaultValue: "Open Group")).frame(maxWidth: .infinity, minHeight: 44) }.buttonStyle(.bordered)
                        Text(String(localized: "group.created.focus_optional", defaultValue: "A numeric goal is optional. You can simply encourage each other."))
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }
            }
            .padding(OutboundSpacing.screen)
        }
        .background(OutboundPalette.background)
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsFocus) { NavigationStack { GroupFocusEditor(group: current) } }
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

struct GroupDetailView: View {
    @Environment(\.analyticsManager) private var analyticsManager
    @EnvironmentObject private var groupStore: GroupStore
    @EnvironmentObject private var socialStore: TogetherStore
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    let group: GroupDTO
    @State private var showsPlanActivity = false
    @State private var showsFocus = false
    @State private var showsNoticeComposer = false
    @State private var showsInvite = false
    @State private var showsMembers = false
    @State private var showsMemberInvite = false
    @State private var memberPendingRemoval: GroupMemberDTO?

    private var current: GroupDTO { groupStore.groups.first(where: { $0.id == group.id }) ?? group }
    private var orderedMembers: [GroupMemberDTO] {
        current.members.enumerated().sorted {
            let leftPriority = groupMemberPriority($0.element.role)
            let rightPriority = groupMemberPriority($1.element.role)
            return leftPriority == rightPriority ? $0.offset < $1.offset : leftPriority < rightPriority
        }.map(\.element)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                header
                if current.trustPolicy == "community" {
                    communityOverview
                } else {
                    if !current.upcomingActivities.isEmpty { upcomingActivitiesSection }
                    focusCard
                    membersSection
                    if !current.invitations.isEmpty { pendingInvitationsSection }
                    if canInviteMembers { inviteMembersButton }
                    planActivityButton
                    if !current.recentMoments.isEmpty { momentsSection }
                    if let history = current.history, !history.isEmpty { historySection(history) }
                }
            }
            .padding(OutboundSpacing.screen)
        }
        .background(OutboundPalette.background)
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if current.role == "owner" || current.role == "admin" {
                NavigationLink { GroupManagementView(group: current) } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel(String(localized: "group.management", defaultValue: "Group settings"))
            }
        }
        .sheet(isPresented: $showsPlanActivity, onDismiss: refreshAfterPlanning) {
            CreateActivityEventView(
                sourceGroupID: current.id
            ) {
                track(.groupPlanActivityCompleted, [.participantCountBucket: .string(ProductAnalyticsBucket.count(current.memberCount)), .result: .string("success")])
            }
            .environmentObject(socialStore)
        }
        .sheet(isPresented: $showsFocus) { NavigationStack { GroupFocusEditor(group: current) } }
        .sheet(isPresented: $showsNoticeComposer) { CommunityNoticeComposer(group: current) }
        .sheet(isPresented: $showsMembers) { fullMembersSheet }
        .task {
            await groupStore.refreshGroup(id: current.id)
            if current.trustPolicy == "community", current.unreadNoticeCount > 0 {
                _ = await groupStore.markNoticesRead(in: current)
            }
            track(.groupProgressOpened, [.entrySource: .string("group_detail"), .selectionType: .string(current.week.focusMode), .participantCountBucket: .string(ProductAnalyticsBucket.count(current.memberCount))])
        }
    }

    private var upcomingActivitiesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "group.up_next", defaultValue: "UP NEXT"))
                .socialSectionLabel()

            ForEach(current.upcomingActivities) { activity in
                NavigationLink {
                    ActivityEventDetailView(
                        run: activity.activityEvent,
                        entrySource: "group_up_next"
                    )
                } label: {
                    OutboundCard(style: .companion) {
                        HStack(spacing: OutboundSpacing.standard) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.title2)
                                .foregroundStyle(OutboundPalette.companion)
                                .frame(width: 42, height: 42)
                                .background(OutboundPalette.companion.opacity(0.12), in: Circle())

                            VStack(alignment: .leading, spacing: 4) {
                                Text(activity.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(upcomingActivitySummary(activity))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var planActivityButton: some View {
        Button { showsPlanActivity = true; track(.groupPlanActivityStarted, [.entrySource: .string("group_detail"), .participantCountBucket: .string(ProductAnalyticsBucket.count(current.memberCount))]) } label: {
            Label(String(localized: "group.plan_activity", defaultValue: "Plan an activity"), systemImage: "calendar.badge.plus")
                .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(OutboundPalette.companion)
    }

    private var canInviteMembers: Bool {
        (current.role == "owner" || current.role == "admin") && current.lifecycle != "archived"
    }

    private var inviteMembersButton: some View {
        Button { showsInvite = true } label: {
            Label(String(localized: "group.invite.more", defaultValue: "Invite connections"), systemImage: "person.badge.plus")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("group.invite.members")
        .disabled(current.memberCount + current.invitations.count >= current.memberLimit)
        .sheet(isPresented: $showsInvite) {
            GroupInviteView(group: current, entrySource: "group_detail")
        }
    }

    private var communityOverview: some View {
        VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
            if current.role == nil,
               !current.members.contains(where: \.isCurrentUser),
               current.joinPolicy != "invite_only" {
                Button {
                    Task {
                        let joining = current.joinPolicy == "open"
                        let succeeded = await groupStore.requestMembership(in: current)
                        track(.groupMembershipChanged, [
                            .entrySource: .string("group_detail"),
                            .selectionType: .string(joining ? "join" : "request"),
                            .result: .string(succeeded ? "success" : "failure"),
                            .participantCountBucket: .string(ProductAnalyticsBucket.count(current.memberCount)),
                        ])
                    }
                } label: {
                    let isPending = current.joinPolicy == "request" && current.pendingRequest?.status == "pending"
                    let title = isPending
                        ? String(localized: "group.join.pending", defaultValue: "Request pending")
                        : current.joinPolicy == "open"
                            ? String(localized: "group.join.open", defaultValue: "Join Group")
                            : String(localized: "group.join.request", defaultValue: "Request to join")
                    Label(title, systemImage: "person.badge.plus")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(current.joinPolicy == "request" && current.pendingRequest?.status == "pending")
            }
            if let description = current.description, !description.isEmpty {
                OutboundCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "group.about", defaultValue: "About")).font(.headline)
                        Text(description).font(.subheadline).foregroundStyle(.secondary)
                        Text(String(localized: "group.join_policy", defaultValue: current.joinPolicy == "request" ? "Request to join" : current.joinPolicy == "open" ? "Anyone can join" : "Invitation only"))
                            .font(.caption.weight(.semibold)).foregroundStyle(OutboundPalette.companion)
                    }
                }
            }
            if !current.notices.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(String(localized: "group.notices", defaultValue: "NOTICES")).socialSectionLabel()
                        Spacer()
                        if current.unreadNoticeCount > 0 { Text(String(localized: "group.notices.unread", defaultValue: "Unread")).font(.caption.weight(.semibold)).foregroundStyle(OutboundPalette.companion) }
                    }
                    ForEach(current.notices) { notice in
                        OutboundCard {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack { if notice.pinned { Image(systemName: "pin.fill") }; Text(notice.title ?? String(localized: "group.notice.update", defaultValue: "Group update")).font(.headline); Spacer(); Text(notice.publishedAt, style: .date).font(.caption).foregroundStyle(.secondary) }
                                Text(notice.body).font(.subheadline)
                            }
                        }
                    }
                    if current.unreadNoticeCount > 0,
                       current.role != nil || current.members.contains(where: \.isCurrentUser) {
                        Button(String(localized: "group.notices.mark_read", defaultValue: "Mark notices read")) {
                            Task { _ = await groupStore.markNoticesRead(in: current) }
                        }
                        .font(.caption)
                    }
                }
            }
            if !current.upcomingActivities.isEmpty { upcomingActivitiesSection }
            if current.role != nil || current.members.contains(where: \.isCurrentUser) {
                communityMembersSection
            }
            if current.role == "owner" || current.role == "admin" {
                Button { showsNoticeComposer = true } label: { Label(String(localized: "group.notice.publish", defaultValue: "Post an update"), systemImage: "megaphone") }
                    .buttonStyle(.bordered)
            }
            if canInviteMembers { inviteMembersButton }
            planActivityButton
        }
    }

    private var communityMembersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "group.members", defaultValue: "MEMBERS")).socialSectionLabel()
            memberSummaryCard
        }
    }

    private var memberSummaryCard: some View {
        OutboundCard {
            HStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(orderedMembers.prefix(3)) { member in
                            HStack(spacing: 6) {
                                SocialAvatar(name: member.user.displayName, avatarURL: member.user.avatarUrl, size: 30)
                                Text(firstName(member.user.displayName))
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                Button(action: showAllMembers) {
                    Text(String(localized: "group.members.more_action", defaultValue: "More"))
                        .font(.subheadline.weight(.semibold))
                }
                .fixedSize()
            }
            .frame(minHeight: 40)
        }
    }

    private var fullMembersSheet: some View {
        NavigationStack {
            List {
                ForEach(orderedMembers) { member in
                    HStack(alignment: .top, spacing: 12) {
                        SocialAvatar(name: member.user.displayName, avatarURL: member.user.avatarUrl)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(member.user.displayName).font(.headline)
                                Spacer(minLength: 8)
                                if member.role != "member" {
                                    Text(member.role.capitalized).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if current.trustPolicy == "community" {
                                Text(member.role.capitalized).font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text(memberStatus(member)).font(.caption).foregroundStyle(.secondary)
                                if let activity = member.recentActivity {
                                    Text("\(activityTitle(activity)) · \(activitySummary(activity))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        if current.trustPolicy != "community", !member.isCurrentUser {
                            memberCheerMenu(member)
                        }
                        if canInviteMembers && canRemove(member) {
                            Menu {
                                Button(String(localized: "group.remove_member", defaultValue: "Remove member"), role: .destructive) {
                                    memberPendingRemoval = member
                                }
                            } label: {
                                Image(systemName: "ellipsis").frame(width: 36, height: 44)
                            }
                            .accessibilityLabel(String(localized: "group.member.actions", defaultValue: "Member actions"))
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(OutboundPalette.background)
                }
            }
            .listStyle(.plain)
            .background(OutboundPalette.background)
            .navigationTitle(String(localized: "group.members.manage", defaultValue: "Members"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if canInviteMembers {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(String(localized: "group.invite.more", defaultValue: "Invite connections")) { showsMemberInvite = true }
                            .disabled(current.memberCount + current.invitations.count >= current.memberLimit)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done", defaultValue: "Done")) { showsMembers = false }
                }
            }
            .sheet(isPresented: $showsMemberInvite) {
                GroupInviteView(group: current, entrySource: "group_members")
                    .environmentObject(groupStore)
                    .environmentObject(socialStore)
            }
            .confirmationDialog(
                String(localized: "group.member.remove_confirm_title", defaultValue: "Remove this member?"),
                isPresented: Binding(get: { memberPendingRemoval != nil }, set: { if !$0 { memberPendingRemoval = nil } }),
                titleVisibility: .visible
            ) {
                Button(String(localized: "group.remove_member", defaultValue: "Remove member"), role: .destructive) {
                    guard let member = memberPendingRemoval else { return }
                    Task {
                        if await groupStore.removeMember(member, from: current) != nil {
                            track(.groupMemberRemoved, [.participantCountBucket: .string(ProductAnalyticsBucket.count(current.memberCount))])
                        }
                        memberPendingRemoval = nil
                    }
                }
                Button(String(localized: "common.cancel", defaultValue: "Cancel"), role: .cancel) { memberPendingRemoval = nil }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func firstName(_ displayName: String) -> String {
        displayName.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? displayName
    }

    private func showAllMembers() {
        showsMembers = true
        track(.groupMembersOpened, [
            .entrySource: .string("group_detail"),
            .participantCountBucket: .string(ProductAnalyticsBucket.count(current.memberCount)),
        ])
    }

    private func canRemove(_ member: GroupMemberDTO) -> Bool {
        guard !member.isCurrentUser, member.role != "owner" else { return false }
        return current.role == "owner" || (current.role == "admin" && member.role == "member")
    }

    private func refreshAfterPlanning() {
        Task {
            await socialStore.refresh()
            await groupStore.refreshGroup(id: current.id)
        }
    }

    private var header: some View {
        OutboundCard(style: .companion) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(current.trustPolicy == "community" ? String(localized: "group.community", defaultValue: "Community Group") : String(localized: "group.private", defaultValue: "Private Group"))
                    if current.featured { Text(String(localized: "group.featured", defaultValue: "Featured")) }
                    if current.organizationVerificationState == "verified" { Text(String(localized: "group.verified", defaultValue: "Verified")) }
                }
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(current.description ?? String(localized: "group.detail.inspiration", defaultValue: "Building a positive life, one activity at a time."))
                    .font(.headline)
                if current.trustPolicy == "community",
                   let city = current.city?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !city.isEmpty {
                    Label(city, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(groupMemberCountLabel(current.memberCount)).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var focusCard: some View {
        OutboundCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(String(localized: "group.weekly_theme", defaultValue: "Weekly Theme")).font(.headline)
                    Spacer()
                    if current.role == "owner" {
                        Button(!current.week.focusConfigured
                            ? String(localized: "group.focus.choose_action", defaultValue: "Choose")
                            : String(localized: "common.edit", defaultValue: "Edit")) {
                            showsFocus = true
                        }
                        .accessibilityIdentifier("group.theme.edit")
                    } else if current.week.focusConfigured && ["theme", "personal_targets"].contains(current.week.focusMode) {
                        Button(current.members.first(where: \.isCurrentUser)?.commitment?.targetCount == nil
                            ? String(localized: "group.commitment.set", defaultValue: "Set my goal")
                            : String(localized: "group.commitment.edit", defaultValue: "Edit my goal")) {
                            showsFocus = true
                        }
                    }
                }
                if !current.week.focusConfigured {
                    Text(current.role == "owner"
                        ? String(localized: "group.theme.unconfigured.owner", defaultValue: "Choose a shared intention for the week.")
                        : String(localized: "group.theme.unconfigured.member", defaultValue: "The Group owner hasn’t chosen this week’s theme yet."))
                        .font(.subheadline).foregroundStyle(.secondary)
                } else if let themeTitle = GroupThemeCatalog.displayTitle(key: current.week.themeKey, customTitle: current.week.themeTitle) {
                    Label(themeTitle, systemImage: GroupThemeCatalog.definition(for: current.week.themeKey)?.systemImage ?? "sparkles")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(OutboundPalette.companion)
                    if let detail = GroupThemeCatalog.displayDetail(key: current.week.themeKey, customNote: current.week.themeNote), !detail.isEmpty {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(String(localized: "group.theme.activity_count", defaultValue: "\(current.week.contributedCount) activities together this week"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let commitment = current.members.first(where: \.isCurrentUser)?.commitment?.targetCount {
                        let contributedCount = current.members.first(where: \.isCurrentUser)?.contributedCount ?? 0
                        Text(commitmentProgress(contributedCount: contributedCount, target: commitment, includesLabel: true))
                            .font(.subheadline.weight(.semibold))
                    }
                } else if current.week.focusMode == "none" {
                    Text(String(localized: "group.focus.none.detail", defaultValue: "No numeric goal this week. Cheer each other on or plan something active."))
                } else if let target = current.week.targetCount {
                    ProgressView(value: min(Double(current.week.contributedCount) / Double(max(target, 1)), 1)).tint(OutboundPalette.companion)
                    Text(String(localized: "group.progress.format", defaultValue: "\(current.week.contributedCount) of \(target) activities this week")).font(.subheadline).foregroundStyle(.secondary)
                }
                nextWeekThemePreview
            }
        }
    }

    @ViewBuilder
    private var nextWeekThemePreview: some View {
        let focus = current.upcomingFocus
        let differsFromCurrent = focus.themeKey != current.week.themeKey || focus.themeTitle != current.week.themeTitle || focus.themeNote != current.week.themeNote
        if focus.focusConfigured, differsFromCurrent,
           let title = GroupThemeCatalog.displayTitle(key: focus.themeKey, customTitle: focus.themeTitle) {
            Divider()
            VStack(alignment: .leading, spacing: 5) {
                Text(String(localized: "group.theme.next_week", defaultValue: "Next week"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Label(title, systemImage: GroupThemeCatalog.definition(for: focus.themeKey)?.systemImage ?? "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OutboundPalette.companion)
                if let detail = GroupThemeCatalog.displayDetail(key: focus.themeKey, customNote: focus.themeNote), !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "group.members", defaultValue: "MEMBERS")).socialSectionLabel()
            memberSummaryCard
        }
    }

    private func memberCheerMenu(_ member: GroupMemberDTO) -> some View {
        Menu {
            ForEach(["encouragement", "celebration", "support"], id: \.self) { preset in
                if let existing = existingCheer(to: member, preset: preset) {
                    Button(String(format: String(localized: "group.cheer.remove_format", defaultValue: "Remove %@"), cheerTitle(preset)), role: .destructive) {
                        Task {
                            if await groupStore.removeCheer(existing, from: current) != nil {
                                track(.groupCheerRemoved, [.selectionType: .string(preset)])
                            }
                        }
                    }
                } else {
                    Button(cheerTitle(preset)) {
                        Task {
                            if await groupStore.sendCheer(group: current, member: member, presetType: preset) {
                                track(.groupCheerSent, [.selectionType: .string(preset)])
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "heart").frame(width: 44, height: 44)
        }
        .accessibilityLabel(String(localized: "group.cheer", defaultValue: "Send a Cheer"))
    }

    private var pendingInvitationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "group.invitations.pending", defaultValue: "Pending invitations"))
                .socialSectionLabel()
            ForEach(current.invitations) { invitation in
                OutboundCard {
                    HStack(spacing: 12) {
                        if let recipient = invitation.recipient {
                            SocialAvatar(name: recipient.displayName, avatarURL: recipient.avatarUrl)
                            Text(recipient.displayName).font(.headline)
                        } else {
                            Image(systemName: "person.crop.circle.badge.clock")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text(String(localized: "group.invitation.pending_person", defaultValue: "Invited person"))
                                .font(.headline)
                        }
                        Spacer()
                        Text(String(localized: "group.invitation.status.pending", defaultValue: "Invited"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 44)
                }
            }
        }
    }

    private var momentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "group.moments", defaultValue: "RECENT MOMENTS")).socialSectionLabel()
            OutboundCard { ForEach(current.recentMoments) { moment in HStack { Image(systemName: moment.type == "cheer" ? "heart.fill" : moment.type == "completed_activity" ? "checkmark.group.fill" : "sparkles").foregroundStyle(OutboundPalette.companion); Text(momentText(moment)).font(.subheadline); Spacer(); Text(moment.createdAt, style: .relative).font(.caption).foregroundStyle(.secondary) }.frame(minHeight: 44) } }
        }
    }

    private func upcomingActivitySummary(_ activity: GroupActivityEventDTO) -> String {
        var parts = [activity.startsAt.formatted(date: .abbreviated, time: .shortened)]
        if let locationName = activity.locationName, !locationName.isEmpty {
            parts.append(locationName)
        }
        parts.append(String(localized: "group.activity.going_count", defaultValue: "\(activity.attendeeCount) going"))
        return parts.joined(separator: " · ")
    }

    private func historySection(_ history: [GroupWeekHistoryDTO]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "group.history", defaultValue: "HISTORY")).socialSectionLabel()
            OutboundCard {
                ForEach(history.prefix(6)) { week in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(week.startsAt.formatted(date: .abbreviated, time: .omitted))
                            if let title = GroupThemeCatalog.displayTitle(key: week.themeKey, customTitle: week.themeTitle) {
                                Text(title).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(week.state == "completed" ? String(localized: "group.completed", defaultValue: "Completed") : String(localized: "group.week.recorded", defaultValue: "Week recorded")).foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 44)
                }
            }
        }
    }

    private func memberStatus(_ member: GroupMemberDTO) -> String {
        if member.commitment?.skipped == true { return String(localized: "group.commitment.skipping", defaultValue: "Skipping this week") }
        if let target = member.commitment?.targetCount {
            return commitmentProgress(contributedCount: member.contributedCount, target: target, includesLabel: false)
        }
        return String(localized: "group.member.contributed", defaultValue: "Contributed \(member.contributedCount)")
    }
    private func commitmentProgress(contributedCount: Int, target: Int, includesLabel: Bool) -> String {
        let completedCount = min(contributedCount, target)
        let extraCount = max(0, contributedCount - target)
        if extraCount > 0 {
            return includesLabel
                ? String(localized: "group.commitment.progress.extra", defaultValue: "Your commitment: \(completedCount) of \(target) · \(extraCount) extra")
                : String(localized: "group.member.progress.extra", defaultValue: "\(completedCount) of \(target) · \(extraCount) extra")
        }
        return includesLabel
            ? String(localized: "group.commitment.progress", defaultValue: "Your commitment: \(completedCount) of \(target)")
            : String(localized: "group.member.progress", defaultValue: "\(completedCount) of \(target)")
    }
    private func activityTypeTitle(_ type: String) -> String {
        switch type {
        case "cycling": return String(localized: "group.activity.ride", defaultValue: "Ride")
        case "hiking": return String(localized: "group.activity.hike", defaultValue: "Hike")
        case "walking": return String(localized: "group.activity.walk", defaultValue: "Walk")
        case "swimming": return String(localized: "group.activity.swim", defaultValue: "Swim")
        default: return String(localized: "group.activity.run", defaultValue: "Run")
        }
    }
    private func activityTitle(_ activity: GroupActivitySummaryDTO) -> String {
        let title = activity.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? activityTypeTitle(activity.type) : title
    }
    private func activitySummary(_ activity: GroupActivitySummaryDTO) -> String {
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
                ? String(localized: "group.activity.duration.hours_minutes", defaultValue: "\(hours) hr \(minutes) min")
                : String(localized: "group.activity.duration.minutes", defaultValue: "\(minutes) min"))
        }
        if let pace = activity.avgPace, pace > 0 {
            parts.append(pace.paceString(for: measurementPreferences.unitSystem))
        }
        if let heartRate = activity.avgHeartRate, heartRate > 0 {
            parts.append(String(localized: "group.activity.heart_rate", defaultValue: "\(heartRate) bpm"))
        }
        if let calories = activity.energyKilocalories, calories > 0 {
            parts.append(String(localized: "group.activity.calories", defaultValue: "\(calories) cal"))
        }
        return parts.joined(separator: " · ")
    }
    private func cheerTitle(_ preset: String) -> String {
        switch preset {
        case "celebration": return String(localized: "group.cheer.celebration", defaultValue: "Celebrate")
        case "support": return String(localized: "group.cheer.support", defaultValue: "Support")
        default: return String(localized: "group.cheer.encouragement", defaultValue: "Keep going")
        }
    }
    private func existingCheer(to member: GroupMemberDTO, preset: String) -> GroupCheerDTO? {
        guard let currentUserID = current.members.first(where: \.isCurrentUser)?.user.id else { return nil }
        return current.cheers.first { $0.senderUserId == currentUserID && $0.recipientUserId == member.user.id && $0.presetType == preset }
    }

    private func momentText(_ moment: GroupMomentDTO) -> String {
        switch moment.type {
        case "completed_activity": return moment.title ?? String(localized: "group.moment.activity_completed", defaultValue: "Activity completed")
        case "weekly_completion": return String(localized: "group.moment.completed", defaultValue: "Weekly theme completed")
        default: return String(localized: "group.moment.cheer", defaultValue: "A Cheer was sent")
        }
    }
    private func track(_ event: ProductEventName, _ properties: [ProductPropertyKey: AnalyticsValue]) { Task { await analyticsManager?.track(.init(event, properties: properties)) } }
}

struct GroupFocusEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.analyticsManager) private var analyticsManager
    @EnvironmentObject private var groupStore: GroupStore
    let group: GroupDTO
    @State private var selectedThemeKey: String
    @State private var customTitle: String
    @State private var customNote: String
    @State private var personalTarget: Int
    @State private var apply = "now"
    @State private var hasCommitment: Bool
    @State private var isSaving = false

    init(group: GroupDTO) {
        self.group = group
        let ownCommitment = group.members.first(where: \.isCurrentUser)?.commitment
        _selectedThemeKey = State(initialValue: group.week.themeKey ?? "")
        _customTitle = State(initialValue: group.week.themeTitle ?? "")
        _customNote = State(initialValue: group.week.themeNote ?? "")
        _personalTarget = State(initialValue: ownCommitment?.targetCount ?? 3)
        _hasCommitment = State(initialValue: ownCommitment?.targetCount != nil && ownCommitment?.skipped != true)
    }

    private var current: GroupDTO { groupStore.groups.first(where: { $0.id == group.id }) ?? group }
    private var recommendations: [GroupThemeDefinition] { GroupThemeCatalog.recommendations(for: current) }
    private var recommendationIDs: Set<String> { Set(recommendations.map(\.id)) }

    var body: some View {
        Form {
            if group.role == "owner" {
                Section(String(localized: "group.theme.recommended", defaultValue: "Recommended for your Group")) {
                    ForEach(recommendations) { theme in
                        themeButton(theme)
                    }
                }
                Section(String(localized: "group.theme.browse", defaultValue: "More themes")) {
                    ForEach(GroupThemeCatalog.all.filter { !recommendationIDs.contains($0.id) }) { theme in
                        themeButton(theme)
                    }
                    Button {
                        selectedThemeKey = "custom"
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "pencil.line")
                                .frame(width: 28)
                                .foregroundStyle(OutboundPalette.companion)
                            Text(String(localized: "group.theme.custom.action", defaultValue: "Write your own"))
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedThemeKey == "custom" {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(OutboundPalette.companion)
                            }
                        }
                        .frame(minHeight: 44)
                    }
                }
                if selectedThemeKey == "custom" {
                    Section(String(localized: "group.theme.custom.section", defaultValue: "Custom theme")) {
                        TextField(String(localized: "group.theme.custom.title", defaultValue: "Theme title"), text: $customTitle)
                            .onChange(of: customTitle) { _, value in customTitle = String(value.prefix(50)) }
                        TextField(String(localized: "group.theme.custom.note", defaultValue: "Supporting note · Optional"), text: $customNote, axis: .vertical)
                            .lineLimit(2...4)
                            .onChange(of: customNote) { _, value in customNote = String(value.prefix(120)) }
                        if customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(String(localized: "group.theme.custom.required", defaultValue: "Add a short title before closing."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section { Picker(String(localized: "group.focus.apply", defaultValue: "Apply"), selection: $apply) { Text(String(localized: "group.apply.now", defaultValue: "Now")).tag("now"); Text(String(localized: "group.apply.next", defaultValue: "Next week")).tag("next_week") } }
            }
            if canEditCommitment {
                Section(String(localized: "group.commitment.mine", defaultValue: "My commitment")) {
                    Toggle(String(localized: "group.commitment.enable", defaultValue: "Set a personal commitment"), isOn: $hasCommitment)
                    if hasCommitment {
                        targetPresets(selection: $personalTarget)
                        Stepper(String(localized: "group.commitment.count", defaultValue: "\(personalTarget) activities"), value: $personalTarget, in: 1...100)
                    }
                    Text(String(localized: "group.commitment.optional", defaultValue: "This is optional and belongs only to you."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(group.role == "owner"
            ? String(localized: "group.weekly_theme", defaultValue: "Weekly Theme")
            : String(localized: "group.commitment.mine", defaultValue: "My commitment"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "group.focus.save", defaultValue: "Save")) {
                    Task { if await saveDraftIfNeeded() { dismiss() } }
                }
                .disabled(isSaving)
                .accessibilityIdentifier("group.focus.save")
            }
        }
        .interactiveDismissDisabled(hasUnsavedChanges || isSaving)
    }

    private func themeButton(_ theme: GroupThemeDefinition) -> some View {
        Button {
            selectedThemeKey = theme.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: theme.systemImage)
                    .frame(width: 28)
                    .foregroundStyle(OutboundPalette.companion)
                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(theme.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if selectedThemeKey == theme.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(OutboundPalette.companion)
                }
            }
            .frame(minHeight: 52)
        }
        .accessibilityIdentifier("group.theme.option.\(theme.id)")
    }

    private func targetPresets(selection: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "group.focus.suggestions", defaultValue: "Suggestions"))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                ForEach([2, 3, 4, 5], id: \.self) { value in
                    Button("\(value)") { selection.wrappedValue = value }
                        .buttonStyle(.bordered)
                        .tint(selection.wrappedValue == value ? OutboundPalette.companion : .secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel(String(localized: "group.focus.preset_accessibility", defaultValue: "\(value) activities"))
                }
            }
        }
    }

    private var canEditCommitment: Bool {
        if group.role == "owner", apply == "now", !selectedThemeKey.isEmpty { return true }
        return current.week.focusConfigured && ["theme", "personal_targets"].contains(current.week.focusMode)
    }

    private var hasUnsavedChanges: Bool {
        let originalCommitment = group.members.first(where: \.isCurrentUser)?.commitment
        let originalHasCommitment = originalCommitment?.targetCount != nil && originalCommitment?.skipped != true
        let normalizedTitle = selectedThemeKey == "custom" ? customTitle.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let trimmedNote = customNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNote = selectedThemeKey == "custom" && !trimmedNote.isEmpty ? trimmedNote : nil
        let validTheme = !selectedThemeKey.isEmpty && (selectedThemeKey != "custom" || !(normalizedTitle ?? "").isEmpty)
        let focusChanged = group.role == "owner" && validTheme && (
            selectedThemeKey != group.week.themeKey ||
            normalizedTitle != group.week.themeTitle ||
            normalizedNote != group.week.themeNote ||
            apply != "now"
        )
        let supportsCommitment = group.role == "owner" && apply == "now" && validTheme
            ? true
            : current.week.focusConfigured && ["theme", "personal_targets"].contains(current.week.focusMode)
        let commitmentChanged = supportsCommitment && (
            hasCommitment != originalHasCommitment ||
            (hasCommitment && personalTarget != originalCommitment?.targetCount)
        )
        return focusChanged || commitmentChanged
    }

    @MainActor
    private func saveDraftIfNeeded() async -> Bool {
        let draftThemeKey = selectedThemeKey
        let draftCustomTitle = customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let draftCustomNote = customNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let draftPersonalTarget = personalTarget
        let draftApply = apply
        let draftHasCommitment = hasCommitment
        let originalCommitment = group.members.first(where: \.isCurrentUser)?.commitment
        let originalHasCommitment = originalCommitment?.targetCount != nil && originalCommitment?.skipped != true
        let normalizedTitle = draftThemeKey == "custom" ? draftCustomTitle : nil
        let normalizedNote = draftThemeKey == "custom" && !draftCustomNote.isEmpty ? draftCustomNote : nil
        let hasValidThemeDraft = !draftThemeKey.isEmpty && (draftThemeKey != "custom" || !draftCustomTitle.isEmpty)
        let focusChanged = group.role == "owner" && hasValidThemeDraft && (
            draftThemeKey != group.week.themeKey ||
            normalizedTitle != group.week.themeTitle ||
            normalizedNote != group.week.themeNote ||
            draftApply != "now"
        )
        let intendedCurrentSupportsCommitment = group.role == "owner" && draftApply == "now" && hasValidThemeDraft
            ? true
            : current.week.focusConfigured && ["theme", "personal_targets"].contains(current.week.focusMode)
        let commitmentChanged = intendedCurrentSupportsCommitment && (
            draftHasCommitment != originalHasCommitment ||
            (draftHasCommitment && draftPersonalTarget != originalCommitment?.targetCount)
        )
        guard focusChanged || commitmentChanged else { return true }
        guard !isSaving else { return false }
        if draftThemeKey == "custom", draftCustomTitle.isEmpty { return false }

        let groupSnapshot = current
        isSaving = true
        defer { isSaving = false }
        if focusChanged {
            guard await groupStore.updateFocus(group: groupSnapshot, themeKey: draftThemeKey, customTitle: normalizedTitle, customNote: normalizedNote, apply: draftApply) != nil else { return false }
            await analyticsManager?.track(.init(.groupThemeChanged, properties: [.selectionType: .string(draftThemeKey == "custom" ? "custom" : "curated"), .sourceType: .string(draftApply)]))
        }
        guard commitmentChanged else { return true }
        guard await groupStore.updateCommitment(group: groupSnapshot, targetCount: draftHasCommitment ? draftPersonalTarget : nil, skipped: false, clear: !draftHasCommitment) != nil else { return false }
        await analyticsManager?.track(.init(.groupTargetChanged, properties: [.selectionType: .string(draftHasCommitment ? "target" : "cleared"), .targetBucket: .string(ProductAnalyticsBucket.count(draftPersonalTarget)), .sourceType: .string("now")]))
        return true
    }
}

private struct CommunityNoticeComposer: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var groupStore: GroupStore
    let group: GroupDTO
    @State private var title = ""
    @State private var noticeBody = ""
    @State private var pinned = false

    var form: some View {
        Form {
            TextField(String(localized: "group.notice.title", defaultValue: "Title (optional)"), text: $title)
            TextField(String(localized: "group.notice.body", defaultValue: "Write an update"), text: $noticeBody, axis: .vertical)
                .lineLimit(5...10)
            Toggle(String(localized: "group.notice.pin", defaultValue: "Pin this notice"), isOn: $pinned)
        }
    }

    var bodyView: some View {
        NavigationStack {
            form
                .navigationTitle(String(localized: "group.notice.publish", defaultValue: "Post an update"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(String(localized: "common.cancel", defaultValue: "Cancel")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "common.publish", defaultValue: "Publish")) {
                            Task {
                                guard !noticeBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                                if await groupStore.publishNotice(group: group, title: title, body: noticeBody, pinned: pinned) != nil { dismiss() }
                            }
                        }
                        .disabled(noticeBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
    }

    var body: some View { bodyView }
}

struct GroupManagementView: View {
    @Environment(\.analyticsManager) private var analyticsManager
    @EnvironmentObject private var groupStore: GroupStore
    @EnvironmentObject private var socialStore: TogetherStore
    @Environment(\.dismiss) private var dismiss
    let group: GroupDTO
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
    @State private var isSaving = false

    init(group: GroupDTO) {
        self.group = group
        _name = State(initialValue: group.name)
        _resetWeekday = State(initialValue: group.resetWeekday)
        _timeZone = State(initialValue: group.timeZone)
        _notificationMuted = State(initialValue: group.currentUserMuted)
        _savedName = State(initialValue: group.name)
        _savedResetWeekday = State(initialValue: group.resetWeekday)
        _savedTimeZone = State(initialValue: group.timeZone)
        _savedNotificationMuted = State(initialValue: group.currentUserMuted)
    }
    private var current: GroupDTO { groupStore.groups.first(where: { $0.id == group.id }) ?? group }

    var body: some View {
        Form {
            Section {
                if current.role == "owner" {
                    NavigationLink(String(localized: "group.weekly_theme", defaultValue: "Weekly Theme")) { GroupFocusEditor(group: current) }
                } else if current.week.focusConfigured && ["theme", "personal_targets"].contains(current.week.focusMode) {
                    NavigationLink(String(localized: "group.commitment.mine", defaultValue: "My commitment")) { GroupFocusEditor(group: current) }
                }
                Toggle(String(localized: "group.notifications.mute", defaultValue: "Mute optional notifications"), isOn: $notificationMuted)
            }

            if current.role == "owner" || current.role == "admin" {
                Section(String(localized: "group.management.owner", defaultValue: "Owner controls")) { TextField(String(localized: "group.create.name", defaultValue: "Name"), text: $name); if current.lifecycle != "archived" { Button(String(localized: "group.invite.more", defaultValue: "Invite connections")) { showsInvite = true } } }
                if !current.invitations.isEmpty {
                    Section(String(localized: "group.invitations.pending", defaultValue: "Pending invitations")) {
                        ForEach(current.invitations) { invitation in
                            HStack {
                                Text(invitation.recipient?.displayName ?? String(localized: "group.invitation.pending_person", defaultValue: "Invited person"))
                                Spacer()
                                Button(String(localized: "group.invitation.cancel", defaultValue: "Cancel"), role: .destructive) {
                                    Task {
                                        if await groupStore.cancel(invitation, in: current) != nil {
                                            track(.groupInvitationCancelled, [.entrySource: .string("group_settings")])
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                Section(String(localized: "group.week.settings", defaultValue: "Group week")) { Picker(String(localized: "group.reset_day", defaultValue: "Reset day"), selection: $resetWeekday) { ForEach(1...7, id: \.self) { Text(isoWeekdayName($0)).tag($0) } }; TextField(String(localized: "group.timezone", defaultValue: "Time zone"), text: $timeZone); Picker(String(localized: "group.focus.apply", defaultValue: "Apply"), selection: $calendarApply) { Text(String(localized: "group.apply.now", defaultValue: "Now")).tag("now"); Text(String(localized: "group.apply.next", defaultValue: "Next week")).tag("next_week") } }
                Section(String(localized: "group.members.manage", defaultValue: "Members")) { ForEach(current.members.filter { !$0.isCurrentUser }) { member in Menu { if current.role == "owner" { Button(member.role == "admin" ? String(localized: "group.role.demote", defaultValue: "Make member") : String(localized: "group.role.promote", defaultValue: "Make admin")) { Task { _ = await groupStore.setRole(member.role == "admin" ? "member" : "admin", for: member, in: current) } }; Button(String(localized: "group.transfer", defaultValue: "Transfer ownership")) { Task { if await groupStore.transferOwnership(of: current, to: member) != nil { track(.groupOwnershipTransferred, [.participantCountBucket: .string(ProductAnalyticsBucket.count(current.memberCount))]) } } } }; Button(String(localized: "group.remove_member", defaultValue: "Remove member"), role: .destructive) { Task { if await groupStore.removeMember(member, from: current) != nil { track(.groupMemberRemoved, [.participantCountBucket: .string(ProductAnalyticsBucket.count(current.memberCount))]) } } } } label: { HStack { Text(member.user.displayName); Spacer(); Image(systemName: "ellipsis").frame(width: 44, height: 44) } } } }
                Section { if current.lifecycle == "archived" { Button(String(localized: "group.reactivate", defaultValue: "Reactivate Group")) { Task { if await groupStore.reactivate(current) != nil { track(.groupReactivated, [.participantCountBucket: .string(ProductAnalyticsBucket.count(current.memberCount))]) } } } } else { Button(String(localized: "group.archive", defaultValue: "Archive Group"), role: .destructive) { Task { if await groupStore.archive(current) { track(.groupArchived, [.participantCountBucket: .string(ProductAnalyticsBucket.count(current.memberCount))]) } } } } }
            } else if current.role == "member" {
                Section { Button(String(localized: "group.leave", defaultValue: "Leave Group"), role: .destructive) { Task { if await groupStore.leave(current) { track(.groupMemberLeft, [.participantCountBucket: .string(ProductAnalyticsBucket.count(current.memberCount))]); dismiss() } } } }
            }
        }
        .navigationTitle(String(localized: "group.management", defaultValue: "Group settings"))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "group.focus.save", defaultValue: "Save")) {
                    Task { await saveDraftIfNeeded() }
                }
                .disabled(isSaving || !hasUnsavedChanges)
            }
        }
        .sheet(isPresented: $showsInvite) { GroupInviteView(group: current) }
        .interactiveDismissDisabled(hasUnsavedChanges || isSaving)
    }

    private var hasUnsavedChanges: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines) != savedName ||
            resetWeekday != savedResetWeekday ||
            timeZone.trimmingCharacters(in: .whitespacesAndNewlines) != savedTimeZone ||
            calendarApply != savedCalendarApply ||
            notificationMuted != savedNotificationMuted
    }

    @MainActor
    private func saveDraftIfNeeded() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTimeZone = timeZone.trimmingCharacters(in: .whitespacesAndNewlines)
        let draftResetWeekday = resetWeekday
        let draftCalendarApply = calendarApply
        let draftNotificationMuted = notificationMuted
        let nameChanged = trimmedName != savedName
        let calendarChanged = draftResetWeekday != savedResetWeekday || trimmedTimeZone != savedTimeZone || draftCalendarApply != savedCalendarApply
        let notificationsChanged = draftNotificationMuted != savedNotificationMuted
        guard nameChanged || calendarChanged || notificationsChanged, !isSaving else { return }

        let groupSnapshot = current
        isSaving = true
        defer { isSaving = false }
        if nameChanged, await groupStore.updateName(group: groupSnapshot, name: trimmedName) != nil {
            savedName = trimmedName
            await analyticsManager?.track(.init(.groupNameChanged))
        }
        if calendarChanged, await groupStore.updateCalendar(group: groupSnapshot, resetWeekday: draftResetWeekday, timeZone: trimmedTimeZone, apply: draftCalendarApply) != nil {
            savedResetWeekday = draftResetWeekday
            savedTimeZone = trimmedTimeZone
            savedCalendarApply = draftCalendarApply
            await analyticsManager?.track(.init(.groupCalendarChanged, properties: [.sourceType: .string(draftCalendarApply)]))
        }
        if notificationsChanged, await groupStore.setMuted(groupSnapshot, muted: draftNotificationMuted) {
            savedNotificationMuted = draftNotificationMuted
            await analyticsManager?.track(.init(.groupNotificationsChanged, properties: [.selectionType: .string(draftNotificationMuted ? "muted" : "unmuted")]))
        }
    }

    private func isoWeekdayName(_ isoWeekday: Int) -> String {
        Calendar.current.weekdaySymbols[isoWeekday % 7]
    }
    private func track(_ event: ProductEventName, _ properties: [ProductPropertyKey: AnalyticsValue]) { Task { await analyticsManager?.track(.init(event, properties: properties)) } }
}

private struct GroupInviteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.analyticsManager) private var analyticsManager
    @EnvironmentObject private var groupStore: GroupStore
    @EnvironmentObject private var socialStore: TogetherStore
    let group: GroupDTO
    var entrySource = "group_settings"
    @State private var selected: Set<String> = []
    @State private var isSending = false
    private var eligible: [SocialConnectionDTO] {
        let existing = Set(group.members.map { $0.user.id })
        let pending = Set(group.invitations.compactMap { $0.recipient?.id })
        return socialStore.connections.filter {
            $0.status == "accepted" && !existing.contains($0.person.id) && !pending.contains($0.person.id)
        }
    }

    var body: some View {
        NavigationStack {
            List(eligible) { connection in
                Button {
                    if selected.contains(connection.person.id) {
                        selected.remove(connection.person.id)
                    } else {
                        selected.insert(connection.person.id)
                    }
                } label: {
                    HStack {
                        SocialAvatar(name: connection.person.displayName, avatarURL: connection.person.avatarUrl)
                        Text(connection.person.displayName).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: selected.contains(connection.person.id) ? "checkmark.circle.fill" : "circle")
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityIdentifier("group.invite.connection.\(connection.person.id)")
                .accessibilityValue(selected.contains(connection.person.id)
                    ? String(localized: "group.connection.selected", defaultValue: "Selected")
                    : String(localized: "group.connection.unselected", defaultValue: "Not selected"))
                .disabled(!selected.contains(connection.person.id) && selected.count >= max(0, group.memberLimit - group.memberCount - group.invitations.count))
            }
            .overlay {
                if eligible.isEmpty {
                    ContentUnavailableView(
                        String(localized: "group.invite.empty.title", defaultValue: "No connections to invite"),
                        systemImage: "person.2",
                        description: Text(String(localized: "group.invite.empty.detail", defaultValue: "Connect with someone first, then invite them to this Group."))
                    )
                }
            }
            .navigationTitle(String(localized: "group.invite.more", defaultValue: "Invite connections"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.close", defaultValue: "Close")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "group.invitation.send", defaultValue: "Send")) {
                        Task {
                            isSending = true
                            if let outcome = await groupStore.invite(Array(selected), to: group) {
                                await analyticsManager?.track(.init(.groupInvitationSent, properties: [.entrySource: .string(entrySource), .participantCountBucket: .string(ProductAnalyticsBucket.count(outcome.sentCount)), .result: .string(outcome.rejectedCount == 0 ? "success" : "partial_failure")]))
                                dismiss()
                            }
                            isSending = false
                        }
                    }
                    .disabled(selected.isEmpty || isSending)
                    .accessibilityIdentifier("group.invite.send")
                }
            }
            .task { await socialStore.loadRemainingConnections() }
        }
    }
}

struct GroupCompletionCelebrationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let group: GroupDTO
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
                Text(String(localized: "group.celebration.title", defaultValue: "Your Group completed the week"))
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(group.name).font(.title3).foregroundStyle(.secondary)
                Button(String(localized: "group.celebration.continue", defaultValue: "Keep it going"), action: onDismiss)
                    .buttonStyle(.borderedProminent)
                    .tint(OutboundPalette.companion)
                    .frame(minHeight: 44)
            }
            .padding(32)
        }
    }
}

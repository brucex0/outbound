import SwiftUI
import PhotosUI
import CoreLocation
import MapKit

extension ActivityFlowView {
    var sessionOptionsCard: some View {
        DisclosureGroup(isExpanded: binding(\.setup.isSessionOptionsExpanded)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                setupOptionButton(
                    title: String(localized: "record.setup.cheer_me_on", defaultValue: "Cheer me on"),
                    subtitle: model.dependencies.liveShareStore.isArmedForNextActivity ? (model.dependencies.liveShareStore.selectedConnections.first?.person.displayName ?? String(localized: "common.on", defaultValue: "On")) : String(localized: "common.off", defaultValue: "Off"),
                    systemImage: model.dependencies.liveShareStore.isArmedForNextActivity ? "waveform.circle.fill" : "waveform.circle",
                    isSelected: model.dependencies.liveShareStore.isArmedForNextActivity
                ) {
                    model.setup.showsTrustedContacts = true
                }
                .accessibilityLabel(model.dependencies.liveShareStore.invitationLabel)

                setupOptionButton(
                    title: String(localized: "record.setup.treadmill", defaultValue: "Treadmill"),
                    subtitle: model.setup.isIndoorSession
                        ? String(localized: "record.setup.indoor", defaultValue: "Indoor")
                        : String(localized: "record.setup.outdoor", defaultValue: "Outdoor"),
                    systemImage: "figure.run.treadmill",
                    isSelected: model.setup.isIndoorSession
                ) {
                    model.setup.isIndoorSession.toggle()
                }
                .accessibilityLabel(String(localized: "record.setup.treadmill", defaultValue: "Treadmill"))
                .accessibilityValue(model.setup.isIndoorSession
                    ? String(localized: "common.on", defaultValue: "On")
                    : String(localized: "common.off", defaultValue: "Off"))
                }

                Divider()

                gearSetupMenu

            if model.dependencies.liveShareStore.isArmedForNextActivity {
                Label(
                    model.dependencies.liveShareStore.invitationLabel,
                    systemImage: "person.crop.circle.badge.checkmark"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            if let message = model.dependencies.liveShareStore.lastErrorMessage {
                Text(message)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
                Divider()
                liveGroupSetup
                if let message = model.dependencies.liveGroupStore.lastErrorMessage {
                    Text(message)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.top, 12)
        } label: {
            compactSetupLabel(
                title: String(localized: "record.setup.run_options", defaultValue: "Run options"),
                value: model.setup.sessionOptionsSummary,
                systemImage: "slider.horizontal.3"
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: model.startSetupCardCornerRadius, style: .continuous))
    }

    var groupRunSetupSheet: some View {
        List {
            Section(String(localized: "record.group.title", defaultValue: "Group run")) {
                liveGroupSetup
            }
            Section {
                Text(String(
                    localized: "record.group.detail",
                    defaultValue: "Everyone in the group appears on the map while you run. Group runs end automatically when the run ends."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                if model.setup.plannedIntent?.activityEvent?.id != nil {
                    Text(String(
                        localized: "record.group.event.detail",
                        defaultValue: "Members can join this activity’s live map without an RSVP. Each participant chooses whether to share."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    var liveGroupSetup: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let eventID = model.setup.plannedIntent?.activityEvent?.id {
                GroupActivityPresenceView(eventID: eventID)
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label(String(localized: "record.group.people", defaultValue: "Runners with you"), systemImage: "person.2.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(model.dependencies.liveGroupStore.isSharing ? model.dependencies.liveGroupStore.displayTitle : "Create or join a group run")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                Spacer()
                Text(model.dependencies.liveGroupStore.statusSummary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if model.dependencies.liveGroupStore.isSharing {
                liveGroupParticipantDisclosure

                HStack(spacing: 10) {
                    if model.dependencies.liveGroupStore.activeSession?.isLinkedToActivityEvent != true {
                        Button {
                        Task {
                            model.track(.init(.groupRunInviteShared, properties: [
                                .participantCountBucket: .string(ProductAnalyticsBucket.count(model.dependencies.liveGroupStore.participants.count))
                            ]))
                            guard let presentation = model.dependencies.liveGroupStore.invitePresentation(intent: model.setup.plannedIntent) else { return }
                            await SystemSharePresenter.present(activityItems: presentation.activityItems)
                        }
                        } label: {
                            Label(String(localized: "common.invite", defaultValue: "Invite"), systemImage: "square.and.arrow.up")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(Color(.tertiarySystemBackground), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Button(role: .destructive) {
                        model.dependencies.liveGroupStore.stopFromManagementControl()
                    } label: {
                        Label(
                            model.dependencies.liveGroupStore.activeSession?.isLinkedToActivityEvent == true
                                ? String(localized: "record.group.event.stop", defaultValue: "Stop sharing")
                                : (model.dependencies.liveGroupStore.activeSession?.isCreatedByCurrentUser == true ? "End" : "Leave"),
                            systemImage: "xmark"
                        )
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Color(.tertiarySystemBackground), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            } else {
                if let activityEventID = model.setup.plannedIntent?.activityEvent?.id {
                    VStack(spacing: 10) {
                        Button {
                            Task {
                                model.track(.init(.groupRunJoinAttempted))
                                await model.dependencies.liveGroupStore.joinActivityEvent(activityEventID)
                                if model.dependencies.liveGroupStore.isSharing {
                                    model.track(.init(.groupRunJoined, properties: [
                                        .participantCountBucket: .string(ProductAnalyticsBucket.count(model.dependencies.liveGroupStore.participants.count))
                                    ]))
                                }
                            }
                        } label: {
                            Label(
                                model.dependencies.liveGroupStore.isJoining ? "Joining..." : String(localized: "record.group.event.share", defaultValue: "Share live map with attendees"),
                                systemImage: "person.2.wave.2.fill"
                            )
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Color(.tertiarySystemBackground), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(model.dependencies.liveGroupStore.isJoining)

#if DEBUG
                        Button {
                            model.dependencies.liveGroupStore.startDebugTestGroupRun(
                                intent: model.setup.plannedIntent,
                                center: model.recorder.locationManager.location?.coordinate,
                                activityEventID: activityEventID
                            )
                        } label: {
                            Label(
                                String(localized: "record.group.event.debug.start", defaultValue: "Simulate attendees"),
                                systemImage: "person.3.fill"
                            )
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Color(.tertiarySystemBackground), in: Capsule())
                        }
                        .buttonStyle(.plain)
#endif
                    }

                } else {
                    HStack(spacing: 10) {
                        Button {
                            Task {
                                model.track(.init(.groupRunCreateAttempted))
                                if let presentation = await model.dependencies.liveGroupStore.createGroup(intent: model.setup.plannedIntent) {
                                    model.track(.init(.groupRunCreated, properties: [
                                        .participantCountBucket: .string(ProductAnalyticsBucket.count(model.dependencies.liveGroupStore.participants.count))
                                    ]))
                                    await SystemSharePresenter.present(activityItems: presentation.activityItems)
                                }
                            }
                        } label: {
                            Label(model.dependencies.liveGroupStore.isCreating ? "Creating..." : "Create", systemImage: "plus")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(Color(.tertiarySystemBackground), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(model.dependencies.liveGroupStore.isCreating)

                        Button {
                            model.setup.groupInviteText = ""
                            model.trackFeatureExposure("group_run")
                            model.setup.isGroupJoinAlertPresented = true
                        } label: {
                            Label(model.dependencies.liveGroupStore.isJoining ? "Joining..." : "Join", systemImage: "link")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(Color(.tertiarySystemBackground), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(model.dependencies.liveGroupStore.isJoining)
                    }
#if DEBUG
                    Button {
                        model.dependencies.liveGroupStore.startDebugTestGroupRun(
                            intent: model.setup.plannedIntent,
                            center: model.recorder.locationManager.location?.coordinate
                        )
                    } label: {
                        Label(
                            String(localized: "record.group.debug.start", defaultValue: "Start test group"),
                            systemImage: "person.3.fill"
                        )
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Color(.tertiarySystemBackground), in: Capsule())
                    }
                    .buttonStyle(.plain)
#endif
                }
            }
        }
    }

    var liveGroupParticipantDisclosure: some View {
        DisclosureGroup(isExpanded: binding(\.setup.isGroupParticipantsExpanded)) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.dependencies.liveGroupStore.participants) { participant in
                    HStack(spacing: 10) {
                        Text(participant.initials)
                            .font(.caption.weight(.black))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(participant.isCurrentUser ? Color.orange : Color.blue))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(participant.isCurrentUser ? "You" : participant.displayName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(model.setup.groupParticipantStatus(participant))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Text(model.dependencies.liveGroupStore.participants.isEmpty ? "Participants" : "Participants (\(model.dependencies.liveGroupStore.participants.count))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .tint(.secondary)
    }

    func setupOptionButton(
        title: String,
        subtitle: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(isSelected ? .white : .orange)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? .white : .primary)
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isSelected ? .white.opacity(0.82) : .secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 54)
            .background(isSelected ? Color.orange : Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    var gearSetupMenu: some View {
        if model.dependencies.gearStore.activeShoes.isEmpty {
            Button {
                model.openAddShoe()
            } label: {
                compactSetupLabel(title: "Shoes", value: "Add shoes", systemImage: "shoeprints.fill")
            }
            .buttonStyle(.plain)
        } else {
            Menu {
                ForEach(model.setup.sessionShoeMenuItems) { shoe in
                    Button {
                        model.setup.selectedSessionShoeID = shoe.id
                        model.track(.init(.shoeSelected, properties: [.selectionType: .string("active_shoe")]))
                    } label: {
                        shoeMenuLabel(shoe)
                    }
                }
                Divider()
                Button(action: model.openAddShoe) {
                    Label(
                        String(localized: "record.shoes.new", defaultValue: "New Shoe"),
                        systemImage: "plus"
                    )
                }
            } label: {
                compactSetupLabel(title: "Shoes", value: model.setup.selectedSessionShoe?.displayName ?? "None", systemImage: "shoeprints.fill")
            }
            .menuOrder(.fixed)
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "record.shoes.change", defaultValue: "Change shoes"))
        }
    }

    @ViewBuilder
    func shoeMenuLabel(_ shoe: GearItem) -> some View {
        if shoe.id == model.setup.selectedSessionShoe?.id {
            Label(shoe.displayName, systemImage: "checkmark")
        } else {
            Text(shoe.displayName)
        }
    }
}

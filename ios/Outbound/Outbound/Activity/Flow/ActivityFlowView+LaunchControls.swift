import SwiftUI
import PhotosUI
import CoreLocation
import MapKit

extension ActivityFlowView {
    var launchDock: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(LaunchWorkoutChoice.allCases) { choice in
                        launchWorkoutButton(choice)
                    }
                }
                .padding(.horizontal, 16)
            }
            .defaultScrollAnchor(host.isEmbeddedInToday ? .center : .leading, for: .alignment)

            HStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        launchMusicControl
                        launchVoiceGuideControl
                        launchCheerMeOnControl
                        launchShoeControl
                        launchCompanionControl
                        launchWatchRecorderControl
                        launchEnvironmentControl
                        launchAutoPauseControl
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, host.isEmbeddedInToday ? 16 : 0)
                }
                .frame(maxWidth: .infinity)
                .defaultScrollAnchor(host.isEmbeddedInToday ? .center : .leading, for: .alignment)
                .accessibilityIdentifier("activity.launch.options")

                if !host.isEmbeddedInToday {
                    Divider()
                        .frame(height: 44)

                    photoLaunchControl
                        .padding(.trailing, 16)
                }
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(height: ActivityLaunchLayout.dockHeight)
        .background(.ultraThickMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    var launchMusicControl: AnyView {
        AnyView(setupUtilityButton(
            title: String(localized: "record.setup.music", defaultValue: "Music"),
            value: model.setup.musicSetupValue,
            isConfigured: model.setup.musicIsConfigured
        ) {
            model.trackFeatureExposure("music")
            model.setup.dismissMusicDiscoveryTip(result: "opened")
            model.setup.setupSheet = .music
        }
        .coordinatedTooltip(
            .musicDiscovery,
            isEligible: model.canRequestMusicDiscoveryTip,
            text: String(localized: "record.music.discovery.tip", defaultValue: "Tap to add music"),
            arrowEdge: .bottom
        ))
    }

    var launchVoiceGuideControl: AnyView {
        AnyView(setupUtilityButton(
            title: String(localized: "record.voice_guide.title", defaultValue: "Voice Guide"),
            value: model.isVoiceGuideExplicitlyUnavailable
                ? String(localized: "record.voice_guide.unavailable.short", defaultValue: "Unavailable")
                : (model.isVoiceGuideEnabled
                    ? String(localized: "common.on", defaultValue: "On")
                    : String(localized: "common.off", defaultValue: "Off")),
            isConfigured: model.voiceGuideSpeechEnabled
        ) {
            model.dependencies.tooltipCoordinator.dismiss(.voiceGuide, outcome: "opened")
            model.setVoiceGuideEnabled(
                model.isVoiceGuideExplicitlyUnavailable ? true : !model.isVoiceGuideEnabled
            )
        }
        .coordinatedTooltip(
            .voiceGuide,
            isEligible: host.isVisible && !model.showCamera && model.dependencies.activityStore.activities.count == 1,
            text: String(localized: "tooltip.voice_guide", defaultValue: "Get coaching cues while you move"),
            arrowEdge: .bottom
        ))
    }

    var launchCheerMeOnControl: AnyView {
        AnyView(setupUtilityButton(
            title: String(localized: "record.setup.cheer_me_on", defaultValue: "Cheer me on"),
            value: model.setup.liveTrackValue,
            isConfigured: model.dependencies.liveShareStore.isArmedForNextActivity
        ) {
            model.dependencies.tooltipCoordinator.dismiss(.cheerMeOn, outcome: "opened")
            model.setup.showsTrustedContacts = true
        }
        .coordinatedTooltip(
            .cheerMeOn,
            isEligible: host.isVisible && !model.showCamera && model.dependencies.socialStore.connections.contains { $0.status == "accepted" },
            text: String(localized: "tooltip.cheer_me_on", defaultValue: "Invite loved ones to follow along and cheer you on"),
            arrowEdge: .bottom
        ))
    }

    var launchWatchRecorderControl: some View {
        Button {
            model.startWatchApp.toggle()
            model.track(.init(.activityConfigurationChanged, properties: [
                .changeType: .string("watch_app"),
                .selectionType: .string(model.startWatchApp ? "enabled" : "disabled")
            ]))
        } label: {
            utilityButtonLabel(
                String(localized: "watch.app.toggle", defaultValue: "Watch app"),
                isConfigured: model.startWatchApp
            )
        }
        .buttonStyle(.plain)
        .accessibilityValue(model.startWatchApp
            ? String(localized: "common.on", defaultValue: "On")
            : String(localized: "common.off", defaultValue: "Off"))
        .accessibilityHint(String(localized: "watch.app.toggle.hint", defaultValue: "Start Plainstride on Apple Watch when you start an activity."))
        .accessibilityAddTraits(model.startWatchApp ? .isSelected : [])
    }

    var launchEnvironmentControl: AnyView {
        AnyView(setupUtilityButton(
            title: model.setup.indoorOutdoorLabel,
            value: model.setup.indoorOutdoorLabel,
            isConfigured: true
        ) {
            model.setup.isIndoorSession.toggle()
            model.track(.init(.activityConfigurationChanged, properties: [
                .changeType: .string("environment"),
                .selectionType: .string(model.setup.isIndoorSession ? "indoor" : "outdoor")
            ]))
        })
    }

    var launchAutoPauseControl: AnyView {
        let activityType = model.setup.setupActivityType
        guard [.running, .cycling, .walking, .hiking].contains(activityType) else {
            return AnyView(EmptyView())
        }
        let enabled = model.autoPauseEnabled(for: activityType)
        return AnyView(setupUtilityButton(
            title: String(localized: "record.setup.auto_pause", defaultValue: "Auto Pause"),
            value: enabled
                ? String(localized: "common.on", defaultValue: "On")
                : String(localized: "common.off", defaultValue: "Off"),
            isConfigured: enabled
        ) {
            model.setAutoPauseEnabled(!enabled, for: activityType)
            model.track(.init(.activityConfigurationChanged, properties: [
                .changeType: .string("auto_pause"),
                .selectionType: .string(enabled ? "disabled" : "enabled"),
                .activityType: .string(activityType.rawValue)
            ]))
        })
    }

    var launchCompanionControl: AnyView {
        guard model.setup.isCompanionControlAvailable else { return AnyView(EmptyView()) }
        let isSelected = model.setup.companionType != nil
        return AnyView(
            Button {
                model.toggleCompanionContext()
            } label: {
                Text(ActivityCompanionType.dog.displayName)
                    .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(
                    isSelected ? theme.accentColor : Color(.secondarySystemBackground),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .stroke(isSelected ? Color.clear : Color.primary.opacity(0.08), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "recording.companion.accessibility", defaultValue: "With dog"))
            .accessibilityValue(String(localized: "activity.companion.dog.title", defaultValue: "With dog"))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityHint(String(localized: "recording.companion.accessibility_hint", defaultValue: "Tags this activity as taken with your dog"))
        )
    }

    var launchGoalPillRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.setup.availableManualGoalModes, id: \.self) { mode in
                    launchGoalPill(mode)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    var contextualStartControl: some View {
        Button(action: { model.ensureLocationReadyThenStart() }) {
            VStack(spacing: 1) {
                Group {
                    if model.isStartingActivity {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.title3.weight(.black))
                            .offset(x: 1)
                    }
                }
                .frame(width: 54, height: 54)
                .foregroundStyle(.white)
                .background(theme.actionColor, in: Circle())
                .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 5))
                .shadow(color: theme.actionColor.opacity(0.28), radius: 10, y: 5)

                Text(String(localized: "record.start.short", defaultValue: "Start"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(theme.actionColor)
                    .textCase(.uppercase)
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isStartingActivity)
        .accessibilityLabel(model.isStartingActivity ? String(localized: "record.start.preparing", defaultValue: "Preparing activity") : (model.setup.plannedIntent ?? .freestyleRun).startLabel)
        .accessibilityHint(String(localized: "record.start.accessibility_hint", defaultValue: "Starts the prepared activity"))
    }

    func launchWorkoutButton(_ choice: LaunchWorkoutChoice) -> some View {
        Button {
            model.selectWorkoutChoice(choice)
        } label: {
            VStack(spacing: 5) {
                Image(systemName: choice.systemImage)
                    .font((host.isEmbeddedInToday ? Font.title3 : .body).weight(.semibold))
                if !host.isEmbeddedInToday {
                    Text(choice.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }
            .foregroundStyle(choice == model.setup.selectedWorkoutChoice ? Color.white : Color.primary)
            .frame(
                width: host.isEmbeddedInToday ? 52 : ActivityLaunchLayout.controlWidth,
                height: host.isEmbeddedInToday ? 52 : ActivityLaunchLayout.controlHeight
            )
            .background(
                choice == model.setup.selectedWorkoutChoice ? theme.accentColor : Color(.secondarySystemBackground),
                in: host.isEmbeddedInToday
                    ? AnyShape(Circle())
                    : AnyShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            )
            .overlay {
                (host.isEmbeddedInToday
                    ? AnyShape(Circle())
                    : AnyShape(RoundedRectangle(cornerRadius: 15, style: .continuous)))
                    .stroke(choice == model.setup.selectedWorkoutChoice ? Color.clear : Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.title)
        .accessibilityValue(choice.accessibilityValue(
            plannedIntent: model.setup.plannedWorkoutIntent,
            curatedIntent: model.setup.curatedWorkoutIntent,
            selectedMode: model.setup.selectedGoalMode,
            manualGoal: model.setup.manualActivityGoal,
            unitSystem: model.dependencies.measurementPreferences.unitSystem
        ))
        .accessibilityAddTraits(choice == model.setup.selectedWorkoutChoice ? .isSelected : [])
    }

    func launchGoalPill(_ mode: SessionGoalMode) -> some View {
        let isSelected = mode == model.setup.selectedGoalMode
        return Button {
            model.selectLaunchMode(mode)
        } label: {
            Text(mode.pillTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background(isSelected ? theme.accentColor : Color(.systemBackground).opacity(0.88), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(isSelected ? Color.clear : Color.primary.opacity(0.1), lineWidth: 1)
                }
                .shadow(color: .black.opacity(isSelected ? 0.12 : 0.07), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.pillTitle)
        .accessibilityValue(
            mode == .curated && isSelected
                ? model.setup.curatedWorkoutIntent?.title ?? mode.compactValue(goal: nil)
                : mode.compactValue(goal: isSelected ? model.setup.manualActivityGoal : model.setup.manualDraftGoal(for: mode))
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    func setupUtilityButton(
        title: String,
        value: String,
        isConfigured: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            utilityButtonLabel(title, isConfigured: isConfigured)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    func utilityButtonLabel(_ title: String, isConfigured: Bool) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isConfigured ? Color.white : Color.primary)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(
                isConfigured ? theme.accentColor : Color(.secondarySystemBackground),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(isConfigured ? Color.clear : Color.primary.opacity(0.08), lineWidth: 1)
            }
    }

    var launchShoeControl: AnyView {
        if model.dependencies.gearStore.activeShoes.isEmpty {
            AnyView(setupUtilityButton(
                title: String(localized: "record.setup.shoes", defaultValue: "Shoes"),
                value: String(localized: "common.none", defaultValue: "None"),
                isConfigured: false
            ) {
                model.dependencies.tooltipCoordinator.dismiss(.shoes, outcome: "opened")
                model.openAddShoe()
            }
            .coordinatedTooltip(
                .shoes,
                isEligible: host.isVisible && !model.showCamera && model.dependencies.activityStore.activities.count >= 1,
                text: String(localized: "tooltip.shoes", defaultValue: "Track mileage and know when to replace your shoes"),
                arrowEdge: .bottom
            ))
        } else {
            AnyView(Menu {
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
                utilityButtonLabel(
                    String(localized: "record.setup.shoes", defaultValue: "Shoes"),
                    isConfigured: model.setup.selectedSessionShoe != nil
                )
            }
            .menuOrder(.fixed)
            .accessibilityLabel(String(localized: "record.setup.shoes", defaultValue: "Shoes"))
            .accessibilityValue(model.setup.selectedSessionShoe?.displayName ?? String(localized: "common.none", defaultValue: "None")))
        }
    }

    var photoLaunchControl: some View {
        Button(action: model.handlePreActivityPhotoAction) {
            ZStack(alignment: .bottomTrailing) {
                if let photo = model.preActivityPhoto {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(theme.actionColor, lineWidth: 2))

                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 17, height: 17)
                        .background(Color.green, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .offset(x: 2, y: 2)
                } else {
                    Circle()
                        .fill(theme.actionColor)
                        .frame(width: 52, height: 52)
                        .overlay {
                            Image(systemName: "camera.fill")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                }
            }
            .frame(width: 56, height: ActivityLaunchLayout.controlHeight)
            .contentShape(Rectangle())
            .shadow(color: theme.actionColor.opacity(0.24), radius: 7, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "record.photo.control", defaultValue: "Photo"))
        .accessibilityValue(model.photoAccessibilityValue)
    }

    func launchUtilityButton(
        title: String,
        systemImage: String,
        isConfigured: Bool,
        accessibilityValue: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                launchUtilityIcon(systemImage: systemImage, isConfigured: isConfigured)
                if isConfigured { configuredBadge }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
    }

    func launchUtilityIcon(systemImage: String, isConfigured: Bool) -> some View {
        Image(systemName: systemImage)
            .font(.headline.weight(.bold))
            .foregroundStyle(isConfigured ? Color.white : Color.orange)
            .frame(width: 52, height: 52)
            .background(isConfigured ? Color.orange : Color(.secondarySystemBackground), in: Circle())
    }

    var configuredBadge: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 8, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 17, height: 17)
            .background(Color.green, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
    }

    @ViewBuilder
    var shoeLaunchControl: some View {
        if model.dependencies.gearStore.activeShoes.isEmpty {
            launchUtilityButton(
                title: String(localized: "record.setup.shoes", defaultValue: "Shoes"),
                systemImage: "shoeprints.fill",
                isConfigured: false,
                accessibilityValue: String(localized: "record.shoes.none_accessibility", defaultValue: "No shoes configured")
            ) { model.openAddShoe() }
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
                ZStack(alignment: .bottomTrailing) {
                    launchUtilityIcon(systemImage: "shoeprints.fill", isConfigured: model.setup.selectedSessionShoe != nil)
                    if model.setup.selectedSessionShoe != nil { configuredBadge }
                }
            }
            .menuOrder(.fixed)
            .accessibilityLabel(String(localized: "record.setup.shoes", defaultValue: "Shoes"))
            .accessibilityValue(model.setup.selectedSessionShoe?.displayName ?? String(localized: "common.none", defaultValue: "None"))
        }
    }
}

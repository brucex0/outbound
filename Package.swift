// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Outbound",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "OutboundSessionAnalysis",
            targets: ["OutboundSessionAnalysis"]
        )
    ],
    targets: [
        .target(
            name: "OutboundSessionAnalysis",
            path: "ios/Outbound/Outbound",
            exclude: [
                "Activity",
                "App",
                "Assets.xcassets",
                "Camera",
                "Social",
                "GoogleService-Info.plist",
                "Coach/CoachCatalogStore.swift",
                "Coach/CoachSelectionView.swift",
                "Coach/CoachStore.swift",
                "Core/APIClient.swift",
                "Core/ActivityRecorder.swift",
                "Core/FirebaseBootstrap.swift",
                "Core/LocalImageView.swift",
                "Core/LocalActivityStore.swift",
                "Core/LocationManager.swift"
            ],
            sources: [
                "Core/ActiveSessionSnapshot.swift",
                "Core/SessionFormatting.swift",
                "Coach/CoachProfile.swift",
                "Coach/CoachTemplate.swift",
                "Coach/SessionAnalysisProvider.swift",
                "Coach/AppleFoundationModelSessionAnalysisProvider.swift",
                "Coach/VirtualCoach.swift"
            ]
        ),
        .testTarget(
            name: "OutboundSessionAnalysisTests",
            dependencies: ["OutboundSessionAnalysis"],
            path: "Tests/OutboundSessionAnalysisTests"
        )
    ]
)

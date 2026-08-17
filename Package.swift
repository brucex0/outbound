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
                "Gear",
                "Safety",
                "Social",
                "GoogleService-Info.plist",
                "Guide/GuideCatalogStore.swift",
                "Guide/GuideSelectionView.swift",
                "Guide/GuideStore.swift",
                "Core/APIClient.swift",
                "Core/ActivityRecorder.swift",
                "Core/FirebaseBootstrap.swift",
                "Core/LocalImageView.swift",
                "Core/LocalActivityStore.swift",
                "Core/LocationManager.swift",
                "Core/SystemShareSheet.swift",
                "Progress/ProgressView.swift"
            ],
            sources: [
                "Core/ActiveSessionSnapshot.swift",
                "Core/ElevationGainCalculator.swift",
                "Core/SessionFormatting.swift",
                "Domains/Athlete/CompanionContracts.swift",
                "Progress/ProgressStatsEngine.swift",
                "Guide/GuideProfile.swift",
                "Guide/GuideTemplate.swift",
                "Guide/SessionAnalysisProvider.swift",
                "Guide/AppleFoundationModelSessionAnalysisProvider.swift",
                "Guide/VirtualGuide.swift"
            ]
        ),
        .testTarget(
            name: "OutboundSessionAnalysisTests",
            dependencies: ["OutboundSessionAnalysis"],
            path: "Tests/OutboundSessionAnalysisTests"
        )
    ]
)

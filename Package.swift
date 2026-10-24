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
                "Activity", "App", "Assets.xcassets", "Camera", "Domains", "Features",
                "Gear", "Guide", "Safety", "Social", "DesignSystem", "LiveCoachAudio",
                "Goals", "Recognition", "Routes", "Debug", "GoogleService-Info.plist"
            ],
            sources: [
                "Core/ActivitySaveEligibility.swift",
                "Core/ElevationGainCalculator.swift",
                "Core/SessionFormatting.swift",
                "Core/AppLanguage.swift",
                "Progress/ProgressStatsEngine.swift",
                "Integrations/Import/ActivityFileParser.swift",
                "Integrations/Import/ImportArchiveReader.swift",
                "Integrations/Import/StravaExportImporter.swift",
                "Integrations/Import/StravaImportModels.swift"
            ]
        ),
        .testTarget(
            name: "OutboundSessionAnalysisTests",
            dependencies: ["OutboundSessionAnalysis"],
            path: "Tests/OutboundSessionAnalysisTests"
        )
    ]
)

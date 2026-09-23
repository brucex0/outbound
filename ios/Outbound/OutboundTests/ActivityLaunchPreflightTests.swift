import SwiftUI
import Testing
@testable import Outbound

struct ActivityLaunchPreflightTests {
    @Test func indoorSessionStartsWithoutLocationPermission() {
        #expect(
            ActivityLaunchPreflight.decision(
                isIndoor: true,
                permissionGranted: false,
                hasRecentValidLocation: false
            ) == .startImmediately
        )
    }

    @Test func outdoorSessionRequestsPermissionBeforeWaitingForGPS() {
        #expect(
            ActivityLaunchPreflight.decision(
                isIndoor: false,
                permissionGranted: false,
                hasRecentValidLocation: false
            ) == .requestPermission
        )
    }

    @Test func permittedOutdoorSessionWaitsForFreshFix() {
        #expect(
            ActivityLaunchPreflight.decision(
                isIndoor: false,
                permissionGranted: true,
                hasRecentValidLocation: false
            ) == .waitForLocation
        )
    }

    @Test func safeZonePreservesAllPublishedEdges() {
        let safeZone = ActivityMapSafeZone(
            topInset: 12,
            bottomInset: 180,
            leadingInset: 8,
            trailingInset: 24
        )

        #expect(safeZone.edgeInsets.top == 12)
        #expect(safeZone.edgeInsets.bottom == 180)
        #expect(safeZone.edgeInsets.leading == 8)
        #expect(safeZone.edgeInsets.trailing == 24)
    }
}

import MapKit
import SwiftUI
import UIKit

struct LiveMapView: View {
    @ObservedObject var recorder: ActivityRecorder
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var coach: VirtualCoach
    let capturedPhotoCount: Int
    let lastCapturedPhoto: UIImage?
    @Binding var activePage: SessionPage
    let onStart: () -> Void
    let onFinish: () -> Void

    @State private var mapPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var isFollowingUser = true

    var body: some View {
        ZStack {
            Map(position: $mapPosition, interactionModes: [.pan, .zoom, .rotate]) {
                UserAnnotation()
                if locationManager.trackPoints.count > 1 {
                    MapPolyline(coordinates: locationManager.trackPoints.map(\.coordinate))
                        .stroke(.orange, lineWidth: 4)
                }
            }
            .onMapCameraChange(frequency: .onEnd) { _ in
                if mapPosition.positionedByUser {
                    isFollowingUser = false
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 12) {
                Spacer()

                if shouldShowCoachNudge {
                    coachNudgeBubble
                        .padding(.horizontal, 16)
                }

                SessionStatusCard(
                    state: recorder.state,
                    elapsedText: recorder.elapsedSeconds.formatted(),
                    paceLabel: recorder.state == .paused ? "Avg. pace" : "Pace",
                    paceText: sessionPaceText,
                    distanceText: String(format: "%.2f", recorder.distanceMeters / 1000),
                    onStart: onStart,
                    onPause: pauseActivity,
                    onResume: resumeActivity,
                    onFinish: onFinish
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }

            VStack {
                Spacer()

                HStack {
                    Spacer()

                    rightControlRail
                }
                .padding(.trailing, 16)
                .padding(.bottom, railBottomPadding)
            }
        }
        .onReceive(locationManager.$location) { loc in
            guard let loc, isFollowingUser else { return }
            updateMapCamera(for: loc, animated: true)
        }
    }

    private var shouldShowCoachNudge: Bool {
        recorder.state != .idle && !coach.lastNudge.isEmpty
    }

    private var coachNudgeBubble: some View {
        Text(coach.lastNudge)
            .font(.caption)
            .foregroundStyle(.white)
            .lineLimit(3)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var rightControlRail: some View {
        VStack(spacing: 14) {
            CapturedPhotoStackView(
                image: lastCapturedPhoto,
                count: capturedPhotoCount,
                isConfirming: false
            )

            Button { activePage = .camera } label: {
                Image(systemName: "camera.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(.black.opacity(0.42)))
            }
            .accessibilityLabel("Show Camera")

            Button {
                if let loc = locationManager.location {
                    isFollowingUser = true
                    updateMapCamera(for: loc, animated: true)
                }
            } label: {
                Image(systemName: "location.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(.black.opacity(0.42)))
            }
            .accessibilityLabel("Recenter Map")
        }
    }

    private var railBottomPadding: CGFloat {
        recorder.state == .paused ? 230 : 184
    }

    private var sessionPaceText: String {
        switch recorder.state {
        case .idle:
            return "--"
        case .active:
            return recorder.currentPace?.paceString ?? "--"
        case .paused:
            guard recorder.distanceMeters > 0 else { return "--" }
            return (Double(recorder.elapsedSeconds) / (recorder.distanceMeters / 1000)).paceString
        }
    }

    private func pauseActivity() {
        recorder.pause()
    }

    private func resumeActivity() {
        recorder.resume()
    }

    private func updateMapCamera(for location: CLLocation, animated: Bool) {
        let update = {
            mapPosition = .camera(MapCamera(
                centerCoordinate: location.coordinate,
                distance: 400,
                heading: location.course >= 0 ? location.course : 0,
                pitch: 0
            ))
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.6)) {
                update()
            }
        } else {
            update()
        }
    }
}

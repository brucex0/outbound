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
    let onFinish: () -> Void

    @State private var mapPosition: MapCameraPosition = .userLocation(fallback: .automatic)

    private let statColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $mapPosition, interactionModes: .zoom) {
                UserAnnotation()
                if locationManager.trackPoints.count > 1 {
                    MapPolyline(coordinates: locationManager.trackPoints.map(\.coordinate))
                        .stroke(.orange, lineWidth: 4)
                }
            }
            .ignoresSafeArea()

            bottomOverlay
        }
        // Keep map centered on runner
        .onReceive(locationManager.$location) { loc in
            guard let loc else { return }
            withAnimation(.easeInOut(duration: 0.6)) {
                mapPosition = .camera(MapCamera(
                    centerCoordinate: loc.coordinate,
                    distance: 400,
                    heading: loc.course >= 0 ? loc.course : 0,
                    pitch: 0
                ))
            }
        }
    }

    private var bottomOverlay: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !coach.lastNudge.isEmpty {
                Text(coach.lastNudge)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .lineLimit(3)
            }

            activityStatsRow

            HStack(alignment: .center) {
                // Finish
                Button(action: onFinish) {
                    Label("Finish", systemImage: "stop.fill")
                        .font(.headline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(.red))
                        .foregroundStyle(.white)
                }

                Spacer()

                Button { activePage = .camera } label: {
                    Image(systemName: "camera.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(Circle().fill(.white.opacity(0.2)))
                }
                .accessibilityLabel("Show Camera")

                Spacer()

                // Re-center
                Button {
                    if let loc = locationManager.location {
                        withAnimation {
                            mapPosition = .camera(MapCamera(
                                centerCoordinate: loc.coordinate,
                                distance: 400,
                                heading: loc.course >= 0 ? loc.course : 0,
                                pitch: 0
                            ))
                        }
                    }
                } label: {
                    Image(systemName: "location.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(minWidth: 78, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.52))
    }

    private var activityStatsRow: some View {
        ZStack(alignment: .topTrailing) {
            LazyVGrid(columns: statColumns, alignment: .leading, spacing: 10) {
                CameraStatTile(icon: "timer",       label: "Time",
                               value: recorder.elapsedSeconds.formatted())
                CameraStatTile(icon: "figure.run",  label: "Distance",
                               value: String(format: "%.2f km", recorder.distanceMeters / 1000))
                CameraStatTile(icon: "speedometer", label: "Pace",
                               value: recorder.currentPace?.paceString ?? "-- /km")
                CameraStatTile(icon: "heart.fill",  label: "Heart Rate",
                               value: recorder.heartRate.map { "\($0) bpm" } ?? "-- bpm")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            CapturedPhotoStackView(
                image: lastCapturedPhoto,
                count: capturedPhotoCount,
                isConfirming: false
            )
        }
        .frame(maxWidth: .infinity, minHeight: 98, alignment: .topLeading)
    }
}

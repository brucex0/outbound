import Combine
import CoreLocation
import MapKit
import SwiftUI

struct ActivityEventPlace {
    let displayName: String
    let coordinate: CLLocationCoordinate2D?
}

extension MKLocalSearchCompletion {
    /// Stable identity for suggestion rows; completions carry no unique identifier of their own.
    var suggestionID: String {
        title + "\u{1F}" + subtitle
    }
}

@MainActor
final class ActivityEventLocationSearchModel: NSObject, ObservableObject {
    @Published private(set) var completions: [MKLocalSearchCompletion] = []

    private let completer: MKLocalSearchCompleter

    override init() {
        let completer = MKLocalSearchCompleter()
        completer.resultTypes = [.address, .pointOfInterest]
        self.completer = completer
        super.init()
        completer.delegate = self
    }

    func update(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clear()
            return
        }
        completer.queryFragment = trimmed
    }

    func clear() {
        completer.queryFragment = ""
        completions = []
    }

    func resolve(_ completion: MKLocalSearchCompletion) async -> ActivityEventPlace {
        let fallbackName = ActivityEventLocationFormatter.joined(
            completion.title,
            completion.subtitle
        )

        do {
            let request = MKLocalSearch.Request(completion: completion)
            let response = try await MKLocalSearch(request: request).start()
            guard let mapItem = response.mapItems.first else {
                return ActivityEventPlace(displayName: fallbackName, coordinate: nil)
            }

            return ActivityEventPlace(
                displayName: ActivityEventLocationFormatter.joined(
                    mapItem.name ?? completion.title,
                    mapItem.placemark.title ?? completion.subtitle
                ),
                coordinate: mapItem.placemark.coordinate
            )
        } catch {
            return ActivityEventPlace(displayName: fallbackName, coordinate: nil)
        }
    }
}

extension ActivityEventLocationSearchModel: MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        var unique: [MKLocalSearchCompletion] = []
        var seen = Set<String>()
        for result in completer.results {
            guard unique.count < 6 else { break }
            guard seen.insert(result.suggestionID).inserted else { continue }
            unique.append(result)
        }
        completions = unique
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        completions = []
    }
}

struct ActivityEventMapPicker: View {
    @Environment(\.dismiss) private var dismiss

    let onSelect: (ActivityEventPlace) -> Void

    @State private var position: MapCameraPosition
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var selectedPlace: ActivityEventPlace?
    @State private var isResolving = false
    @State private var hasResolutionError = false
    @State private var resolutionGeneration = 0
    @State private var resolutionTask: Task<Void, Never>?
    @State private var reverseGeocoder = CLGeocoder()

    init(
        initialCoordinate: CLLocationCoordinate2D?,
        initialName: String? = nil,
        onSelect: @escaping (ActivityEventPlace) -> Void
    ) {
        self.onSelect = onSelect
        _selectedCoordinate = State(initialValue: initialCoordinate)

        if let initialCoordinate {
            _position = State(initialValue: .region(MKCoordinateRegion(
                center: initialCoordinate,
                latitudinalMeters: 1_500,
                longitudinalMeters: 1_500
            )))
            if let initialName, !initialName.isEmpty {
                _selectedPlace = State(initialValue: ActivityEventPlace(
                    displayName: initialName,
                    coordinate: initialCoordinate
                ))
            }
        } else {
            _position = State(initialValue: .userLocation(fallback: .automatic))
        }
    }

    var body: some View {
        NavigationStack {
            Map(position: $position) {
                UserAnnotation()
            }
            .mapStyle(.standard(elevation: .realistic))
            .onMapCameraChange(frequency: .continuous) { context in
                invalidateSelectionIfNeeded(for: context.region.center)
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                choose(context.region.center)
            }
            .overlay {
                centerPin
            }
            .overlay(alignment: .top) {
                HStack(alignment: .top, spacing: 10) {
                    Label(
                        String(
                            localized: "social.event.location.map.instructions",
                            defaultValue: "Pan or zoom the map to choose a meetup point."
                        ),
                        systemImage: "hand.draw"
                    )
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())

                    Spacer(minLength: 0)

                    Button {
                        position = .userLocation(fallback: .automatic)
                    } label: {
                        Image(systemName: "location.fill")
                            .frame(width: 24, height: 24)
                            .padding(8)
                            .background(.regularMaterial, in: Circle())
                    }
                    .accessibilityLabel(
                        String(
                            localized: "social.event.location.map.current",
                            defaultValue: "Go to my location"
                        )
                    )
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                selectionCard
            }
            .navigationTitle(
                String(localized: "social.event.location.map.title", defaultValue: "Choose meetup point")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel", defaultValue: "Cancel")) {
                        dismiss()
                    }
                }
            }
            .task {
                // A coordinate may arrive without a resolved place, for example when the
                // autocomplete resolve was still running when the sheet opened.
                guard selectedPlace == nil, let coordinate = selectedCoordinate else { return }
                beginResolution(for: coordinate)
            }
            .onDisappear {
                resolutionTask?.cancel()
                reverseGeocoder.cancelGeocode()
            }
        }
    }

    private var centerPin: some View {
        Image(systemName: "mappin")
            .font(.system(size: 44, weight: .medium))
            .foregroundStyle(OutboundPalette.companion)
            .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
            .offset(y: -22)
            .accessibilityLabel(
                String(
                    localized: "social.event.location.map.meet_here",
                    defaultValue: "Meet here"
                )
            )
            .allowsHitTesting(false)
    }

    private var selectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isResolving {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(
                        String(
                            localized: "social.event.location.map.locating",
                            defaultValue: "Finding this place…"
                        )
                    )
                    .foregroundStyle(.secondary)
                }
            } else if let selectedPlace {
                Label(selectedPlace.displayName, systemImage: "mappin.and.ellipse")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            } else if hasResolutionError {
                Label(
                    String(
                        localized: "social.event.location.map.unavailable",
                        defaultValue: "Couldn’t identify this place. Try another point."
                    ),
                    systemImage: "exclamationmark.circle"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } else {
                Text(
                    String(
                        localized: "social.event.location.map.no_selection",
                        defaultValue: "No meetup point selected"
                    )
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Button {
                guard let selectedPlace else { return }
                onSelect(selectedPlace)
                dismiss()
            } label: {
                Text(
                    String(
                        localized: "social.event.location.map.use",
                        defaultValue: "Use this location"
                    )
                )
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(OutboundPalette.companion)
            .disabled(selectedPlace == nil || isResolving)
        }
        .padding()
        .background(.regularMaterial)
    }

    private func invalidateSelectionIfNeeded(for coordinate: CLLocationCoordinate2D) {
        guard selectedPlace != nil || isResolving || hasResolutionError else { return }
        guard !coordinatesMatch(selectedCoordinate, coordinate) else { return }

        resolutionGeneration += 1
        resolutionTask?.cancel()
        reverseGeocoder.cancelGeocode()
        resolutionTask = nil
        selectedCoordinate = nil
        selectedPlace = nil
        isResolving = false
        hasResolutionError = false
    }

    private func choose(_ coordinate: CLLocationCoordinate2D) {
        // Camera callbacks can repeat the same settled center. Avoid restarting a valid
        // request, which would otherwise make CLGeocoder more likely to be throttled.
        guard !coordinatesMatch(selectedCoordinate, coordinate) else { return }
        selectedCoordinate = coordinate
        beginResolution(for: coordinate)
    }

    private func beginResolution(for coordinate: CLLocationCoordinate2D) {
        resolutionGeneration += 1
        let generation = resolutionGeneration
        selectedPlace = nil
        hasResolutionError = false
        isResolving = true

        resolutionTask?.cancel()
        reverseGeocoder.cancelGeocode()
        resolutionTask = Task { @MainActor in
            do {
                // Let the camera settle before starting the request, especially after a
                // gesture produces several closely spaced onEnd callbacks.
                try await Task.sleep(nanoseconds: 500_000_000)
                try Task.checkCancellation()
                let place = await resolvePlace(at: coordinate)
                try Task.checkCancellation()

                // A newer map position supersedes this result; never let stale geocoding win.
                guard generation == resolutionGeneration,
                      coordinatesMatch(selectedCoordinate, coordinate) else { return }
                isResolving = false
                selectedPlace = place
                hasResolutionError = place == nil
            } catch is CancellationError {
                // A newer camera position owns the loading state.
            } catch {
                guard generation == resolutionGeneration else { return }
                isResolving = false
                hasResolutionError = true
            }
        }
    }

    private func resolvePlace(at coordinate: CLLocationCoordinate2D) async -> ActivityEventPlace? {
        for attempt in 0..<2 {
            do {
                let placemarks = try await reverseGeocoder.reverseGeocodeLocation(
                    CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                    preferredLocale: .autoupdatingCurrent
                )
                if let placemark = placemarks.first,
                   let place = ActivityEventLocationFormatter.place(
                       from: placemark,
                       coordinate: coordinate
                   ) {
                    return place
                }
            } catch {
                guard !Task.isCancelled else { return nil }
            }

            guard attempt == 0, !Task.isCancelled else { return nil }
            do {
                try await Task.sleep(nanoseconds: 750_000_000)
            } catch {
                return nil
            }
        }
        return nil
    }

    private func coordinatesMatch(
        _ lhs: CLLocationCoordinate2D?,
        _ rhs: CLLocationCoordinate2D
    ) -> Bool {
        guard let lhs else { return false }
        return abs(lhs.latitude - rhs.latitude) < 0.000_001
            && abs(lhs.longitude - rhs.longitude) < 0.000_001
    }
}

enum ActivityEventLocationFormatter {
    static func place(
        from placemark: CLPlacemark,
        coordinate: CLLocationCoordinate2D
    ) -> ActivityEventPlace? {
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let area = [placemark.locality, placemark.administrativeArea]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        let displayName = joined(placemark.name ?? street, area)
        guard !displayName.isEmpty else { return nil }
        return ActivityEventPlace(displayName: displayName, coordinate: coordinate)
    }

    static func joined(_ title: String, _ subtitle: String) -> String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty else { return subtitle }
        guard !subtitle.isEmpty else { return title }
        guard !subtitle.localizedCaseInsensitiveContains(title) else { return subtitle }
        guard !title.localizedCaseInsensitiveContains(subtitle) else { return title }
        return "\(title), \(subtitle)"
    }
}

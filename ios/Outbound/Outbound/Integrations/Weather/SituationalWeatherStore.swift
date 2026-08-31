import Combine
import CoreLocation
import OSLog
import WeatherKit

struct RunningWeatherSnapshot: Codable, Equatable {
    enum Impact: String, Codable {
        case none
        case advisory
        case caution
        case unsafe
    }

    let fetchedAt: Date
    let placeName: String?
    let symbolName: String
    let condition: String
    let temperatureCelsius: Double
    let apparentTemperatureCelsius: Double
    let windKilometersPerHour: Double
    let precipitationChance: Double
    let impact: Impact
    let headline: String
    let guidance: String?
    let bestWindow: String?
    let approximateLatitude: Double?
    let approximateLongitude: Double?
    let approximateAltitudeMeters: Double?

    var isFresh: Bool {
        Date().timeIntervalSince(fetchedAt) < 30 * 60
    }

    func temperatureLabel(unit: TemperatureUnit) -> String {
        let measurement = Measurement(value: temperatureCelsius, unit: UnitTemperature.celsius)
        let value = unit == .fahrenheit
            ? measurement.converted(to: .fahrenheit).value
            : measurement.value
        return "\(Int(value.rounded()))\(unit.symbol)"
    }

    func windLabel(unitSystem: MeasurementUnitSystem) -> String {
        let measurement = Measurement(value: windKilometersPerHour, unit: UnitSpeed.kilometersPerHour)
        if unitSystem == .imperial {
            return "\(Int(measurement.converted(to: .milesPerHour).value.rounded())) mph"
        }
        return "\(Int(measurement.value.rounded())) km/h"
    }

    var companionSignal: CompanionSituationalSignalDTO {
        CompanionSituationalSignalDTO(
            idempotencyKey: "weather-\(Int(fetchedAt.timeIntervalSince1970 / 1800))",
            type: impact == .unsafe ? "weather.lightning" : impact == .caution ? "weather.heat_or_surface_risk" : "weather.running_conditions",
            value: "\(headline); apparent temperature \(Int(apparentTemperatureCelsius.rounded())) C; wind \(Int(windKilometersPerHour.rounded())) km/h; precipitation \(Int((precipitationChance * 100).rounded())) percent",
            source: "apple_weather",
            confidence: 0.9,
            privacy: "approximate_location",
            consequenceLevel: impact == .unsafe ? "high" : impact == .caution ? "medium" : "low",
            possibleEffects: impact == .none ? [] : ["adjust_effort", "adjust_duration", "suggest_time_or_indoor_alternative"],
            scope: ["place": placeName ?? "approximate_current_location", "temporal": "today"],
            observedAt: fetchedAt,
            freshUntil: fetchedAt.addingTimeInterval(60 * 60)
        )
    }
}

@MainActor
final class SituationalWeatherStore: NSObject, ObservableObject {
    nonisolated private static let logger = Logger(subsystem: "plainstride.outbound", category: "Weather")

    @Published private(set) var snapshot: RunningWeatherSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var errorMessage: String?

    private let locationManager = CLLocationManager()
    private let weatherService = WeatherService.shared
    private let defaults: UserDefaults
    private let snapshotKey = "situational_weather_snapshot_v1"
    private let diagnosticKey = "situational_weather_last_diagnostic_v1"
    private var pendingRefresh = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.authorizationStatus = locationManager.authorizationStatus
        self.snapshot = Self.decodeSnapshot(from: defaults.data(forKey: snapshotKey))
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyReduced
        Self.logger.info(
            "Weather store initialized. authorization=\(String(describing: self.authorizationStatus), privacy: .public) cachedSnapshot=\(self.snapshot != nil)"
        )
    }

    func refreshForToday() {
        refresh(force: false)
    }

    func refresh(force: Bool) {
        if !force, snapshot?.isFresh == true {
            Self.logger.debug("Weather refresh skipped because the cached snapshot is fresh.")
            return
        }
        errorMessage = nil
        pendingRefresh = true
        Self.logger.info(
            "Weather refresh requested. force=\(force) authorization=\(String(describing: self.locationManager.authorizationStatus), privacy: .public) hasCachedSnapshot=\(self.snapshot != nil)"
        )

        switch locationManager.authorizationStatus {
        case .notDetermined:
            Self.logger.info("Requesting when-in-use location authorization for local weather.")
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            isLoading = true
            Self.logger.debug("Requesting a one-shot reduced-accuracy location for WeatherKit.")
            locationManager.requestLocation()
        case .denied, .restricted:
            pendingRefresh = false
            Self.logger.warning("Weather refresh stopped because location authorization is denied or restricted.")
            errorMessage = "Location access is off. You can enable it in Settings to see local conditions."
        @unknown default:
            pendingRefresh = false
            Self.logger.error("Weather refresh stopped for an unknown location authorization status.")
            errorMessage = "Local conditions are temporarily unavailable."
        }
    }

    private func loadWeather(for location: CLLocation) async {
        Self.logger.info(
            "Starting WeatherKit request. horizontalAccuracyMeters=\(location.horizontalAccuracy, format: .fixed(precision: 1)) locationAgeSeconds=\(abs(location.timestamp.timeIntervalSinceNow), format: .fixed(precision: 1))"
        )
        do {
            async let weatherRequest = weatherService.weather(for: location)
            async let placeRequest = CLGeocoder().reverseGeocodeLocation(location)
            let weather = try await weatherRequest
            let placemarks = try? await placeRequest
            let place = placemarks?.first?.locality ?? placemarks?.first?.administrativeArea
            let normalized = Self.normalize(weather: weather, placeName: place, location: location)
            snapshot = normalized
            defaults.set(try? JSONEncoder().encode(normalized), forKey: snapshotKey)
            defaults.removeObject(forKey: diagnosticKey)
            errorMessage = nil
            Self.logger.info(
                "WeatherKit request succeeded. condition=\(normalized.condition, privacy: .public) impact=\(normalized.impact.rawValue, privacy: .public) hourlyWindowAvailable=\(normalized.bestWindow != nil)"
            )
        } catch {
            let diagnostic = Self.describe(error)
            defaults.set(diagnostic, forKey: diagnosticKey)
            Self.logger.error("WeatherKit request failed. \(diagnostic, privacy: .public)")
            #if DEBUG
            print("[Weather] WeatherKit request failed. \(diagnostic)")
            #endif
            errorMessage = snapshot == nil
                ? "Weather is temporarily unavailable. Your workout is unchanged."
                : "Conditions could not be refreshed. Showing the last update."
        }
        isLoading = false
        pendingRefresh = false
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return "type=\(String(reflecting: type(of: error))) domain=\(nsError.domain) code=\(nsError.code) localizedDescription=\(nsError.localizedDescription) debug=\(String(reflecting: error))"
    }

    private static func normalize(weather: Weather, placeName: String?, location: CLLocation) -> RunningWeatherSnapshot {
        let current = weather.currentWeather
        let now = Date()
        let upcoming = weather.hourlyForecast.filter { hour in
            hour.date >= now && hour.date <= now.addingTimeInterval(18 * 60 * 60)
        }
        let conditionText = String(describing: current.condition)
        let searchableCondition = conditionText.lowercased()
        let apparentCelsius = current.apparentTemperature.converted(to: .celsius).value
        let windKPH = current.wind.speed.converted(to: .kilometersPerHour).value
        let precipitationChance = upcoming.first?.precipitationChance ?? 0

        let impact: RunningWeatherSnapshot.Impact
        let headline: String
        let guidance: String?

        if searchableCondition.contains("thunder") || searchableCondition.contains("tropical") {
            impact = .unsafe
            headline = "Outdoor running may be unsafe"
            guidance = "Choose an indoor option or wait until the storm has passed."
        } else if apparentCelsius >= 32 {
            impact = .caution
            headline = "Heat will raise the effort"
            guidance = "Run by effort instead of pace, carry fluids, and consider a shorter or cooler window."
        } else if apparentCelsius <= -7 {
            impact = .caution
            headline = "Very cold conditions"
            guidance = "Warm up indoors, cover exposed skin, and keep the first minutes especially easy."
        } else if windKPH >= 35 {
            impact = .advisory
            headline = "Strong wind nearby"
            guidance = "Use effort rather than pace and choose a sheltered route when possible."
        } else if searchableCondition.contains("snow") || searchableCondition.contains("sleet") || searchableCondition.contains("freezing") {
            impact = .caution
            headline = "Slippery surfaces are possible"
            guidance = "Choose a clear route or move the workout indoors."
        } else if precipitationChance >= 0.65 || searchableCondition.contains("rain") {
            impact = .advisory
            headline = "Rain is likely"
            guidance = "The workout still fits; choose visible layers and watch for slick surfaces."
        } else {
            impact = .none
            headline = "Good conditions for today’s run"
            guidance = nil
        }

        return RunningWeatherSnapshot(
            fetchedAt: now,
            placeName: placeName,
            symbolName: current.symbolName,
            condition: conditionText,
            temperatureCelsius: current.temperature.converted(to: .celsius).value,
            apparentTemperatureCelsius: apparentCelsius,
            windKilometersPerHour: windKPH,
            precipitationChance: precipitationChance,
            impact: impact,
            headline: headline,
            guidance: guidance,
            bestWindow: bestRunningWindow(in: Array(upcoming), now: now),
            approximateLatitude: roundedCoordinate(location.coordinate.latitude),
            approximateLongitude: roundedCoordinate(location.coordinate.longitude),
            approximateAltitudeMeters: location.altitude.rounded()
        )
    }

    private static func roundedCoordinate(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private static func bestRunningWindow(in hours: [HourWeather], now: Date) -> String? {
        guard hours.count >= 3 else { return nil }
        let candidates = hours.enumerated().compactMap { index, hour -> (Int, Double)? in
            guard index + 2 < hours.count, hour.isDaylight else { return nil }
            let window = hours[index...(index + 2)]
            let averageRain = window.reduce(0) { $0 + $1.precipitationChance } / Double(window.count)
            let averageTemperature = window.reduce(0) {
                $0 + $1.apparentTemperature.converted(to: .celsius).value
            } / Double(window.count)
            let temperaturePenalty = abs(averageTemperature - 14) / 20
            return (index, averageRain * 2 + temperaturePenalty)
        }
        guard let best = candidates.min(by: { $0.1 < $1.1 }), best.0 > 0 else { return nil }
        let start = hours[best.0].date
        guard start.timeIntervalSince(now) < 12 * 60 * 60 else { return nil }
        return "Best window around \(start.formatted(date: .omitted, time: .shortened))"
    }

    private static func decodeSnapshot(from data: Data?) -> RunningWeatherSnapshot? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(RunningWeatherSnapshot.self, from: data)
    }
}

extension SituationalWeatherStore: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            Self.logger.info(
                "Location authorization changed for weather. authorization=\(String(describing: manager.authorizationStatus), privacy: .public) pendingRefresh=\(self.pendingRefresh)"
            )
            guard pendingRefresh else { return }
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                isLoading = true
                Self.logger.debug("Authorization granted; requesting location for WeatherKit.")
                locationManager.requestLocation()
            case .denied, .restricted:
                pendingRefresh = false
                Self.logger.warning("Location authorization was denied or restricted during weather refresh.")
                errorMessage = "Location access is off. You can enable it in Settings to see local conditions."
            case .notDetermined:
                break
            @unknown default:
                pendingRefresh = false
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            Self.logger.error("Location manager returned an empty location update for weather.")
            return
        }
        Task { @MainActor in
            Self.logger.debug("Received location update for weather without retaining or logging coordinates.")
            await loadWeather(for: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            let diagnostic = Self.describe(error)
            defaults.set(diagnostic, forKey: diagnosticKey)
            Self.logger.error("Location request for weather failed. \(diagnostic, privacy: .public)")
            #if DEBUG
            print("[Weather] Location request failed. \(diagnostic)")
            #endif
            isLoading = false
            pendingRefresh = false
            errorMessage = "Couldn’t determine local conditions. Your workout is unchanged."
        }
    }
}

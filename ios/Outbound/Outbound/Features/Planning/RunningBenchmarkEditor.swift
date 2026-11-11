import SwiftUI

struct RunningBenchmarkReport: Codable, Hashable {
    var activity = "run"
    let source: String
    var maximalEffort = true
    let distanceMeters: Double
    let durationSeconds: Int
    let date: String
}

struct RunningBenchmarkFitness: Codable, Hashable {
    let status: String
    let source: String?
    let report: RunningBenchmarkReport?
}

struct RunningBenchmarkContext: Codable, Hashable {
    let goalID: String
    let fitness: RunningBenchmarkFitness?
}

struct RunningBenchmarkUpdateRequest: Codable {
    let runningBenchmark: RunningBenchmarkReport?
    enum CodingKeys: String, CodingKey { case runningBenchmark }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let runningBenchmark { try container.encode(runningBenchmark, forKey: .runningBenchmark) }
        else { try container.encodeNil(forKey: .runningBenchmark) }
    }
}

struct RunningPhasePace: Codable, Hashable {
    let targetSecondsPerKilometer: Double?
    let fasterToleranceSeconds: Double
    let slowerToleranceSeconds: Double?
    func rangeLabel(units: MeasurementUnitSystem) -> String? {
        guard let center = targetSecondsPerKilometer, center.isFinite, center > fasterToleranceSeconds else { return nil }
        let faster = units.paceString(secondsPerKilometer: center - fasterToleranceSeconds)
        let slower = units.paceString(secondsPerKilometer: center + (slowerToleranceSeconds ?? fasterToleranceSeconds))
        return String(format: benchmarkText("pace_range"), faster, slower)
    }
}

func benchmarkText(_ key: String) -> String { String(localized: String.LocalizationValue("planning.benchmark." + key)) }

struct RunningBenchmarkManagementRow: View {
    @Environment(\.analyticsManager) private var analytics
    let context: RunningBenchmarkContext
    var saveOverride: ((RunningBenchmarkReport?) async throws -> Void)? = nil
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
            Button {
                editing = true
                Task { await analytics?.track(.init(.planningSurfaceOpened, properties: [.sourceType: .string("running_benchmark"), .entrySource: .string("plan_details")])) }
            } label: {
                Text(benchmarkText("title")).font(.subheadline.weight(.semibold)).frame(minHeight: 44, alignment: .leading)
            }.buttonStyle(.plain).foregroundStyle(.tint)
            if let report = context.fitness?.report {
                Text("\(benchmarkText(report.source == "race" ? "race" : "time_trial")) · \(benchmarkLogicalDateLabel(report.date) ?? benchmarkText("fallback"))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(benchmarkText(context.fitness?.status == "eligible" ? "estimate_detail" : context.fitness?.status == "stale" ? "stale" : "fallback"))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .sheet(isPresented: $editing) { NavigationStack { RunningBenchmarkEditor(context: context, saveOverride: saveOverride) } }
    }
}

struct RunningBenchmarkEditor: View {
    @EnvironmentObject private var store: TrainingPlanStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.analyticsManager) private var analytics
    let context: RunningBenchmarkContext
    var saveOverride: ((RunningBenchmarkReport?) async throws -> Void)?
    @State private var distance: String
    @State private var duration: String
    @State private var date: Date
    @State private var source: String
    @State private var maximal: Bool
    @State private var saving = false
    @State private var removes = false
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?

    init(context: RunningBenchmarkContext, saveOverride: ((RunningBenchmarkReport?) async throws -> Void)? = nil) {
        self.context = context; self.saveOverride = saveOverride
        let report = context.fitness?.report
        _distance = State(initialValue: report.map { String($0.distanceMeters / 1000) } ?? "5")
        _duration = State(initialValue: report.map { String(format: "%d:%02d:%02d", $0.durationSeconds / 3600, $0.durationSeconds / 60 % 60, $0.durationSeconds % 60) } ?? "")
        _date = State(initialValue: report.flatMap { Self.dateFormatter.date(from: $0.date) } ?? benchmarkNewReportDate())
        _source = State(initialValue: report?.source ?? "race")
        _maximal = State(initialValue: report?.maximalEffort ?? false)
    }

    var body: some View {
        Form {
            Section {
                Text(benchmarkText("detail")).font(.subheadline)
                Picker(benchmarkText("source"), selection: $source) {
                    Text(benchmarkText("race")).tag("race")
                    Text(benchmarkText("time_trial")).tag("timeTrial")
                }
                TextField(benchmarkText("distance"), text: $distance).keyboardType(.decimalPad)
                TextField(benchmarkText("duration"), text: $duration).keyboardType(.numbersAndPunctuation)
                DatePicker(benchmarkText("date"), selection: $date, in: ...Date(), displayedComponents: .date)
                    .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
                Toggle(benchmarkText("maximal"), isOn: $maximal)
            } footer: { Text(benchmarkText("validation")) }
            Section { Text(benchmarkText("estimate_detail")).font(.footnote) }
            if context.fitness?.status != nil && context.fitness?.status != "absent" {
                Section { Button(benchmarkText("remove"), role: .destructive) { removes = true }.frame(minHeight: 44) }
            }
        }
        .navigationTitle(benchmarkText("title"))
        .disabled(saving)
        .interactiveDismissDisabled(saving)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(String(localized: "today.race_goal.cancel")) { dismiss() }.disabled(saving) }
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "today.race_goal.save")) { if let report { submit(report) } }.disabled(saving || report == nil)
            }
        }
        .onDisappear { toastTask?.cancel() }
        .confirmationDialog(benchmarkText("remove_title"), isPresented: $removes, titleVisibility: .visible) {
            Button(benchmarkText("remove"), role: .destructive) { submit(nil) }
            Button(String(localized: "today.race_goal.cancel"), role: .cancel) {}
        } message: { Text(benchmarkText("remove_detail")) }
        .overlay(alignment: .bottom) {
            if let toast { Text(toast).font(.subheadline).padding().background(.regularMaterial, in: Capsule()).padding().accessibilityAddTraits(.updatesFrequently) }
        }
    }

    private static var dateFormatter: DateFormatter {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"; return formatter
    }
    private var report: RunningBenchmarkReport? {
        guard let seconds = benchmarkDurationSeconds(duration),
              let km = Double(distance.replacingOccurrences(of: ",", with: ".")), km.isFinite,
              (1.5...30).contains(km), maximal else { return nil }
        let day = Self.dateFormatter.string(from: date)
        let today = Self.dateFormatter.date(from: Self.dateFormatter.string(from: Date()))!
        guard seconds > 0, seconds <= 86400, let chosen = Self.dateFormatter.date(from: day),
              chosen <= today, chosen >= today.addingTimeInterval(-84 * 86400) else { return nil }
        return RunningBenchmarkReport(source: source, distanceMeters: km * 1000, durationSeconds: seconds, date: day)
    }
    private func submit(_ report: RunningBenchmarkReport?) {
        saving = true
        Task {
            defer { saving = false }
            do {
                if let saveOverride { try await saveOverride(report) }
                else { try await store.updateRunningBenchmark(goalID: context.goalID, report: report) }
                await analytics?.track(.init(.featureExposed, properties: [.feature: .string(report == nil ? "running_benchmark_removed" : "running_benchmark_saved"), .result: .string("success")]))
                dismiss()
            } catch is CancellationError {
                // Cancellation retains the editor's current inputs and performs no further action.
            } catch {
                let validation: Bool
                if let api = error as? APIError, case let .http(_, _, code) = api { validation = code == "running_benchmark_invalid" }
                else { validation = false }
                let planValidation = error.planningValidationMessage
                if validation || planValidation != nil { ActivityDiagnosticLog.notice(.sync, "running_benchmark_validation category=\(validation ? "invalid_input" : "plan_constraint")") }
                else { ActivityDiagnosticLog.error(.sync, "running_benchmark_update_failed category=\(ActivityDiagnosticLog.errorCategory(error))") }
                await analytics?.track(.init(.featureExposed, properties: [.feature: .string("running_benchmark_save"), .result: .string("failure")]))
                toastTask?.cancel()
                toast = planValidation ?? benchmarkText(validation ? "validation" : "failed")
                toastTask = Task {
                    do { try await Task.sleep(for: .seconds(4)); toast = nil }
                    catch { /* Dismissed/replaced toast is expected cancellation. */ }
                }
            }
        }
    }
}

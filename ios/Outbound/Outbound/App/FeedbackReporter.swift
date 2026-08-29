import SwiftUI
import UIKit
import OSLog

enum FeedbackTrigger {
    static let notification = Notification.Name("plainstride.presentFeedback")

    static func present(currentPage: String? = nil) {
        NotificationCenter.default.post(name: notification, object: currentPage)
    }
}

private enum FeedbackKind: String, CaseIterable, Identifiable {
    case bug = "Bug"
    case suggestion = "Suggestion"

    var id: Self { self }

    var apiValue: String {
        switch self {
        case .bug: "bug"
        case .suggestion: "suggestion"
        }
    }

    var symbol: String {
        switch self {
        case .bug: "ladybug"
        case .suggestion: "lightbulb"
        }
    }
}

struct FeedbackReporterModifier: ViewModifier {
    @Environment(\.analyticsManager) private var analyticsManager
    let isShakeDisabled: Bool
    let currentPage: String
    @State private var presentation: FeedbackPresentation?
    @State private var firstShakeAt: Date?

    private let doubleShakeInterval: TimeInterval = 3

    func body(content: Content) -> some View {
        content
            .background {
                ShakeDetector(isEnabled: !isShakeDisabled && presentation == nil) {
                    registerShake()
                }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
            .onReceive(NotificationCenter.default.publisher(for: FeedbackTrigger.notification)) { notification in
                presentFeedback(pageOverride: notification.object as? String)
            }
            .onChange(of: isShakeDisabled) { _, isDisabled in
                if isDisabled {
                    firstShakeAt = nil
                }
            }
            .sheet(item: $presentation) { presentation in
                FeedbackForm(screenshot: presentation.screenshot, currentPage: presentation.page)
            }
    }

    private func registerShake() {
        let now = Date()
        guard let firstShakeAt, now.timeIntervalSince(firstShakeAt) <= doubleShakeInterval else {
            self.firstShakeAt = now
            return
        }

        self.firstShakeAt = nil
        presentFeedback()
    }

    private func presentFeedback(pageOverride: String? = nil) {
        guard presentation == nil else { return }
        let screenshot = FeedbackScreenshot.capture()
        presentation = FeedbackPresentation(page: pageOverride ?? currentPage, screenshot: screenshot)
        Task {
            await analyticsManager?.track(
                .init(
                    .feedbackReporterOpened,
                    properties: [
                        .entrySource: .string(pageOverride == nil ? "shake" : "in_app"),
                        .result: .string(screenshot == nil ? "capture_failed" : "capture_succeeded")
                    ]
                )
            )
        }
    }
}

private struct FeedbackPresentation: Identifiable {
    let id = UUID()
    let page: String
    let screenshot: UIImage?
}

extension View {
    func feedbackReporter(isShakeDisabled: Bool = false, currentPage: String) -> some View {
        modifier(FeedbackReporterModifier(isShakeDisabled: isShakeDisabled, currentPage: currentPage))
    }
}

private struct FeedbackForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.analyticsManager) private var analyticsManager
    @State private var kind: FeedbackKind = .bug
    @State private var message = ""
    @State private var includesDiagnostics = true
    @State private var includesRecentLogs = true
    @State private var screenshot: UIImage?
    @State private var isAnnotating = false
    @State private var isSubmitting = false
    @State private var toast: FeedbackToast?
    private let currentPage: String

    init(screenshot: UIImage?, currentPage: String) {
        _screenshot = State(initialValue: screenshot)
        self.currentPage = currentPage
    }

    var body: some View {
        NavigationStack {
            Form {
                if let screenshot {
                    Section("Screenshot") {
                        Image(uiImage: screenshot)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        HStack {
                            Button("Annotate", systemImage: "pencil.tip") {
                                isAnnotating = true
                            }
                            Spacer()
                            Button("Remove", systemImage: "trash", role: .destructive) {
                                self.screenshot = nil
                            }
                        }
                    }
                }

                Section {
                    Picker("Feedback type", selection: $kind) {
                        ForEach(FeedbackKind.allCases) { kind in
                            Label(kind.rawValue, systemImage: kind.symbol).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(kind == .bug ? "What went wrong?" : "What would make Plainstride better?") {
                    TextField("Share as much detail as you can", text: $message, axis: .vertical)
                        .lineLimit(5...10)
                }

                Section {
                    Toggle("Include app and device details", isOn: $includesDiagnostics)
                    Toggle("Include recent app logs", isOn: $includesRecentLogs)
                } footer: {
                    Text("App and device details include the app version, specific device model, and iOS version. Recent logs cover up to the last 15 minutes of this Plainstride session. Private values, health data, and precise locations are excluded. Your account ID, email, and current page are attached to every report.")
                }

                Section {
                    Button {
                        submitReport()
                    } label: {
                        HStack {
                            if isSubmitting {
                                ProgressView()
                            } else {
                                Image(systemName: "paperplane.fill")
                            }
                            Text(
                                isSubmitting
                                    ? String(localized: "Submitting…")
                                    : String(localized: "Submit report")
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .disabled(trimmedMessage.isEmpty || isSubmitting)
                }
            }
            .navigationTitle("Send feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $isAnnotating) {
                if let screenshot {
                    ScreenshotAnnotator(image: screenshot) { annotatedImage in
                        self.screenshot = annotatedImage
                        isAnnotating = false
                    } onCancel: {
                        isAnnotating = false
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    FeedbackToastView(toast: toast)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: toast)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submitReport() {
        guard !isSubmitting, !trimmedMessage.isEmpty else { return }
        isSubmitting = true
        toast = nil
        let recentLogs = includesRecentLogs ? FeedbackLogCollector.snapshot() : nil
        let logSelection = if !includesRecentLogs {
            "logs_excluded"
        } else if recentLogs == nil {
            "logs_unavailable"
        } else {
            "logs_attached"
        }
        let request = FeedbackSubmissionRequest(
            kind: kind.apiValue,
            message: trimmedMessage,
            currentPage: currentPage,
            diagnostics: includesDiagnostics ? FeedbackDiagnostics.summary : nil,
            recentLogs: recentLogs,
            screenshotBase64: screenshot?.jpegData(compressionQuality: 0.82)?.base64EncodedString(),
            screenshotContentType: screenshot == nil ? nil : "image/jpeg"
        )

        Task {
            do {
                _ = try await APIClient.shared.submitFeedback(request)
                await analyticsManager?.track(
                    .init(
                        .feedbackReportSubmitted,
                        properties: [
                            .result: .string("succeeded"),
                            .selectionType: .string(logSelection)
                        ]
                    )
                )
                isSubmitting = false
                toast = FeedbackToast(text: String(localized: "Report submitted"), isError: false)
                try? await Task.sleep(for: .seconds(1.2))
                dismiss()
            } catch {
                await analyticsManager?.track(
                    .init(
                        .feedbackReportSubmitted,
                        properties: [
                            .result: .string("failed"),
                            .selectionType: .string(logSelection)
                        ]
                    )
                )
                isSubmitting = false
                toast = FeedbackToast(
                    text: String(localized: "Could not submit report. Try again."),
                    isError: true
                )
                try? await Task.sleep(for: .seconds(3))
                toast = nil
            }
        }
    }
}

struct FeedbackSubmissionRequest: Encodable {
    let kind: String
    let message: String
    let currentPage: String
    let diagnostics: String?
    let recentLogs: String?
    let screenshotBase64: String?
    let screenshotContentType: String?
}

struct FeedbackSubmissionResponse: Decodable {
    let id: String
    let status: String
}

private struct FeedbackToast: Equatable {
    let text: String
    let isError: Bool
}

private struct FeedbackToastView: View {
    let toast: FeedbackToast

    var body: some View {
        Label(toast.text, systemImage: toast.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(toast.isError ? Color.red : Color.green, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
            .accessibilityAddTraits(.isStaticText)
    }
}

@MainActor
private enum FeedbackScreenshot {
    static func capture() -> UIImage? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?
            .windows.first(where: \.isKeyWindow) else { return nil }

        guard !window.bounds.isEmpty else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale
        format.opaque = window.isOpaque
        return UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { context in
            if !window.drawHierarchy(in: window.bounds, afterScreenUpdates: false) {
                window.layer.render(in: context.cgContext)
            }
        }
    }
}

private struct AnnotationStroke: Identifiable {
    let id = UUID()
    var points: [CGPoint]
}

private struct ScreenshotAnnotator: View {
    let image: UIImage
    let onSave: (UIImage) -> Void
    let onCancel: () -> Void
    @State private var strokes: [AnnotationStroke] = []
    @State private var activeStroke: AnnotationStroke?

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let imageRect = aspectFitRect(imageSize: image.size, in: geometry.size)

                ZStack(alignment: .topLeading) {
                    Color.black.ignoresSafeArea()
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: imageRect.width, height: imageRect.height)
                        .position(x: imageRect.midX, y: imageRect.midY)

                    Canvas { context, _ in
                        var visibleStrokes = strokes
                        if let activeStroke { visibleStrokes.append(activeStroke) }
                        for stroke in visibleStrokes {
                            guard let first = stroke.points.first else { continue }
                            var path = Path()
                            path.move(to: denormalize(first, in: imageRect))
                            for point in stroke.points.dropFirst() {
                                path.addLine(to: denormalize(point, in: imageRect))
                            }
                            context.stroke(
                                path,
                                with: .color(.red),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                            )
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(drawGesture(in: imageRect))
                }
            }
            .navigationTitle("Mark up screenshot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Undo", systemImage: "arrow.uturn.backward") {
                        _ = strokes.popLast()
                    }
                    .disabled(strokes.isEmpty)
                    Button("Save") { onSave(renderedImage()) }
                }
            }
        }
    }

    private func drawGesture(in rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard rect.contains(value.location) else { return }
                let point = normalize(value.location, in: rect)
                if activeStroke == nil {
                    activeStroke = AnnotationStroke(points: [point])
                } else {
                    activeStroke?.points.append(point)
                }
            }
            .onEnded { _ in
                if let activeStroke { strokes.append(activeStroke) }
                activeStroke = nil
            }
    }

    private func renderedImage() -> UIImage {
        UIGraphicsImageRenderer(size: image.size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
            UIColor.systemRed.setStroke()
            for stroke in strokes {
                guard let first = stroke.points.first else { continue }
                let path = UIBezierPath()
                path.lineWidth = max(5, image.size.width / 80)
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.move(to: CGPoint(x: first.x * image.size.width, y: first.y * image.size.height))
                for point in stroke.points.dropFirst() {
                    path.addLine(to: CGPoint(x: point.x * image.size.width, y: point.y * image.size.height))
                }
                path.stroke()
            }
        }
    }

    private func aspectFitRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private func normalize(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: (point.x - rect.minX) / rect.width, y: (point.y - rect.minY) / rect.height)
    }

    private func denormalize(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
    }
}

private enum FeedbackDiagnostics {
    static var summary: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = info?["CFBundleVersion"] as? String ?? "Unknown"
        let device = UIDevice.current
        return "App: \(version) (\(build))\nDevice: \(DeviceModel.displayName)\niOS: \(device.systemVersion)"
    }
}

private enum FeedbackLogCollector {
    private static let lookback: TimeInterval = 15 * 60
    private static let maximumLines = 200
    private static let maximumCharacters = 30_000
    private static let allowedCategories: Set<String> = [
        "Analytics",
        "AppleMusic",
        "Assistant",
        "MusicStore",
        "Weather"
    ]

    static func snapshot(now: Date = Date()) -> String? {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let position = store.position(date: now.addingTimeInterval(-lookback))
            let entries = try store.getEntries(at: position)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let appSubsystems = Set([Bundle.main.bundleIdentifier, "plainstride.outbound"].compactMap { $0 })
            var lines: [String] = []

            for case let entry as OSLogEntryLog in entries {
                guard appSubsystems.contains(entry.subsystem), allowedCategories.contains(entry.category) else {
                    continue
                }
                let line = "\(formatter.string(from: entry.date)) [\(levelName(entry.level))] [\(entry.category)] \(redacted(entry.composedMessage))"
                lines.append(line)
                if lines.count > maximumLines {
                    lines.removeFirst(lines.count - maximumLines)
                }
            }

            guard !lines.isEmpty else { return nil }
            let joined = lines.joined(separator: "\n")
            return String(joined.suffix(maximumCharacters))
        } catch {
            return nil
        }
    }

    private static func levelName(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .undefined: "default"
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .error: "error"
        case .fault: "fault"
        @unknown default: "unknown"
        }
    }

    private static func redacted(_ message: String) -> String {
        let patterns = [
            #"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+"#,
            #"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"#,
            #"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#,
            #"(?i)\b(?:lat(?:itude)?|lon(?:gitude)?|lng)\s*[=:]\s*-?\d{1,3}(?:\.\d+)?"#,
            #"(?<![\d.])-?\d{1,2}\.\d{4,}\s*[,/]\s*-?\d{1,3}\.\d{4,}(?![\d.])"#
        ]
        return patterns.reduce(message) { partial, pattern in
            partial.replacingOccurrences(
                of: pattern,
                with: "[redacted]",
                options: .regularExpression
            )
        }
    }
}

private enum DeviceModel {
    static var displayName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        let resolvedIdentifier = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? identifier
        let name = names[resolvedIdentifier] ?? "iPhone"
        return "\(name) (\(resolvedIdentifier))"
    }

    private static let names: [String: String] = [
        "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus", "iPhone17,5": "iPhone 16e",
        "iPhone18,1": "iPhone 17 Pro", "iPhone18,2": "iPhone 17 Pro Max",
        "iPhone18,3": "iPhone 17", "iPhone18,4": "iPhone Air"
    ]
}

private struct ShakeDetector: UIViewControllerRepresentable {
    let isEnabled: Bool
    let onShake: () -> Void

    func makeUIViewController(context: Context) -> ShakeDetectorViewController {
        let controller = ShakeDetectorViewController()
        controller.isEnabled = isEnabled
        controller.onShake = onShake
        return controller
    }

    func updateUIViewController(_ controller: ShakeDetectorViewController, context: Context) {
        controller.isEnabled = isEnabled
        controller.onShake = onShake
    }
}

private final class ShakeDetectorViewController: UIViewController {
    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled {
                claimFirstResponderWhenReady()
            } else if isFirstResponder {
                resignFirstResponder()
            }
        }
    }
    var onShake: (() -> Void)?
    private var observers: [NSObjectProtocol] = []

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.claimFirstResponderWhenReady()
            },
            center.addObserver(
                forName: UIWindow.didBecomeKeyNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.claimFirstResponderWhenReady()
            },
            center.addObserver(
                forName: UIResponder.keyboardDidHideNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.claimFirstResponderWhenReady()
            }
        ]
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        claimFirstResponderWhenReady()
    }

    deinit {
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        guard motion == .motionShake, isEnabled else { return }
        onShake?()
    }

    private func claimFirstResponderWhenReady() {
        guard isEnabled else { return }
        Task { @MainActor [weak self] in
            guard let self, self.isEnabled, self.viewIfLoaded?.window != nil else { return }
            self.becomeFirstResponder()
        }
    }
}

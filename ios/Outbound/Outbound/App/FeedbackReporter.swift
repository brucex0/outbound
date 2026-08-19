import MessageUI
import SwiftUI
import UIKit

enum FeedbackTrigger {
    static let notification = Notification.Name("plainstride.presentFeedback")

    static func present() {
        NotificationCenter.default.post(name: notification, object: nil)
    }
}

private enum FeedbackKind: String, CaseIterable, Identifiable {
    case bug = "Bug"
    case suggestion = "Suggestion"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .bug: "ladybug"
        case .suggestion: "lightbulb"
        }
    }
}

struct FeedbackReporterModifier: ViewModifier {
    let isShakeDisabled: Bool
    @State private var isPresented = false
    @State private var screenshot: UIImage?
    @State private var firstShakeAt: Date?

    private let doubleShakeInterval: TimeInterval = 3

    func body(content: Content) -> some View {
        content
            .background {
                ShakeDetector(isEnabled: !isShakeDisabled) {
                    registerShake()
                }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
            .onReceive(NotificationCenter.default.publisher(for: FeedbackTrigger.notification)) { _ in
                presentFeedback()
            }
            .onChange(of: isShakeDisabled) { _, isDisabled in
                if isDisabled {
                    firstShakeAt = nil
                }
            }
            .sheet(isPresented: $isPresented) {
                FeedbackForm(screenshot: screenshot)
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

    private func presentFeedback() {
        guard !isPresented else { return }
        screenshot = FeedbackScreenshot.capture()
        isPresented = true
    }
}

extension View {
    func feedbackReporter(isShakeDisabled: Bool = false) -> some View {
        modifier(FeedbackReporterModifier(isShakeDisabled: isShakeDisabled))
    }
}

private struct FeedbackForm: View {
    @Environment(\.dismiss) private var dismiss
    @State private var kind: FeedbackKind = .bug
    @State private var message = ""
    @State private var includesDiagnostics = true
    @State private var emailedReport: FeedbackReport?
    @State private var showsMailUnavailableAlert = false
    @State private var screenshot: UIImage?
    @State private var isAnnotating = false

    init(screenshot: UIImage?) {
        _screenshot = State(initialValue: screenshot)
    }

    var body: some View {
        NavigationStack {
            Form {
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
                } footer: {
                    Text("This includes the app version, device type, and iOS version. It does not include health, location, or account data.")
                }

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
                    Button {
                        if MFMailComposeViewController.canSendMail() {
                            emailedReport = FeedbackReport(text: reportText, screenshot: screenshot)
                        } else {
                            showsMailUnavailableAlert = true
                        }
                    } label: {
                        Label("Email report", systemImage: "envelope.fill")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .disabled(trimmedMessage.isEmpty)
                } footer: {
                    Text("Your report will be addressed to info@plainstride.com.")
                }
            }
            .navigationTitle("Send feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $emailedReport) { report in
                FeedbackMailComposer(report: report) {
                    emailedReport = nil
                }
            }
            .alert("Mail isn’t set up", isPresented: $showsMailUnavailableAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Set up an email account in Mail, then try again.")
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
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var reportText: String {
        var sections = ["Plainstride \(kind.rawValue)", "", trimmedMessage]
        if includesDiagnostics {
            sections.append(contentsOf: ["", "---", FeedbackDiagnostics.summary])
        }
        return sections.joined(separator: "\n")
    }
}

private struct FeedbackReport: Identifiable {
    let id = UUID()
    let text: String
    let screenshot: UIImage?

}

private struct FeedbackMailComposer: UIViewControllerRepresentable {
    let report: FeedbackReport
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        composer.setToRecipients(["info@plainstride.com"])
        composer.setSubject(String(localized: "Plainstride feedback"))
        composer.setMessageBody(report.text, isHTML: false)
        if let screenshot = report.screenshot, let data = screenshot.jpegData(compressionQuality: 0.9) {
            composer.addAttachmentData(data, mimeType: "image/jpeg", fileName: "plainstride-feedback.jpg")
        }
        return composer
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true)
            onFinish()
        }
    }
}

@MainActor
private enum FeedbackScreenshot {
    static func capture() -> UIImage? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?
            .windows.first(where: \.isKeyWindow) else { return nil }

        return UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
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
        return "App: \(version) (\(build))\nDevice: \(device.model)\niOS: \(device.systemVersion)"
    }
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
    var isEnabled = true
    var onShake: (() -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        guard motion == .motionShake, isEnabled else { return }
        onShake?()
    }
}

import AVFoundation
import SwiftUI
import UIKit
import Vision
import VisionKit

struct SocialConnectionQRCodeView: View {
    @Environment(\.analyticsManager) private var analyticsManager
    @State private var profile: AppUserProfileDTO?
    @State private var connectionURL: URL?
    @State private var isLoading = true
    @State private var hasError = false

    var body: some View {
        ScrollView {
            VStack(spacing: OutboundSpacing.standard) {
                if let profile {
                    OutboundCard {
                        VStack(spacing: OutboundSpacing.compact) {
                            SocialAvatar(name: profile.displayName, avatarURL: profile.avatarUrl)
                            Text(profile.displayName)
                                .font(.headline)
                            if !profile.username.isEmpty {
                                Text("@\(profile.username)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                }

                OutboundCard {
                    VStack(spacing: OutboundSpacing.standard) {
                        if let connectionURL,
                           let qrImage = QRCodeRenderer.image(for: connectionURL) {
                            Image(uiImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 280, height: 280)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .accessibilityLabel(String(localized: "My Plainstride QR code"))

                            Text(String(
                                localized: "Scan this QR code to join me on Plainstride.",
                                defaultValue: "Scan this QR code to join me on Plainstride."
                            ))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        } else if isLoading {
                            ProgressView()
                                .frame(width: 280, height: 280)
                        } else if hasError {
                            ContentUnavailableView(
                                String(localized: "QR code unavailable"),
                                systemImage: "qrcode",
                                description: Text(String(
                                    localized: "Could not load your connection code. Try again.",
                                    defaultValue: "Could not load your connection code. Try again.",
                                    table: "ConnectionQRCode"
                                ))
                            )
                            .frame(height: 280)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(OutboundSpacing.screen)
        }
        .background(OutboundPalette.background)
        .navigationTitle(String(localized: "My QR Code"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadCode() }
    }

    private func loadCode() async {
        await analyticsManager?.track(.init(.profileQRCodeOpened, properties: [
            .entrySource: .string("connections")
        ]))
        do {
            async let profileRequest = APIClient.shared.fetchMyProfile()
            async let linkRequest = APIClient.shared.createConnectionLink()
            let (loadedProfile, link) = try await (profileRequest, linkRequest)
            profile = loadedProfile
            connectionURL = link.url
        } catch {
            hasError = true
        }
        isLoading = false
    }
}

struct SocialConnectionQRScannerView: View {
    private enum CameraState {
        case requesting
        case ready
        case denied
        case unavailable
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.analyticsManager) private var analyticsManager
    @EnvironmentObject private var socialStore: TogetherStore
    @State private var cameraState: CameraState = .requesting
    @State private var isProcessing = false
    @State private var scannerMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                switch cameraState {
                case .requesting:
                    ProgressView()
                        .tint(.white)
                case .ready:
                    ConnectionCodeScanner(isScanning: !isProcessing, onPayload: handlePayload)
                        .ignoresSafeArea()
                    scannerOverlay
                case .denied:
                    unavailableView(
                        title: String(localized: "Camera access needed", table: "ConnectionQRCode"),
                        description: String(localized: "Allow camera access in Settings to scan a Plainstride connection code.", table: "ConnectionQRCode"),
                        showsSettingsButton: true
                    )
                case .unavailable:
                    unavailableView(
                        title: String(localized: "Scanner unavailable", table: "ConnectionQRCode"),
                        description: String(localized: "This device can’t scan connection codes.", table: "ConnectionQRCode"),
                        showsSettingsButton: false
                    )
                }
            }
            .navigationTitle(String(localized: "Scan QR Code", table: "ConnectionQRCode"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.black.opacity(0.72), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Close")) { dismiss() }
                }
            }
        }
        .task { await prepareCamera() }
        .task(id: scannerMessage) {
            guard scannerMessage != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            scannerMessage = nil
        }
    }

    private var scannerOverlay: some View {
        VStack(spacing: 0) {
            Text(String(localized: "Scan a friend’s Plainstride QR code.", table: "ConnectionQRCode"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.black.opacity(0.68), in: Capsule())
                .padding(.top, 28)

            Spacer()

            if isProcessing {
                ProgressView(String(localized: "Sending connection request…", table: "ConnectionQRCode"))
                    .tint(.white)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.72), in: Capsule())
            } else if let scannerMessage {
                Label(scannerMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.72), in: Capsule())
            }
        }
        .padding(OutboundSpacing.screen)
    }

    @ViewBuilder
    private func unavailableView(title: String, description: String, showsSettingsButton: Bool) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "camera.viewfinder")
                .foregroundStyle(.white)
        } description: {
            Text(description)
                .foregroundStyle(.white.opacity(0.75))
        } actions: {
            if showsSettingsButton {
                Button(String(localized: "Open Settings", table: "ConnectionQRCode")) {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func prepareCamera() async {
        await analyticsManager?.track(.init(.featureExposed, properties: [
            .feature: .string("connection_qr_scanner")
        ]))

        guard DataScannerViewController.isSupported,
              DataScannerViewController.isAvailable else {
            cameraState = .unavailable
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraState = .ready
        case .notDetermined:
            cameraState = await AVCaptureDevice.requestAccess(for: .video) ? .ready : .denied
        case .denied, .restricted:
            cameraState = .denied
        @unknown default:
            cameraState = .unavailable
        }
    }

    private func handlePayload(_ payload: String) {
        guard !isProcessing else { return }
        guard let url = URL(string: payload),
              let code = PlainstrideLinks.connectionCode(from: url) else {
            scannerMessage = String(localized: "Not a Plainstride connection code", table: "ConnectionQRCode")
            return
        }

        isProcessing = true
        Task {
            let outcome = await socialStore.consumeConnectionLink(code: code)
            await analyticsManager?.track(.init(.connectionQRCodeRequestResult, properties: [
                .result: .string(outcome.analyticsResult)
            ]))
            if outcome.shouldClearPendingURL {
                dismiss()
            } else {
                isProcessing = false
            }
        }
    }
}

private struct ConnectionCodeScanner: UIViewControllerRepresentable {
    let isScanning: Bool
    let onPayload: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPayload: onPayload)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.onPayload = onPayload
        if isScanning, !controller.isScanning {
            try? controller.startScanning()
        } else if !isScanning, controller.isScanning {
            controller.stopScanning()
        }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onPayload: (String) -> Void

        init(onPayload: @escaping (String) -> Void) {
            self.onPayload = onPayload
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard case let .barcode(barcode) = addedItems.first,
                  let payload = barcode.payloadStringValue else { return }
            onPayload(payload)
        }
    }
}

import AVFoundation
import Combine
import UIKit

final class CameraController: ObservableObject {
    let session = AVCaptureSession()
    @Published private(set) var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published private(set) var cameraPosition: AVCaptureDevice.Position

    private static let preferredCameraPositionKey = "preferred_camera_position_v1"
    private let userDefaults: UserDefaults
    private var selectedCameraPosition: AVCaptureDevice.Position
    private var photoOutput = AVCapturePhotoOutput()
    private var captureCallbacks: [Int64: (UIImage?) -> Void] = [:]
    private var captureDelegates: [Int64: PhotoDelegate] = [:]
    private let sessionQueue = DispatchQueue(label: "outbound.camera.session")
    private var isConfigured = false

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let position: AVCaptureDevice.Position = userDefaults.string(forKey: Self.preferredCameraPositionKey) == "back"
            ? .back
            : .front
        self.cameraPosition = position
        self.selectedCameraPosition = position
    }

    func start() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        updateAuthorizationStatus(status)

        switch status {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                let newStatus = AVCaptureDevice.authorizationStatus(for: .video)
                self?.updateAuthorizationStatus(newStatus)
                guard granted else { return }
                self?.startSession()
            }
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    private func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureSessionIfNeeded()
            if self.isConfigured {
                self.session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureSessionIfNeeded()
            guard self.isConfigured else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let settings = AVCapturePhotoSettings()
            let captureID = settings.uniqueID
            let delegate = PhotoDelegate { [weak self] image in
                self?.sessionQueue.async {
                    self?.captureCallbacks.removeValue(forKey: captureID)
                    self?.captureDelegates.removeValue(forKey: captureID)
                }
                completion(image)
            }

            // Store callback keyed by expected photo ID
            self.captureCallbacks[captureID] = completion
            self.captureDelegates[captureID] = delegate
            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    func flipCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
            self.configureSessionIfNeeded()
            guard self.isConfigured else { return }

            let newPosition: AVCaptureDevice.Position = self.selectedCameraPosition == .back ? .front : .back
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                return
            }

            self.session.beginConfiguration()
            self.session.inputs
                .compactMap { $0 as? AVCaptureDeviceInput }
                .forEach { self.session.removeInput($0) }

            if self.session.canAddInput(input) {
                self.session.addInput(input)
                self.selectedCameraPosition = newPosition
                self.userDefaults.set(newPosition == .back ? "back" : "front", forKey: Self.preferredCameraPositionKey)
                DispatchQueue.main.async {
                    self.cameraPosition = newPosition
                }
            }
            self.session.commitConfiguration()
        }
    }

    private func configureSessionIfNeeded() {
        guard !isConfigured else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo
        let defaultPosition = selectedCameraPosition
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: defaultPosition),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        guard session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(photoOutput)
        session.commitConfiguration()
        isConfigured = true
    }

    private func updateAuthorizationStatus(_ status: AVAuthorizationStatus) {
        DispatchQueue.main.async { [weak self] in
            self?.authorizationStatus = status
        }
    }
}

nonisolated private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (UIImage?) -> Void
    init(completion: @escaping (UIImage?) -> Void) { self.completion = completion }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            completion(nil); return
        }
        completion(UIImage(data: data))
    }
}

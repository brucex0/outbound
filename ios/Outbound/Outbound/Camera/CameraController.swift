import AVFoundation
import Combine
import UIKit

final class CameraController: ObservableObject {
    let session = AVCaptureSession()
    @Published private(set) var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    private var photoOutput = AVCapturePhotoOutput()
    private var captureCallbacks: [Int64: (UIImage?) -> Void] = [:]
    private let sessionQueue = DispatchQueue(label: "outbound.camera.session")
    private var isConfigured = false

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
            let settings = AVCapturePhotoSettings()
            // Store callback keyed by expected photo ID
            self.captureCallbacks[settings.uniqueID] = completion
            self.photoOutput.capturePhoto(with: settings, delegate: PhotoDelegate { [weak self] image in
                self?.sessionQueue.async {
                    self?.captureCallbacks.removeValue(forKey: settings.uniqueID)
                }
                completion(image)
            })
        }
    }

    private func configureSessionIfNeeded() {
        guard !isConfigured else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
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

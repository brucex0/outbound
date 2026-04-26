import AVFoundation
import UIKit

@MainActor
final class CameraController: ObservableObject {
    let session = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private var captureCallbacks: [Int64: (UIImage?) -> Void] = [:]

    func start() {
        Task.detached(priority: .userInitiated) { [weak self] in
            self?.configureSession()
            self?.session.startRunning()
        }
    }

    func stop() {
        Task.detached { [weak self] in self?.session.stopRunning() }
    }

    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        let settings = AVCapturePhotoSettings()
        // Store callback keyed by expected photo ID
        captureCallbacks[settings.uniqueID] = completion
        photoOutput.capturePhoto(with: settings, delegate: PhotoDelegate { [weak self] image in
            self?.captureCallbacks.removeValue(forKey: settings.uniqueID)
            completion(image)
        })
    }

    private func configureSession() {
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
    }
}

private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (UIImage?) -> Void
    init(completion: @escaping (UIImage?) -> Void) { self.completion = completion }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            completion(nil); return
        }
        completion(UIImage(data: data))
    }
}

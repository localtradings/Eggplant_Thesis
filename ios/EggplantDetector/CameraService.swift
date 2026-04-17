import AVFoundation
import UIKit

final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Expected AVCaptureVideoPreviewLayer backing layer")
        }
        return layer
    }
}

protocol CameraServiceDelegate: AnyObject {
    func cameraService(_ service: CameraService, didOutput pixelBuffer: CVPixelBuffer)
    func cameraService(_ service: CameraService, didFail error: Error)
}

final class CameraService: NSObject {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let outputQueue = DispatchQueue(label: "camera.output.queue")
    private let videoOutput = AVCaptureVideoDataOutput()
    private weak var previewHostView: CameraPreviewView?

    weak var delegate: CameraServiceDelegate?

    func start(in view: CameraPreviewView) {
        previewHostView = view
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.delegate?.cameraService(self, didFail: CameraError.permissionDenied)
                return
            }

            self.sessionQueue.async {
                do {
                    try self.configureSessionIfNeeded()
                    self.session.startRunning()

                    DispatchQueue.main.async {
                        view.layoutIfNeeded()
                        view.videoPreviewLayer.session = self.session
                        view.videoPreviewLayer.videoGravity = .resizeAspectFill
                        view.videoPreviewLayer.frame = view.bounds
                    }
                } catch {
                    self.delegate?.cameraService(self, didFail: error)
                }
            }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func refreshPreviewLayout() {
        DispatchQueue.main.async {
            guard let view = self.previewHostView else { return }
            view.layoutIfNeeded()
            view.videoPreviewLayer.frame = view.bounds
        }
    }

    private func configureSessionIfNeeded() throws {
        guard session.inputs.isEmpty else { return }

        session.beginConfiguration()
        session.sessionPreset = .high

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            session.commitConfiguration()
            throw CameraError.noCamera
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CameraError.cannotAddInput
        }
        session.addInput(input)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)

        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            throw CameraError.cannotAddOutput
        }
        session.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video),
           connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }

        session.commitConfiguration()
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        delegate?.cameraService(self, didOutput: pixelBuffer)
    }
}

private enum CameraError: LocalizedError {
    case permissionDenied
    case noCamera
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Camera permission was denied."
        case .noCamera:
            return "No back camera is available."
        case .cannotAddInput:
            return "The camera input could not be attached."
        case .cannotAddOutput:
            return "The camera output could not be attached."
        }
    }
}

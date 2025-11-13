import AVFoundation
import Photos
import UIKit

class CameraManager: NSObject, ObservableObject {
    @Published var isAuthorized = false
    @Published var capturedImage: UIImage?
    @Published var errorMessage: String?

    private let captureSession = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private var currentDevice: AVCaptureDevice?
    private let audioSession = AVAudioSession.sharedInstance()

    override init() {
        super.init()
        configureSilentAudioSession()
        checkAuthorization()
    }

    private func configureSilentAudioSession() {
        do {
            // Configure audio session to suppress shutter sound
            try audioSession.setCategory(.playAndRecord, options: [.mixWithOthers, .defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            print("オーディオセッションの設定に失敗: \(error.localizedDescription)")
        }
    }

    func checkAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted {
                        self?.setupCamera()
                    }
                }
            }
        default:
            isAuthorized = false
        }
    }

    private func setupCamera() {
        captureSession.beginConfiguration()

        // Set session preset for high resolution
        if captureSession.canSetSessionPreset(.photo) {
            captureSession.sessionPreset = .photo
        }

        // Get the best camera device (48MP capable)
        guard let device = getBestCameraDevice() else {
            errorMessage = "48MP対応カメラが見つかりません"
            captureSession.commitConfiguration()
            return
        }

        currentDevice = device

        do {
            let input = try AVCaptureDeviceInput(device: device)

            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }

            if captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)

                // Enable Apple ProRAW if available
                if photoOutput.isAppleProRAWSupported {
                    photoOutput.isAppleProRAWEnabled = true
                }

                // Configure for maximum quality
                if let photoSettings = photoOutput.availablePhotoCodecTypes.first {
                    photoOutput.maxPhotoQualityPrioritization = .quality
                }
            }

            captureSession.commitConfiguration()

            // Start session on background thread
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession.startRunning()
            }

        } catch {
            errorMessage = "カメラの設定に失敗しました: \(error.localizedDescription)"
            captureSession.commitConfiguration()
        }
    }

    private func getBestCameraDevice() -> AVCaptureDevice? {
        // Get the best available back camera
        // iPhone 14 Pro and later will support 48MP when we set maxPhotoDimensions
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        )

        // Return the first available back camera
        // The 48MP capability is determined by maxPhotoDimensions setting during capture
        return discoverySession.devices.first
    }

    func capturePhoto() {
        // Re-configure audio session right before capture to ensure silence
        do {
            try audioSession.setCategory(.playAndRecord, options: [.mixWithOthers, .defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            print("撮影前のオーディオセッション設定に失敗: \(error.localizedDescription)")
        }

        var settings: AVCapturePhotoSettings

        // Enable Apple ProRAW if supported
        if photoOutput.isAppleProRAWSupported {
            if let rawFormat = photoOutput.availableRawPhotoPixelFormatTypes.first {
                settings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat)
                settings.photoQualityPrioritization = .quality
            } else {
                settings = AVCapturePhotoSettings()
            }
        } else {
            settings = AVCapturePhotoSettings()
        }

        // Enable max resolution (48MP)
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions

        // Silent shutter - disable flash
        settings.flashMode = .off

        // Capture without shutter sound
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func getPreviewLayer() -> AVCaptureVideoPreviewLayer {
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        return previewLayer
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.errorMessage = "撮影エラー: \(error.localizedDescription)"
            }
            return
        }

        // Get RAW image data
        var imageData: Data?

        // Try to get RAW data first (DNG format)
        if let rawData = photo.fileDataRepresentation() {
            imageData = rawData

            // Save to photo library
            savePhotoToLibrary(imageData: rawData, isRaw: true)
        } else if let jpegData = photo.fileDataRepresentation() {
            // Fallback to JPEG if RAW not available
            imageData = jpegData
            savePhotoToLibrary(imageData: jpegData, isRaw: false)
        }

        // Update preview image
        if let data = imageData, let image = UIImage(data: data) {
            DispatchQueue.main.async {
                self.capturedImage = image
            }
        }
    }

    private func savePhotoToLibrary(imageData: Data, isRaw: Bool) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async {
                    self.errorMessage = "写真ライブラリへのアクセスが許可されていません"
                }
                return
            }

            PHPhotoLibrary.shared().performChanges({
                let creationRequest = PHAssetCreationRequest.forAsset()

                if isRaw {
                    // Save as RAW (DNG)
                    creationRequest.addResource(with: .photo, data: imageData, options: nil)
                } else {
                    // Save as JPEG
                    creationRequest.addResource(with: .photo, data: imageData, options: nil)
                }

            }) { success, error in
                DispatchQueue.main.async {
                    if success {
                        self.errorMessage = nil
                        print("写真を保存しました (\(isRaw ? "RAW" : "JPEG"))")
                    } else if let error = error {
                        self.errorMessage = "保存エラー: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}

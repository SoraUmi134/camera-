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

    override init() {
        super.init()
        checkAuthorization()
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
        // Try to get triple camera or wide-angle camera with 48MP support
        // iPhone 14 Pro and later have 48MP main camera
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        )

        // Find device that supports high resolution (48MP)
        for device in discoverySession.devices {
            if device.activeFormat.isHighResolutionPhotoEnabled {
                return device
            }
        }

        // Fallback to any available back camera
        return discoverySession.devices.first
    }

    func capturePhoto() {
        let settings = AVCapturePhotoSettings()

        // Enable Apple ProRAW if supported
        if photoOutput.isAppleProRAWSupported {
            if let rawFormat = photoOutput.availableRawPhotoPixelFormatTypes.first {
                settings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat)
                settings.photoQualityPrioritization = .quality
            }
        }

        // Enable max resolution (48MP)
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions

        // Silent shutter - use flash mode off
        settings.flashMode = .off

        // Disable shutter sound (Note: This may not work on Japanese iPhones due to legal requirements)
        // Using Live Photo can reduce shutter sound volume
        if photoOutput.isLivePhotoCaptureSupported {
            let livePhotoMovieFileName = UUID().uuidString
            let livePhotoMovieFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((livePhotoMovieFileName as NSString).appendingPathExtension("mov")!)
            settings.livePhotoMovieFileURL = URL(fileURLWithPath: livePhotoMovieFilePath)
        }

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

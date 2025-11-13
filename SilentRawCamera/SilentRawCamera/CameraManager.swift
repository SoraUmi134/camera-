import AVFoundation
import Photos
import UIKit

class CameraManager: NSObject, ObservableObject {
    @Published var isAuthorized = false
    @Published var capturedImage: UIImage?
    @Published var errorMessage: String?
    @Published var isSessionReady = false

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
                guard let self = self else { return }
                self.captureSession.startRunning()

                // Wait a bit for session to stabilize, then mark as ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.isSessionReady = true
                    print("カメラセッション準備完了")
                }
            }

        } catch {
            errorMessage = "カメラの設定に失敗しました: \(error.localizedDescription)"
            captureSession.commitConfiguration()
        }
    }

    private func getBestCameraDevice() -> AVCaptureDevice? {
        // Try different camera types in order of preference
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInWideAngleCamera
        ]

        // Try each device type
        for deviceType in deviceTypes {
            if let device = AVCaptureDevice.default(deviceType, for: .video, position: .back) {
                print("カメラデバイスを検出: \(deviceType.rawValue)")
                return device
            }
        }

        // Fallback: Use discovery session
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        )

        if let device = discoverySession.devices.first {
            print("ディスカバリーセッションでカメラを検出")
            return device
        }

        // Last resort: any video device
        print("エラー: カメラデバイスが見つかりません")
        return AVCaptureDevice.default(for: .video)
    }

    func capturePhoto() {
        // Check if session is ready
        guard isSessionReady && captureSession.isRunning else {
            print("カメラセッションがまだ準備できていません")
            DispatchQueue.main.async {
                self.errorMessage = "カメラが準備中です。少しお待ちください"
            }
            return
        }

        // Check if there's an active video connection
        guard let connection = photoOutput.connection(with: .video), connection.isEnabled else {
            print("ビデオ接続が有効ではありません")
            DispatchQueue.main.async {
                self.errorMessage = "カメラ接続エラー"
            }
            return
        }

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

        print("撮影開始")
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

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
        print("=== カメラ権限チェック ===")
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        print("現在の権限ステータス: \(status.rawValue)")

        switch status {
        case .authorized:
            print("✅ カメラ権限が許可されています")
            isAuthorized = true
            setupCamera()
        case .notDetermined:
            print("⚠️ カメラ権限が未決定、リクエスト中...")
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                print(granted ? "✅ カメラ権限が許可されました" : "❌ カメラ権限が拒否されました")
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted {
                        self?.setupCamera()
                    } else {
                        self?.errorMessage = "カメラへのアクセスが拒否されました"
                    }
                }
            }
        case .denied:
            print("❌ カメラ権限が拒否されています")
            isAuthorized = false
            errorMessage = "カメラへのアクセスが拒否されています。設定から許可してください。"
        case .restricted:
            print("❌ カメラ権限が制限されています")
            isAuthorized = false
            errorMessage = "カメラへのアクセスが制限されています"
        @unknown default:
            print("❌ 不明な権限ステータス")
            isAuthorized = false
        }
    }

    private func setupCamera() {
        print("=== カメラセットアップ開始 ===")
        captureSession.beginConfiguration()

        // Set session preset for high resolution
        if captureSession.canSetSessionPreset(.photo) {
            captureSession.sessionPreset = .photo
            print("✅ セッションプリセットを .photo に設定")
        } else {
            print("⚠️ .photo プリセットが利用不可")
        }

        // Get the best camera device (48MP capable)
        guard let device = getBestCameraDevice() else {
            let message = "カメラデバイスが見つかりません。実機で実行していますか？"
            print("❌ \(message)")
            DispatchQueue.main.async {
                self.errorMessage = message
            }
            captureSession.commitConfiguration()
            return
        }

        print("✅ カメラデバイスを選択: \(device.localizedName)")
        currentDevice = device

        do {
            let input = try AVCaptureDeviceInput(device: device)
            print("✅ AVCaptureDeviceInput作成成功")

            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                print("✅ 入力デバイスを追加")
            } else {
                print("❌ 入力デバイスを追加できません")
            }

            if captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)
                print("✅ 写真出力を追加")

                // Enable Apple ProRAW if available
                if photoOutput.isAppleProRAWSupported {
                    photoOutput.isAppleProRAWEnabled = true
                    print("✅ Apple ProRAW有効化")
                } else {
                    print("⚠️ Apple ProRAW非対応")
                }

                // Configure for maximum quality
                photoOutput.maxPhotoQualityPrioritization = .quality
                print("✅ 最高品質設定完了")
            } else {
                print("❌ 写真出力を追加できません")
            }

            captureSession.commitConfiguration()
            print("✅ セッション設定完了")

            // Start session on background thread
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                print("⏳ カメラセッション起動中...")
                self.captureSession.startRunning()
                print("✅ カメラセッション起動完了")

                // Wait a bit for session to stabilize, then mark as ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.isSessionReady = true
                    print("🎉 カメラ準備完了！撮影可能です")
                }
            }

        } catch {
            let message = "カメラの設定に失敗: \(error.localizedDescription)"
            print("❌ \(message)")
            DispatchQueue.main.async {
                self.errorMessage = message
            }
            captureSession.commitConfiguration()
        }
    }

    private func getBestCameraDevice() -> AVCaptureDevice? {
        print("=== カメラデバイスの検索を開始 ===")

        // List all available devices for debugging
        let allDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInDualCamera,
                .builtInWideAngleCamera,
                .builtInUltraWideCamera,
                .builtInTelephotoCamera
            ],
            mediaType: .video,
            position: .unspecified
        ).devices

        print("利用可能なカメラデバイス数: \(allDevices.count)")
        for device in allDevices {
            print("- \(device.localizedName) (\(device.deviceType.rawValue)) - Position: \(device.position.rawValue)")
        }

        // Try to get back camera with specific device types
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInWideAngleCamera
        ]

        for deviceType in deviceTypes {
            if let device = AVCaptureDevice.default(deviceType, for: .video, position: .back) {
                print("✅ カメラデバイスを検出: \(device.localizedName) (\(deviceType.rawValue))")
                return device
            } else {
                print("❌ \(deviceType.rawValue) は利用不可")
            }
        }

        // Fallback 1: Try to get any back camera
        print("フォールバック1: 任意のバックカメラを検索")
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            print("✅ バックカメラを検出: \(device.localizedName)")
            return device
        }

        // Fallback 2: Use discovery session for back cameras
        print("フォールバック2: ディスカバリーセッションで検索")
        let backCameras = allDevices.filter { $0.position == .back }
        if let device = backCameras.first {
            print("✅ ディスカバリーセッションでカメラを検出: \(device.localizedName)")
            return device
        }

        // Fallback 3: Use ANY camera (including front)
        print("フォールバック3: フロントカメラも含めて検索")
        if let device = allDevices.first {
            print("⚠️ フロントカメラを使用: \(device.localizedName)")
            return device
        }

        // Last resort: default video device
        print("フォールバック4: デフォルトビデオデバイス")
        if let device = AVCaptureDevice.default(for: .video) {
            print("✅ デフォルトビデオデバイスを検出: \(device.localizedName)")
            return device
        }

        print("❌❌❌ エラー: カメラデバイスが見つかりません ❌❌❌")
        return nil
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

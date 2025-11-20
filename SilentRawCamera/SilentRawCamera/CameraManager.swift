import AVFoundation
import Photos
import UIKit
import CoreMotion
import CoreLocation

class CameraManager: NSObject, ObservableObject {
    @Published var isAuthorized = false
    @Published var capturedImage: UIImage?
    @Published var errorMessage: String?
    @Published var isSessionReady = false
    @Published var captureMode: CaptureMode = .highRes

    enum CaptureMode {
        case highRes // 48MP, Shutter Sound
        case silent  // 12MP, No Sound
    }

    private let captureSession = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private var videoOutput = AVCaptureVideoDataOutput()
    private var currentDevice: AVCaptureDevice?
    private let audioSession = AVAudioSession.sharedInstance()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var silentAudioPlayer: AVAudioPlayer?
    private var lastSampleBuffer: CMSampleBuffer?
    private let videoQueue = DispatchQueue(label: "com.silentrawcamera.videoQueue")
    private let motionManager = CMMotionManager()
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    
    // Capture State
    private var tempRawData: Data?
    private var tempProcessedData: Data?
    private var isCapturingRawAndProcessed = false

    override init() {
        super.init()
        configureSilentAudioSession()
        setupSilentAudioPlayer()
        setupLocationManager()
        checkAuthorization()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    private func setupSilentAudioPlayer() {
        // Create a proper WAV file in temp directory
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("silent.wav")
        
        // WAV Header (44 bytes) + 1 second of silence
        // It's easier to just use AudioFile APIs or just create a dummy file if we can,
        // but writing raw bytes for a valid WAV is reliable.
        // Alternatively, we can just try to play a system sound or use a simpler approach.
        // Let's try writing a minimal valid WAV header.
        
        let sampleRate: Int32 = 44100
        let duration: Int32 = 1 // seconds
        let dataSize: Int32 = sampleRate * duration * 2 // 16-bit mono
        let fileSize: Int32 = 36 + dataSize
        
        var header = Data()
        
        // RIFF chunk
        header.append(contentsOf: "RIFF".utf8)
        header.append(withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        header.append(contentsOf: "WAVE".utf8)
        
        // fmt chunk
        header.append(contentsOf: "fmt ".utf8)
        header.append(withUnsafeBytes(of: Int32(16).littleEndian) { Data($0) }) // Chunk size
        header.append(withUnsafeBytes(of: Int16(1).littleEndian) { Data($0) }) // PCM
        header.append(withUnsafeBytes(of: Int16(1).littleEndian) { Data($0) }) // Mono
        header.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) }) // Sample rate
        header.append(withUnsafeBytes(of: (sampleRate * 2).littleEndian) { Data($0) }) // Byte rate
        header.append(withUnsafeBytes(of: Int16(2).littleEndian) { Data($0) }) // Block align
        header.append(withUnsafeBytes(of: Int16(16).littleEndian) { Data($0) }) // Bits per sample
        
        // data chunk
        header.append(contentsOf: "data".utf8)
        header.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        
        // Silence data
        let silence = Data(count: Int(dataSize))
        
        do {
            var fileData = header
            fileData.append(silence)
            try fileData.write(to: fileURL)
            
            silentAudioPlayer = try AVAudioPlayer(contentsOf: fileURL)
            silentAudioPlayer?.numberOfLoops = -1 // Loop indefinitely
            silentAudioPlayer?.volume = 0.02 // Slightly higher volume to ensure system recognition
            silentAudioPlayer?.prepareToPlay()
            silentAudioPlayer?.play()
            print("✅ サイレントオーディオプレーヤー開始 (Vol: 0.02)")
        } catch {
            print("❌ サイレントオーディオプレーヤー作成失敗: \(error)")
        }
    }

    private func configureSilentAudioSession() {
        do {
            // Configure audio session to suppress shutter sound
            // Use .playback to avoid "recording" state which enforces shutter sound
            try audioSession.setCategory(.playback, options: [.mixWithOthers, .duckOthers])
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

        // Set session preset to inputPriority to allow custom formats (48MP)
        if captureSession.canSetSessionPreset(.inputPriority) {
            captureSession.sessionPreset = .inputPriority
            print("✅ セッションプリセットを .inputPriority に設定")
        } else {
            // Fallback to photo if inputPriority not available (older iOS)
            captureSession.sessionPreset = .photo
            print("⚠️ .inputPriority 非対応 -> .photo を使用")
        }

        // Get the best camera device (48MP capable)

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

        // Explicitly configure the best format (48MP) BEFORE adding inputs
        // This ensures the device is in the right mode before the session tries to negotiate presets
        configureBestFormat(for: device)

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

                // Configure for maximum quality
                photoOutput.maxPhotoQualityPrioritization = .quality
                photoOutput.isHighResolutionCaptureEnabled = true // Enable 48MP
                
                if photoOutput.isAppleProRAWSupported {
                    photoOutput.isAppleProRAWEnabled = true
                    print("✅ Apple ProRAW を有効化")
                }

                
                // CRITICAL: Set photoOutput.maxPhotoDimensions to 48MP
                if let format = currentDevice?.activeFormat {
                    if #available(iOS 16.0, *) {
                        let maxDims = format.supportedMaxPhotoDimensions
                        if let highestDim = maxDims.max(by: { $0.width * $0.height < $1.width * $1.height }) {
                            photoOutput.maxPhotoDimensions = highestDim
                            print("✅ PhotoOutput最大解像度設定: \(highestDim.width)x\(highestDim.height)")
                        }
                    }
                }
                
                print("✅ 最高品質・高解像度設定完了")

            } else {
                print("❌ 写真出力を追加できません")
            }

            // Add Video Output for Silent Mode
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
                
                // Request high resolution for video output
                // Note: kCVPixelBufferPixelFormatTypeKey is required.
                // We try to request 4K (3840x2160) or highest available.
                // However, exact dimensions might fail if not supported by the active format.
                // Safest is to just set the pixel format and let the session preset determine size,
                // BUT sessionPreset .photo might give small video frames.
                // Let's try to rely on the format we are about to set in configureBestFormat.
                
                videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
                ]
                
                videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
                videoOutput.alwaysDiscardsLateVideoFrames = true
                print("✅ ビデオ出力を追加 (サイレント用)")
            } else {
                print("❌ ビデオ出力を追加できません")
            }

            // Configure the best format (48MP) NOW, after all connections are made
            // configureBestFormat(for: device) // Moved to top
            
            captureSession.commitConfiguration()
            print("✅ セッション設定完了")

            // Create preview layer once
            let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.videoGravity = .resizeAspectFill
            self.previewLayer = previewLayer

            // Start session on background thread
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                print("⏳ カメラセッション起動中...")
                self.captureSession.startRunning()
                print("✅ カメラセッション起動完了")

                // Mark as ready immediately
                DispatchQueue.main.async {
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
        // Prioritize builtInWideAngleCamera (Main) for 48MP
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera, // Main Camera (often 48MP)
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera
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

    private func configureBestFormat(for device: AVCaptureDevice) {
        // IMPORTANT: Store device reference first
        currentDevice = device
        print("✅ カメラデバイスを選択: \(device.localizedName)")
        
        // Reduced logging for faster startup
        var bestFormat: AVCaptureDevice.Format?
        var maxPixels: Int32 = 0
        var bestVideoPixels: Int32 = 0

        for (_, format) in device.formats.enumerated() {
            let dim = format.highResolutionStillImageDimensions
            let videoDim = format.formatDescription.dimensions
            
            // Check for 48MP support (iOS 16+)
            var is48MP = false
            if #available(iOS 16.0, *) {
                for supportedDim in format.supportedMaxPhotoDimensions {
                    if supportedDim.width > 8000 {
                        is48MP = true
                        break
                    }
                }
            }
            
            let photoPixels = dim.width * dim.height
            let videoPixels = videoDim.width * videoDim.height
            
            // Selection Logic (silent, no logging per format)
            var isBetter = false
            
            if is48MP {
                if let currentBest = bestFormat {
                    var currentIs48MP = false
                    if #available(iOS 16.0, *) {
                        for d in currentBest.supportedMaxPhotoDimensions {
                            if d.width > 8000 { currentIs48MP = true; break }
                        }
                    }
                    
                    if !currentIs48MP {
                        isBetter = true
                    } else {
                        if videoPixels > bestVideoPixels {
                            isBetter = true
                        }
                    }
                } else {
                    isBetter = true
                }
            } else {
                if let currentBest = bestFormat {
                    var currentIs48MP = false
                    if #available(iOS 16.0, *) {
                        for d in currentBest.supportedMaxPhotoDimensions {
                            if d.width > 8000 { currentIs48MP = true; break }
                        }
                    }
                    
                    if !currentIs48MP {
                        if photoPixels > maxPixels {
                            isBetter = true
                        } else if photoPixels == maxPixels {
                            if videoPixels > bestVideoPixels {
                                isBetter = true
                            }
                        }
                    }
                } else {
                    isBetter = true
                }
            }
            
            if isBetter {
                bestFormat = format
                maxPixels = photoPixels
                bestVideoPixels = videoPixels
            }
        }

        if let bestFormat = bestFormat {
            do {
                try device.lockForConfiguration()
                device.activeFormat = bestFormat
                
                let dim = bestFormat.highResolutionStillImageDimensions
                print("✅ フォーマットを強制設定: \(dim.width)x\(dim.height)")
                
                if #available(iOS 16.0, *) {
                    let maxDims = bestFormat.supportedMaxPhotoDimensions
                    print("   -> サポートされる最大撮影解像度: \(maxDims.map { "\($0.width)x\($0.height)" })")
                }
                
                let videoDim = bestFormat.formatDescription.dimensions
                print("📹 このフォーマットのビデオ解像度: \(videoDim.width)x\(videoDim.height)")
                
                device.unlockForConfiguration()
            } catch {
                print("❌ フォーマット設定失敗: \(error)")
            }
        } else {
            print("⚠️ 最適なフォーマットが見つかりませんでした")
        }
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

        if captureMode == .silent {
            captureSilentPhoto()
        } else {
            captureHighResPhoto()
        }
    }

    private func captureSilentPhoto() {
        print("🤫 サイレント撮影開始")
        guard let sampleBuffer = lastSampleBuffer else {
            print("❌ バッファがありません")
            DispatchQueue.main.async {
                self.errorMessage = "画像の取得に失敗しました"
            }
            return
        }
        
        // Log buffer size
        if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let width = CVPixelBufferGetWidth(imageBuffer)
            let height = CVPixelBufferGetHeight(imageBuffer)
            print("📹 サイレント撮影バッファサイズ: \(width)x\(height)")
        }

        // Convert CMSampleBuffer to UIImage
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        
        // Get device orientation for correct image orientation
        let deviceOrientation = UIDevice.current.orientation
        let imageOrientation: UIImage.Orientation
        
        switch deviceOrientation {
        case .portrait:
            imageOrientation = .right
        case .portraitUpsideDown:
            imageOrientation = .left
        case .landscapeLeft:
            imageOrientation = .up
        case .landscapeRight:
            imageOrientation = .down
        default:
            imageOrientation = .right // Default to portrait
        }
        
        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: imageOrientation)
            
            // Save to library (on background thread to not block UI)
            DispatchQueue.global(qos: .userInitiated).async {
                if let data = image.jpegData(compressionQuality: 1.0) {
                    self.savePhotoToLibrary(imageData: data, isRaw: false, location: self.currentLocation)
                }
            }
            
            DispatchQueue.main.async {
                self.capturedImage = image
                
                // Haptic feedback for silent capture
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                
                // Auto-dismiss after 0.5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.capturedImage = nil
                }
            }
        }
    }

    private func captureHighResPhoto() {
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
            try audioSession.setCategory(.playback, options: [.mixWithOthers, .duckOthers])
            try audioSession.setActive(true)
        } catch {
            print("撮影前のオーディオセッション設定に失敗: \(error.localizedDescription)")
        }

        // Log current format dimensions
        // Log current format dimensions
        if let format = currentDevice?.activeFormat {
            let dim = format.highResolutionStillImageDimensions
            print("📸 撮影時のフォーマット解像度(Binning): \(dim.width)x\(dim.height)")
        }
        
        // Log max photo dimensions from output
        let maxDim = photoOutput.maxPhotoDimensions
        print("🚀 PhotoOutput MaxDimensions: \(maxDim.width)x\(maxDim.height)")

        var settings: AVCapturePhotoSettings

        // Enable Apple ProRAW if supported - capture BOTH RAW and JPEG for instant preview
        if photoOutput.isAppleProRAWSupported {
            if let rawFormat = photoOutput.availableRawPhotoPixelFormatTypes.first {
                // Use rawPixelFormatType + processedFormat to get both RAW and JPEG
                settings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat, processedFormat: [
                    AVVideoCodecKey: AVVideoCodecType.hevc  // HEVC for smaller file size
                ])
            } else {
                settings = AVCapturePhotoSettings()
            }
        } else {
            settings = AVCapturePhotoSettings()
        }

        // CRITICAL: Force 48MP by getting it from the active format's supportedMaxPhotoDimensions
        // photoOutput.maxPhotoDimensions is often stuck at 12MP, so we need to set it explicitly
        if let format = currentDevice?.activeFormat {
            if #available(iOS 16.0, *) {
                // Find the 48MP dimensions from supportedMaxPhotoDimensions
                let maxDims = format.supportedMaxPhotoDimensions
                if let highestDim = maxDims.max(by: { $0.width * $0.height < $1.width * $1.height }) {
                    settings.maxPhotoDimensions = highestDim
                    print("✅ 撮影解像度を明示的に設定: \(highestDim.width)x\(highestDim.height)")
                } else {
                    settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
                }
            } else {
                settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
            }
        } else {
            settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        }

        // Silent shutter - disable flash
        settings.flashMode = .off

        // Debug: Log what we're capturing
        print("📸 キャプチャ設定:")
        print("  - RAW Pixel Format: \(settings.rawPhotoPixelFormatType)")
        if let fileType = settings.processedFileType {
            print("  - Processed Format: \(fileType.rawValue)")
        }
        print("  - Max Dimensions: \(settings.maxPhotoDimensions.width)x\(settings.maxPhotoDimensions.height)")

        // Reset temp storage
        tempRawData = nil
        tempProcessedData = nil
        isCapturingRawAndProcessed = settings.rawPhotoPixelFormatType != 0 && settings.processedFileType != nil
        
        print("撮影開始 (RAW+Processed: \(isCapturingRawAndProcessed))")
        // Capture without shutter sound
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func getPreviewLayer() -> AVCaptureVideoPreviewLayer {
        if let layer = previewLayer {
            return layer
        }
        // Fallback if not ready (shouldn't happen if authorized)
        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        self.previewLayer = layer
        return layer
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        lastSampleBuffer = sampleBuffer
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

        // Determine photo type and buffer data
        if photo.isRawPhoto {
            tempRawData = photo.fileDataRepresentation()
            print("📥 RAWデータ受信: \(tempRawData?.count ?? 0) bytes")
        } else {
            tempProcessedData = photo.fileDataRepresentation()
            print("📥 処理済みデータ受信: \(tempProcessedData?.count ?? 0) bytes")
        }
        
        // Check if we are ready to save
        if isCapturingRawAndProcessed {
            // We need both
            if let raw = tempRawData, let processed = tempProcessedData {
                print("📦 RAWと処理済みデータが揃いました。保存します。")
                DispatchQueue.global(qos: .userInitiated).async {
                    self.savePhotoToLibrary(rawData: raw, processedData: processed, location: self.currentLocation)
                }
                // Reset
                tempRawData = nil
                tempProcessedData = nil
                isCapturingRawAndProcessed = false
            } else {
                print("⏳ データ待ち... (RAW: \(tempRawData != nil), Processed: \(tempProcessedData != nil))")
            }
        } else {
            // Single format capture (e.g. just JPEG or just RAW - though we force both for 48MP)
            // Or if one failed?
            // For now, if we are not expecting both, save immediately
            if let data = photo.fileDataRepresentation() {
                 DispatchQueue.global(qos: .userInitiated).async {
                     // Determine if it's RAW or Processed based on photo object
                     if photo.isRawPhoto {
                         self.savePhotoToLibrary(rawData: data, processedData: nil, location: self.currentLocation)
                     } else {
                         self.savePhotoToLibrary(rawData: nil, processedData: data, location: self.currentLocation)
                     }
                 }
            }
        }

        // Update preview image (JPEG only, RAW doesn't preview well with UIImage)
        if let data = photo.fileDataRepresentation(), let image = UIImage(data: data) {
            DispatchQueue.main.async {
                self.capturedImage = image
                
                // Auto-dismiss after 0.5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.capturedImage = nil
                }
            }
        }
    }

    
    
    private func savePhotoToLibrary(rawData: Data?, processedData: Data?, location: CLLocation?) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async {
                    self.errorMessage = "写真ライブラリへのアクセスが許可されていません"
                }
                return
            }

            PHPhotoLibrary.shared().performChanges({
                let creationRequest = PHAssetCreationRequest.forAsset()
                
                // Strategy:
                // If we have both, add Processed as main .photo, and RAW as .alternatePhoto (or vice versa depending on desired behavior)
                // Standard behavior: Add HEIC as .photo, RAW as .alternatePhoto with DNG identifier
                
                if let processed = processedData {
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = true
                    creationRequest.addResource(with: .photo, data: processed, options: options)
                }
                
                if let raw = rawData {
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = true
                    // If we also have processed data, RAW is alternate. If ONLY RAW, it's .photo (but we usually have processed)
                    let type: PHAssetResourceType = processedData != nil ? .alternatePhoto : .photo
                    creationRequest.addResource(with: type, data: raw, options: options)
                }
                
                // Add location if available
                if let location = location {
                    creationRequest.location = location
                }

            }) { success, error in
                DispatchQueue.main.async {
                    if success {
                        self.errorMessage = nil
                        print("✅ 写真を保存しました (Combined Asset)")
                    } else if let error = error {
                        self.errorMessage = "保存エラー: \(error.localizedDescription)"
                        print("❌ 保存エラー: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    // Silent mode JPEG save
    private func savePhotoToLibrary(imageData: Data, isRaw: Bool, location: CLLocation?) {
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
                    // Save as RAW (DNG) - simply use .photo, iOS handles it correctly
                    creationRequest.addResource(with: .photo, data: imageData, options: nil)
                } else {
                    // Save as JPEG
                    creationRequest.addResource(with: .photo, data: imageData, options: nil)
                }
                
                // Add location if available
                if let location = location {
                    creationRequest.location = location
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

extension CameraManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }
}

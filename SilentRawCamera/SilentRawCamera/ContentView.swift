import SwiftUI

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()

    var body: some View {
        ZStack {
            // Camera preview
            if cameraManager.isAuthorized {
                CameraPreview(previewLayer: cameraManager.getPreviewLayer())
                    .edgesIgnoringSafeArea(.all)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)

                    Text("カメラへのアクセスを許可してください")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding()

                    Button("設定を開く") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .padding()
            }

            // Image preview overlay (full screen, no buttons)
            // Image preview overlay (full screen, no buttons)
            if let image = cameraManager.capturedImage {
                GeometryReader { geometry in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
                .edgesIgnoringSafeArea(.all)
            }

            // Camera controls overlay (hidden when showing preview)
            if cameraManager.capturedImage == nil {
                VStack {
                    // Top bar - info display
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            // Mode Toggle
                            Picker("Mode", selection: $cameraManager.captureMode) {
                                Text("高画質 (48MP)").tag(CameraManager.CaptureMode.highRes)
                                Text("無音 (12MP)").tag(CameraManager.CaptureMode.silent)
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .frame(width: 200)
                            .padding(.bottom, 8)

                            if cameraManager.captureMode == .highRes {
                                Text("📸 48MP RAW (音あり)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .padding(8)
                                    .background(Color.black.opacity(0.6))
                                    .foregroundColor(.yellow)
                                    .cornerRadius(8)
                            } else {
                                Text("🤫 完全無音 (12MP)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .padding(8)
                                    .background(Color.black.opacity(0.6))
                                    .foregroundColor(.green)
                                    .cornerRadius(8)
                            }
                        }
                        .padding()

                        Spacer()
                    }

                    Spacer()

                    // Bottom bar - capture button
                    VStack(spacing: 20) {
                        // Status messages
                        if !cameraManager.isSessionReady && cameraManager.isAuthorized {
                            Text("カメラ準備中...")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.blue.opacity(0.8))
                                .cornerRadius(10)
                                .padding(.horizontal)
                        }

                        // Error message
                        if let errorMessage = cameraManager.errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.red.opacity(0.8))
                                .cornerRadius(10)
                                .padding(.horizontal)
                        }

                        // Capture button
                        Button(action: {
                            cameraManager.capturePhoto()
                        }) {
                            ZStack {
                                Circle()
                                    .fill(cameraManager.isSessionReady ? Color.white : Color.gray)
                                    .frame(width: 70, height: 70)

                                Circle()
                                    .stroke(cameraManager.isSessionReady ? Color.white : Color.gray, lineWidth: 3)
                                    .frame(width: 85, height: 85)
                            }
                        }
                        .disabled(!cameraManager.isSessionReady)
                        .opacity(cameraManager.isSessionReady ? 1.0 : 0.5)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

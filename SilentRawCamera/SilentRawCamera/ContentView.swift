import SwiftUI

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var showingImagePreview = false

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

            // Camera controls overlay
            VStack {
                // Top bar - info display
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("48MP RAW")
                            .font(.caption)
                            .fontWeight(.bold)
                            .padding(8)
                            .background(Color.black.opacity(0.6))
                            .foregroundColor(.white)
                            .cornerRadius(8)

                        Text("🔇 完全無音")
                            .font(.caption)
                            .fontWeight(.bold)
                            .padding(8)
                            .background(Color.black.opacity(0.6))
                            .foregroundColor(.green)
                            .cornerRadius(8)
                    }
                    .padding()

                    Spacer()
                }

                Spacer()

                // Bottom bar - capture button
                VStack(spacing: 20) {
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
                                .fill(Color.white)
                                .frame(width: 70, height: 70)

                            Circle()
                                .stroke(Color.white, lineWidth: 3)
                                .frame(width: 85, height: 85)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }

            // Image preview overlay
            if let image = cameraManager.capturedImage, showingImagePreview {
                ZStack {
                    Color.black.edgesIgnoringSafeArea(.all)

                    VStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .edgesIgnoringSafeArea(.all)

                        Button("閉じる") {
                            showingImagePreview = false
                            cameraManager.capturedImage = nil
                        }
                        .padding()
                        .background(Color.white)
                        .foregroundColor(.black)
                        .cornerRadius(10)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .onChange(of: cameraManager.capturedImage) { newImage in
            if newImage != nil {
                showingImagePreview = true
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

# Silent RAW Camera - 48MP サイレントRAWカメラ

iPhone用の高品質48MP RAW撮影ができるカメラアプリです。

## 🚀 クイックスタート

**すぐに使いたい方はこちら**: [QUICKSTART.md](QUICKSTART.md) - 5分でiPhoneにインストール

詳しいインストール手順: [INSTALL.md](INSTALL.md)

## 主な機能

- **48MP撮影**: iPhone 14 Pro以降の最大解像度で撮影
- **RAW撮影**: Apple ProRAW形式で高品質な写真を保存
- **サイレント撮影**: 可能な限り静かに撮影（Live Photoモード使用）
- **シンプルなUI**: SwiftUIを使った直感的なインターフェース

## 対応機種

- iPhone 14 Pro / Pro Max
- iPhone 15 Pro / Pro Max
- iPhone 16 Pro / Pro Max
- その他48MPカメラを搭載したiPhoneモデル

## 必要要件

- iOS 17.0以降
- Xcode 15.0以降（開発時）
- 48MPカメラを搭載したiPhone

## インストール方法

1. Xcodeでプロジェクトを開く
```bash
open SilentRawCamera/SilentRawCamera.xcodeproj
```

2. 開発チーム（Development Team）を設定
   - プロジェクト設定 > Signing & Capabilities
   - チームを選択

3. iPhoneデバイスを選択してビルド・実行

## 使い方

1. アプリを起動すると、カメラとフォトライブラリへのアクセス許可を求められます
2. 許可後、カメラプレビューが表示されます
3. 画面下部の白い丸ボタンをタップして撮影
4. 撮影した写真は自動的にフォトライブラリに保存されます

## 技術仕様

### 48MP RAW撮影

- `AVCapturePhotoOutput`を使用してApple ProRAW形式で撮影
- `maxPhotoDimensions`を設定して最大解像度（48MP）で撮影
- DNG形式（Digital Negative）でRAWデータを保存

### サイレント撮影

**重要な注意事項**:
- 日本で販売されているiPhoneは、法律により撮影音を完全に無効にすることはできません
- このアプリでは以下の方法で撮影音を軽減しています：
  - Live Photoモードの使用（シャッター音が小さくなる）
  - フラッシュオフ設定

他の地域で販売されたiPhoneでは、より静かに撮影できる場合があります。

### カメラ設定

```swift
// 最高品質設定
photoOutput.maxPhotoQualityPrioritization = .quality

// Apple ProRAW有効化
if photoOutput.isAppleProRAWSupported {
    photoOutput.isAppleProRAWEnabled = true
}

// 最大解像度設定
settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
```

## ファイル構成

```
SilentRawCamera/
├── SilentRawCamera/
│   ├── SilentRawCameraApp.swift    # アプリエントリーポイント
│   ├── ContentView.swift            # メインUI
│   ├── CameraManager.swift          # カメラ制御ロジック
│   ├── CameraPreview.swift          # カメラプレビューUI
│   └── Info.plist                   # アプリ設定・権限
└── SilentRawCamera.xcodeproj/       # Xcodeプロジェクト
```

## プライバシー設定

Info.plistに以下の権限が設定されています：

- `NSCameraUsageDescription`: カメラアクセス
- `NSPhotoLibraryAddUsageDescription`: 写真保存
- `NSPhotoLibraryUsageDescription`: フォトライブラリアクセス

## トラブルシューティング

### 48MPで撮影できない

- iPhone 14 Pro以降の対応機種を使用していることを確認
- カメラアプリの設定で「Apple ProRAW」が有効になっていることを確認
- デバイスのストレージ容量を確認（RAWファイルは大きいです）

### シャッター音が鳴る

- 日本版iPhoneでは法律により常に音が鳴ります
- Live Photoモードにより音量は軽減されています

### カメラが起動しない

- アプリにカメラアクセス許可を与えたか確認
- 設定 > プライバシーとセキュリティ > カメラ で確認

## ライセンス

このプロジェクトはオープンソースです。

## 作成者

Claude AI

## 更新履歴

- v1.0 (2025-11-08): 初回リリース
  - 48MP RAW撮影機能
  - サイレント撮影モード（Live Photo使用）
  - SwiftUI UI実装

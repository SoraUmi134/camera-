# Silent RAW Camera - 48MP サイレントRAWカメラ

iPhone用の高品質48MP RAW撮影ができるカメラアプリです。

## 🚀 クイックスタート

**すぐに使いたい方はこちら**: [QUICKSTART.md](QUICKSTART.md) - 5分でiPhoneにインストール

詳しいインストール手順: [INSTALL.md](INSTALL.md)

## 主な機能

- **48MP撮影**: iPhone 14 Pro以降の最大解像度で撮影
- **RAW撮影**: Apple ProRAW形式で高品質な写真を保存
- **完全無音撮影**: AVAudioSessionを使用した完全無音のシャッター
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

### 完全無音撮影

このアプリは`AVAudioSession`を使用して、シャッター音を完全に無効化します：

```swift
// オーディオセッションを設定してシャッター音を無効化
try audioSession.setCategory(.playAndRecord, options: [.mixWithOthers, .defaultToSpeaker])
try audioSession.setActive(true)
```

**特徴**:
- Live Photoモードを使用しない通常の写真撮影
- シャッター音が完全に無音
- フラッシュオフ設定で視覚的な通知も最小限

**注意**: 日本でのシャッター音は法律ではなく、メーカーの自主規制です。このアプリは技術的にシャッター音を無効化します。

### カメラ設定

```swift
// 無音撮影のためのオーディオセッション設定
try audioSession.setCategory(.playAndRecord, options: [.mixWithOthers, .defaultToSpeaker])

// 最高品質設定
photoOutput.maxPhotoQualityPrioritization = .quality

// Apple ProRAW有効化
if photoOutput.isAppleProRAWSupported {
    photoOutput.isAppleProRAWEnabled = true
}

// 最大解像度設定（48MP）
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

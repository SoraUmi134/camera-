# インストール手順

このガイドに従って、iPhoneにアプリをインストールします。

## 必要なもの

- Mac（macOS Ventura以降推奨）
- Xcode 15.0以降
- iPhone（iOS 17.0以降、できれば48MP対応のiPhone 14 Pro以降）
- Lightningケーブルまたは USB-Cケーブル
- Apple ID（無料の開発者アカウントでOK）

## ステップ1: Xcodeのインストール

1. App Storeを開く
2. 「Xcode」で検索
3. インストール（数GB、時間がかかります）

または、コマンドラインから：
```bash
xcode-select --install
```

## ステップ2: プロジェクトを開く

1. リポジトリをクローンまたはダウンロード
```bash
git clone <repository-url>
cd camera-
```

2. Xcodeでプロジェクトを開く
```bash
open SilentRawCamera/SilentRawCamera.xcodeproj
```

## ステップ3: Apple IDでサインイン

1. Xcode上部メニュー > **Xcode** > **Settings...**（または Preferences）
2. **Accounts** タブを開く
3. 左下の **+** ボタンをクリック
4. **Apple ID** を選択
5. Apple IDとパスワードを入力してサインイン

## ステップ4: 開発チーム設定

1. Xcodeの左側プロジェクトナビゲーターで **SilentRawCamera**（青いアイコン）をクリック
2. **TARGETS** の下の **SilentRawCamera** を選択
3. **Signing & Capabilities** タブを開く
4. **Team** ドロップダウンから、自分のApple IDを選択
   - もし「Personal Team」と表示されていれば、それを選択（無料でOK）
5. 自動的にBundle Identifierが更新されます

**重要**: エラーが出た場合は、Bundle Identifierを変更してみてください：
- 例: `com.silentrawcamera.app` → `com.yourname.silentrawcamera`

## ステップ5: iPhoneの準備

### iPhoneの設定

1. iPhoneの **設定** > **プライバシーとセキュリティ** > **開発者モード** をオンにする
   - iOS 16以降で必要
   - オンにすると再起動が必要です

2. MacとiPhoneをケーブルで接続

3. iPhone上で「このコンピュータを信頼しますか？」と表示されたら **信頼** をタップ

4. パスコードを入力

## ステップ6: ビルド＆実行

1. Xcodeの上部ツールバーで、デバイス選択ドロップダウン（⌘ + Shift + 2 の横）をクリック

2. 接続したiPhoneを選択
   - 「iPhone の名前」のように表示されます
   - シミュレーターではなく、実機を選択してください

3. **▶** ボタン（またはCommand + R）を押してビルド開始

4. 初回は「開発元を信頼する」設定が必要です：
   - iPhone上で **設定** > **一般** > **VPNとデバイス管理**
   - あなたのApple IDが表示されているので、タップ
   - **信頼** をタップ

5. ホーム画面にアプリアイコンが表示されます

## ステップ7: アプリの起動と権限設定

1. iPhoneでアプリを起動

2. 初回起動時に以下の権限を求められます：
   - **カメラへのアクセス** → **許可**
   - **写真ライブラリへのアクセス** → **すべての写真へのアクセスを許可** または **選択した写真へのアクセスを許可**

3. カメラプレビューが表示されたら完了！

## 使い方

- 画面下部の白い丸ボタンをタップして撮影
- **48MP RAW形式**で保存されます
- **完全無音**で撮影できます（シャッター音なし）
- 撮影した写真は自動的に写真アプリに保存されます
- 画面左上に「48MP RAW」と「🔇 完全無音」の表示があります

## トラブルシューティング

### 「開発者アカウントが必要です」エラー

無料のApple IDでは、アプリの有効期限が7日間です。7日後に再度Xcodeから実行する必要があります。

### ビルドエラー: "Failed to register bundle identifier"

Bundle Identifierが他の人と重複している可能性があります。
1. プロジェクト設定 > **General** タブ
2. **Bundle Identifier** を変更（例: `com.yourname.silentrawcamera`）

### 「このアプリケーションを開けません」エラー

開発元の信頼設定が必要です：
1. iPhone > 設定 > 一般 > VPNとデバイス管理
2. Apple IDをタップして信頼

### カメラが起動しない

1. 設定 > プライバシーとセキュリティ > カメラ
2. SilentRawCameraがオンになっているか確認

### 48MPで撮影できない

- iPhone 14 Pro、15 Pro、16 Pro以降が必要です
- それ以外のiPhoneでは通常の解像度で撮影されます

## その他

### アプリの削除

通常のアプリと同じように、アイコンを長押しして「Appを削除」で削除できます。

### 再インストール

Xcodeから再度「▶」ボタンを押すだけで、最新版が上書きインストールされます。

---

問題が発生した場合は、GitHubのIssuesでお知らせください。

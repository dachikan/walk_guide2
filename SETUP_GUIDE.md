# Walk Guide 2 セットアップガイド

## 目次
1. [GitHub リポジトリ作成](#1-github-リポジトリ作成)
2. [Google Maps API キー取得](#2-google-maps-api-キー取得)
3. [開発環境のセットアップ](#3-開発環境のセットアップ)

---

## 1. GitHub リポジトリ作成

### 前提条件
- GitHub アカウントを持っていること
- Git がインストールされていること
- GitHub CLI (`gh`) がインストールされていること（推奨）

### 方法A: GitHub CLI を使う（推奨）

```powershell
# プロジェクトフォルダに移動
cd C:\Users\Express580053xguser\Dropbox\31Develop\walk_guide2

# Git 初期化（まだの場合）
git init

# .gitignore を確認（Flutter プロジェクトの標準的な .gitignore が必要）
# すでに存在するはずですが、なければ作成

# 全ファイルをステージング
git add .

# 初回コミット
git commit -m "Initial commit: GPS route navigation app for visually impaired"

# GitHub にリポジトリを作成してプッシュ
gh repo create walk_guide2 --public --source=. --push
```

### 方法B: GitHub Web サイトを使う

1. **GitHub にログイン**
   - https://github.com にアクセス

2. **新規リポジトリ作成**
   - 右上の「+」→「New repository」をクリック
   - Repository name: `walk_guide2`
   - Description: `GPS route navigation app for visually impaired users`
   - Public/Private を選択
   - 「Create repository」をクリック

3. **ローカルプロジェクトをプッシュ**
   ```powershell
   cd C:\Users\Express580053xguser\Dropbox\31Develop\walk_guide2
   
   # Git 初期化
   git init
   
   # リモートリポジトリを追加（YOUR_USERNAME を置き換え）
   git remote add origin https://github.com/YOUR_USERNAME/walk_guide2.git
   
   # ファイルをコミット
   git add .
   git commit -m "Initial commit: GPS route navigation app"
   
   # プッシュ
   git branch -M main
   git push -u origin main
   ```

### .gitignore の確認

Flutter プロジェクトには以下が `.gitignore` に含まれているべきです：

```gitignore
# Flutter/Dart
.dart_tool/
.flutter-plugins
.flutter-plugins-dependencies
.packages
.pub-cache/
.pub/
build/
pubspec.lock

# Android
*.iml
.gradle
local.properties
.idea/
*.jks
*.keystore

# iOS
*.pbxuser
*.mode1v3
*.mode2v3
*.perspectivev3
xcuserdata/
*.xccheckout
*.moved-aside
DerivedData/
*.hmap
*.ipa
*.xcworkspace

# 個人設定・API キー
.env
.env.local
android/key.properties
google-services.json
GoogleService-Info.plist
```

---

## 2. Google Maps API キー取得

### ステップ1: Google Cloud Console にアクセス

1. [Google Cloud Console](https://console.cloud.google.com/) にアクセス
2. Google アカウントでログイン

### ステップ2: プロジェクトを作成

1. 上部のプロジェクト選択ドロップダウンをクリック
2. 「新しいプロジェクト」を選択
3. プロジェクト名: `walk-guide-2` (任意)
4. 「作成」をクリック
5. プロジェクトが作成されたら選択

### ステップ3: Maps SDK for Android を有効化

1. 左側メニューから「APIとサービス」→「ライブラリ」を選択
2. 検索バーで「Maps SDK for Android」を検索
3. 「Maps SDK for Android」をクリック
4. 「有効にする」をクリック

### ステップ4: API キーを作成

1. 左側メニューから「認証情報」を選択
2. 上部の「認証情報を作成」→「API キー」をクリック
3. API キーが生成されます（例: `AIzaSyXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX`）
4. **このキーをコピーして安全な場所に保存**

### ステップ5: API キーに制限を設定（推奨）

1. 作成された API キーの「編集」（鉛筆アイコン）をクリック
2. 「アプリケーションの制限」セクション:
   - 「Android アプリ」を選択
   - 「項目を追加」をクリック
   - パッケージ名: `com.example.walk_guide2`
   - SHA-1 証明書フィンガープリント: （後で追加可能）
3. 「API の制限」セクション:
   - 「キーを制限」を選択
   - 「Maps SDK for Android」にチェック
4. 「保存」をクリック

### ステップ6: API キーをアプリに設定

1. ファイルを開く:
   ```
   android/app/src/main/AndroidManifest.xml
   ```

2. 31行目付近を編集:
   ```xml
   <meta-data
       android:name="com.google.android.geo.API_KEY"
       android:value="YOUR_API_KEY_HERE"/>
   ```
   ↓
   ```xml
   <meta-data
       android:name="com.google.android.geo.API_KEY"
       android:value="AIzaSyXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"/>
   ```

3. ファイルを保存

### ⚠️ セキュリティ注意事項

- **API キーをコミットしない**: `.gitignore` に含めるか、環境変数で管理
- **本番環境では必ず制限を設定**: 無制限のキーは不正利用のリスクあり
- **定期的にキーをローテーション**: セキュリティのため

### API キーを秘密にする方法（オプション）

#### 方法1: local.properties を使う

1. `android/local.properties` に追加:
   ```properties
   MAPS_API_KEY=AIzaSyXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
   ```

2. `android/app/build.gradle` を編集:
   ```gradle
   android {
       defaultConfig {
           // ...
           manifestPlaceholders = [MAPS_API_KEY: project.findProperty('MAPS_API_KEY') ?: '']
       }
   }
   ```

3. `AndroidManifest.xml` を編集:
   ```xml
   <meta-data
       android:name="com.google.android.geo.API_KEY"
       android:value="${MAPS_API_KEY}"/>
   ```

4. `.gitignore` に `local.properties` が含まれていることを確認

---

## 3. 開発環境のセットアップ

### Flutter SDK

```powershell
# Flutter バージョン確認
flutter --version

# プロジェクトの依存関係をインストール
cd C:\Users\Express580053xguser\Dropbox\31Develop\walk_guide2
flutter pub get

# デバイスを接続して確認
flutter devices

# アプリをビルド＆実行
flutter run -d DEVICE_ID
```

### Android Studio / VS Code

- **Android Studio**: Flutter プラグインをインストール
- **VS Code**: Flutter 拡張機能をインストール

### 端末接続

```powershell
# USB デバッグを有効化した Android 端末を接続
# デバイス ID を確認
flutter devices

# 特定デバイスで実行
flutter run -d GGXDU17227002711
```

---

## トラブルシューティング

### Google Maps が表示されない

1. API キーが正しく設定されているか確認
2. Maps SDK for Android が有効化されているか確認
3. インターネット接続を確認
4. Logcat でエラーメッセージを確認:
   ```
   adb logcat | grep -i "google\|maps"
   ```

### FlutterCompass が動作しない

- デバイスに方位センサーがない可能性
- 代替案: GPS 移動方向を使用（既存実装）

### 音声案内が停止しない

- アプリを完全に終了（タスクマネージャーから削除）
- デバイスを再起動

---

## 参考リンク

- [Google Maps Platform](https://developers.google.com/maps)
- [Flutter 公式ドキュメント](https://flutter.dev/docs)
- [Geolocator パッケージ](https://pub.dev/packages/geolocator)
- [Flutter TTS パッケージ](https://pub.dev/packages/flutter_tts)

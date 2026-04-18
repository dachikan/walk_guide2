# Walk Guide - 視覚障害者向け歩行介助アプリ

## 概要

視覚障害者の方が安全に歩行できるよう支援するスマホアプリです。以下の2つの主要機能を持ちます：

### 1. AI画像解析による状況案内（ロボット大脳）
- カメラで前方の状況を分析し、音声で案内
- 10秒おきの自動解析
- 短期記憶機能（海馬）で状況変化を検出
- マルチAI対応（Gemini, Claude, ChatGPT）

### 2. **ルートナビゲーション機能（新機能）**
- ✨ App Inventor版RemoteNaviの機能をFlutterで完全再実装
- GPS追跡による地点案内
- 予め登録したルート上の地点に近づくと音声で案内
- 地図上でのルート編集

## 主な機能

### AI画像解析機能
- **音声による状況案内**: 前方の状況を日本語で音声案内（10秒おき）
- **短期記憶機能（海馬）**: 10秒前と現在の画像を比較し、状況の変化を通知
- **マルチAI対応**: Google Gemini, Claude 3.5 Sonnet, ChatGPT (GPT-4o mini) を切替可能
- **音声コマンド認識**: 「景色」「説明」「クロード」「ジェミニ」「GPT」などの音声操作
- **通信エラー詳細通知**: エラー発生時に具体的な原因を説明
- **生存確認ハートビート**: 4秒間隔のバイブレーションでアプリ動作を確認

### ルートナビゲーション機能（新規実装）
- **ルート選択**: 複数のルートから選択してナビゲーション開始
- **GPS追跡**: リアルタイムで現在位置を追跡
- **地点案内**: 各地点に近づくと自動的に音声で案内
- **方位表示**: コンパス表示で進行方向を確認
- **ルート編集**: 地図上で地点の追加・編集・削除
- **CSV形式**: 簡単にルートデータを作成・共有可能

## 使用技術
- **Flutter**: 3.11.0
- **AI**: Gemini 2.5 Flash Lite, Claude 3.5 Sonnet, GPT-4o mini
- **音声**: speech_to_text, flutter_tts
- **位置情報**: geolocator
- **地図**: google_maps_flutter
- **データ**: CSV形式

## ルートナビゲーション機能の使い方

### 1. ルート選択
1. アプリを起動
2. 音声コマンド「ルート」または設定画面から「ルートナビゲーション」を選択
3. 利用可能なルート一覧から選択

### 2. ナビゲーション
- ルート選択後、自動的にGPS追跡開始
- 各地点に近づくと音声で案内
- 画面に表示される情報：
  - 現在の方位（コンパス）
  - 次の地点までの距離
  - 現在位置（緯度・経度）

### 3. 新しいルートの作成

#### 方法1: CSVファイル
`assets/routes/`フォルダにCSVファイルを作成：
```csv
1,35.410191,139.525466,0,10,自宅付近です
2,35.410148,139.525345,0,10,目的地付近です
```

フォーマット：`ID, 緯度, 経度, 方位, 案内距離(m), メッセージ`

#### 方法2: ルート編集画面
- 地図上で地点をタップして追加
- 既存の地点をドラッグして移動
- メッセージと案内距離を編集

## プロジェクト構成

### ルートナビゲーション関連ファイル
```
lib/
├── route_service.dart          # CSV読み込み・保存サービス
├── walk_navi_engine.dart       # ナビゲーションエンジン
├── route_select_screen.dart    # ルート選択画面
├── walk_navi_screen.dart       # ナビゲーション画面
├── route_edit_screen.dart      # ルート編集画面
└── walking_route.dart          # ルートデータモデル

assets/routes/
├── home_route.csv              # 自宅ルート
├── friend_home.csv             # 友人宅ルート
└── express_bus_stop.csv        # 高速バス停ルート
```

## RemoteNavi機能との対応表

| RemoteNavi | Walk Guide | 説明 |
|-----------|-----------|------|
| Screen1 | RouteSelectScreen | ルート選択画面 |
| NaviScreen | WalkNaviScreen | ナビゲーション実行画面 |
| EditScreen | RouteEditScreen | ルート編集画面 |
| CSV読み込み | RouteService | ルートデータ管理 |
| GPS追跡 | WalkNaviEngine | ナビゲーションロジック |
| 音声案内 | FlutterTts統合 | TTSによる案内 |

## バージョン履歴
- **v0.0.12+11** (予定): ルートナビゲーション機能の追加（RemoteNavi完全実装）
- **v0.0.11+10**: GPS地点案内機能の試験実装
- **v0.0.8+1**: 通信エラー詳細通知、マルチAI、短期記憶の実装

## 詳細ドキュメント
- [仕様書 (Spec.md)](Spec.md) - 全体仕様と将来計画
- [開発ルール (DEVELOPMENT_RULES.md)](DEVELOPMENT_RULES.md) - アーキテクチャと開発指針
- **[ルートナビゲーション実装ガイド (ROUTE_NAVIGATION_GUIDE.md)](ROUTE_NAVIGATION_GUIDE.md)** - ルート機能の詳細説明

## インストール・ビルド

### 必要な環境
- Flutter 3.11.0以上
- Android Studio / VS Code
- Android SDK

### セットアップ
1. リポジトリをクローン
2. `.walking_guide.env`ファイルを作成し、APIキーを設定：
   ```
   GEMINI_API_KEY=your_gemini_api_key
   CLAUDE_API_KEY=your_claude_api_key
   OPENAI_API_KEY=your_openai_api_key
   ```
3. 依存関係をインストール：
   ```bash
   flutter pub get
   ```
4. ビルド：
   ```bash
   flutter build apk
   ```

## 今後の開発予定

### 優先度：高
- [ ] AI画像解析とルートナビゲーションの統合
- [ ] ルート逸脱検知
- [ ] クラウド同期

### 優先度：中
- [ ] ルートの共有機能
- [ ] 代替ルート提案
- [ ] 音声コマンドでナビゲーション制御

### 優先度：低
- [ ] 複数言語対応
- [ ] カスタムTTS音声

## ライセンス
このプロジェクトは個人使用を目的としています。

## 謝辞
- App Inventor版RemoteNavi54_1の設計思想を継承
- Flutterエコシステムの各種パッケージ開発者の皆様に感謝

---
**最終更新**: 2026年4月17日  
**開発者**: WalkGuide Development Team

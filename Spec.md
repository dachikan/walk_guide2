# Walk Guide 2 - 視覚障害者向けルートナビゲーションアプリ

## プロジェクト概要

### プロジェクト名
Walk Guide 2 - 視覚障害者のための GPS ルートナビゲーションアプリ

### 目的
視覚障害者が事前に登録されたルートに沿って安全に歩行できるよう、GPS と音声案内で支援するシンプルなナビゲーションアプリです。

### 元プロジェクトとの違い
- **walk_guide**: AI 画像解析による障害物検出（未完成）
- **walk_guide2**: GPS ルートナビゲーション（現プロジェクト・実装済み）

## 技術スタック

### フレームワーク
- Flutter 3.11.0
- Dart SDK ^3.11.0

### 主要パッケージ
- `geolocator: 10.1.0` - GPS 位置追跡
- `flutter_tts: 4.2.2` - 音声案内（日本語TTS）
- `flutter_compass: ^0.8.0` - 方位センサー
- `google_maps_flutter: ^2.2.0` - 地図表示
- `csv: 6.0.0` - ルートデータ読み込み
- `permission_handler: 11.3.1` - 権限管理

### 対象プラットフォーム
- Android 7.0 (API 24) 以上
- テスト端末: HUAWEI CAN L12 (Android 7.0)

## 機能仕様

### ✅ 実装済み機能

#### 1. ルート選択画面
- CSV ファイルから複数ルートを読み込み
- 大きなボタンで視認性向上
- ルート名、地点数、距離を表示

#### 2. GPS ナビゲーション画面
- **リアルタイム位置追跡**
  - GPS 精度: 高精度モード
  - 更新間隔: 1m 移動ごと
  - 緯度・経度表示（5桁精度）
  
- **コンパス表示**
  - 目的地方向を青い矢印で表示
  - 端末の向きに連動して回転
  - 目的地方位と端末向きを度数表示
  
- **次の地点情報**
  - 地点名（メッセージ）を大きく表示
  - 残り距離（メートル）
  - 現在地点 / 全地点数
  
- **音声案内**
  - 15秒間隔で自動音声案内
  - 相対方向と距離を案内
    - 「まっすぐ、10メートル先」
    - 「右へ30度、10メートル先」
    - 「左へ45度、5メートル先」
  - 端末の向き基準で案内（視覚障害者向け）
  
- **ナビゲーション制御**
  - 停止ボタン（確認ダイアログ付き）
  - 地図ボタン（地図画面へ遷移）

#### 3. ルート地図表示画面
- **地図機能**（Google Maps API キー必要）
  - ルート全体をポリラインで表示
  - 地点マーカー
    - 開始地点: 緑
    - 中間地点: 青
    - 終了地点: 赤
  - 現在位置をリアルタイム表示
  
- **操作ボタン**
  - 現在位置へ移動
  - ルート全体を表示

#### 4. ルートデータ管理
- CSV 形式でルートを定義
- フォーマット: `地点番号, 緯度, 経度, 方位, トリガー距離, メッセージ`
- サンプルルート3件同梱
  - home_route.csv
  - friend_home.csv
  - express_bus_stop.csv

### ⚠️ 既知の問題・制限事項

#### 1. 方位センサー（FlutterCompass）
- **問題**: デバイスによっては0度固定になる
- **影響**: コンパスが回転しない、相対方向が正しく計算されない
- **対策**: デバイス依存性あり、代替手段を検討中

#### 2. 音声案内の基準
- **現状**: 端末の向き（`_deviceHeading`）基準
- **課題**: 方位センサーが動作しない場合、移動方向基準にフォールバック必要

#### 3. Google Maps API
- **現状**: AndroidManifest.xml に API キープレースホルダー設定済み
- **必要作業**: 実際の API キーを取得・設定

#### 4. UI オーバーフロー
- **問題**: ホーム画面で39ピクセルのオーバーフロー警告
- **影響**: 視覚的には問題なし
- **対策**: 低優先度（機能には影響なし）

### 🚧 未実装機能

#### 短期計画
- [ ] 方位センサーのフォールバック処理
- [ ] Google Maps API キー設定手順の文書化
- [ ] ルート作成ツール（現状は手動で CSV 編集）
- [ ] バックグラウンド音声案内の改善

#### 中期計画
- [ ] ルート録画機能（実際に歩いて記録）
- [ ] オフライン地図対応
- [ ] カスタム音声案内間隔設定
- [ ] 振動フィードバック

#### 長期計画
- [ ] walk_guide (AI 画像解析) との統合
- [ ] 障害物検出の追加
- [ ] 複数ルート間のナビゲーション

## 画面構成

```
ホーム画面
    ↓ ルート選択ボタン
ルート選択画面
    ↓ ルートタップ
ナビゲーション画面 ← → 地図画面
    ↓ 停止ボタン
ホーム画面
```

### ナビゲーション画面レイアウト
```
┌─────────────────────────────┐
│ home_route      [地図] [×]  │ ← AppBar
├─────────────────────────────┤
│    ナビゲーション中          │ ← ステータス
├─────────────────────────────┤
│                             │
│          ↑                  │ ← コンパス
│       (目的地)              │
│                             │
│    目的地: 166°            │
│    端末向き: 0°            │
│                             │
├─────────────────────────────┤
│ 次の地点                    │
│ 目的地付近です              │ ← メッセージ
│                             │
│ 距離: 9 m    地点 2 / 2    │
├─────────────────────────────┤
│ 緯度: 35.41023             │
│ 経度: 139.52532            │
└─────────────────────────────┘
```

## CSV ルートデータ形式

```csv
地点番号,緯度,経度,方位,トリガー距離,メッセージ
1,35.41234,139.52345,0,10,スタート地点です
2,35.41345,139.52456,90,10,右に曲がります
3,35.41456,139.52567,0,10,目的地付近です
```

## 音声案内ロジック

### 案内タイミング
- 15秒間隔（`Timer.periodic`）
- ナビゲーション画面表示中のみ
- 画面を離れると自動停止（`deactivate`）

### 相対方向計算
```dart
relativeBearing = 目的地方位 - 端末向き
正規化: -180° ~ 180°

if (|relativeBearing| < 15°)  → "まっすぐ"
else if (relativeBearing > 0)  → "右へX度"
else                           → "左へX度"
```

### 音声メッセージ例
- 「まっすぐ、10メートル先」
- 「右へ30度、7メートル先」
- 「左へ120度、15メートル先」

## プログラム構造

### アーキテクチャ概要
Walk Guide 2 は Flutter のシンプルな MVC パターンを採用しています。画面（View）、ビジネスロジック（Engine）、データモデル（Model）、サービス層（Service）が明確に分離されています。

### ファイル構成と役割

```
lib/
├── main.dart                    # アプリエントリポイント
├── walking_route.dart           # データモデル
├── route_service.dart           # CSV読み込みサービス
├── route_select_screen.dart     # ルート選択画面
├── walk_navi_screen.dart        # ナビゲーション画面（View）
├── walk_navi_engine.dart        # GPS追跡エンジン（Logic）
└── route_map_screen.dart        # 地図表示画面
```

#### 1. main.dart
- **役割**: アプリケーションのエントリポイント
- **主要機能**:
  - FlutterTts のグローバルインスタンス初期化
  - MaterialApp の設定
  - ホーム画面の表示
- **依存**: なし
- **公開**: `globalTts`（グローバル TTS インスタンス）

#### 2. walking_route.dart
- **役割**: ナビゲーション用データモデル
- **主要クラス**:
  - `NaviPoint`: 単一の地点情報（緯度、経度、メッセージ、トリガー距離）
  - `WalkRoute`: ルート全体（名前、地点リスト）
- **主要メソッド**:
  - `NaviPoint.distanceTo(Position)`: 現在位置からの距離計算
  - `NaviPoint.bearingTo(Position)`: 現在位置から地点への方位計算
- **依存**: `geolocator`

#### 3. route_service.dart
- **役割**: CSV ファイルからルートデータを読み込むサービス層
- **主要クラス**: `RouteService`
- **主要メソッド**:
  - `static Future<List<WalkRoute>> loadRoutes()`: 全ルートを読み込み
  - `static Future<WalkRoute?> _loadRoute(String)`: 個別ルートファイルを読み込み
- **依存**: `csv`, `flutter/services`, `walking_route`
- **データソース**: `assets/routes/*.csv`

#### 4. route_select_screen.dart
- **役割**: ルート選択画面（リスト表示）
- **主要機能**:
  - ルートリストの表示（名前、地点数、総距離）
  - ルート選択時にナビゲーション画面へ遷移
- **依存**: `route_service`, `walk_navi_screen`, `walking_route`
- **状態管理**: StatefulWidget（ルートリスト読み込み）

#### 5. walk_navi_screen.dart
- **役割**: ナビゲーション画面（メイン UI）
- **主要機能**:
  - リアルタイム位置・方位表示
  - コンパス表示（相対方向）
  - 小型磁北コンパス表示（介助者用）
  - 音声案内タイマー（15秒間隔）
  - 地図画面への遷移
- **状態管理**: StatefulWidget
- **ライフサイクル**:
  - `initState()`: エンジン初期化、コンパス監視開始、音声タイマー開始
  - `deactivate()`: 音声タイマー停止（画面離脱時）
  - `dispose()`: リソース解放
- **依存**: `walk_navi_engine`, `route_map_screen`, `flutter_compass`

#### 6. walk_navi_engine.dart
- **役割**: GPS 追跡とナビゲーションロジック
- **主要クラス**: `WalkNaviEngine`
- **主要機能**:
  - GPS 位置監視（1m 間隔、高精度）
  - 現在位置と次の地点の距離・方位計算
  - 地点到達検出（トリガー距離以内）
  - 地点到達時の音声案内
- **主要メソッド**:
  - `start()`: GPS 監視開始
  - `stop()`: GPS 監視停止
  - `_onPositionUpdate(Position)`: 位置更新時の処理
  - `_announcePoint(NaviPoint)`: 地点到達時の音声案内
- **コールバック**: `onLocationUpdate(Position)`, `onPointReached(int)`
- **依存**: `geolocator`, `walking_route`, `main.globalTts`

#### 7. route_map_screen.dart
- **役割**: Google Maps による地図表示画面
- **主要機能**:
  - ルート全体をポリラインで表示
  - 各地点にマーカー配置（色分け）
  - 現在位置のリアルタイム更新
  - カメラ操作（現在位置、ルート全体表示）
- **状態管理**: StatefulWidget
- **依存**: `google_maps_flutter`, `walking_route`, `walk_navi_engine`

### データフロー図

```
[CSV Files] 
    ↓ (RouteService)
[WalkRoute Models]
    ↓ (RouteSelectScreen)
[User Selection]
    ↓
[WalkNaviScreen] ←→ [WalkNaviEngine] ←→ [GPS Sensor]
    ↓                     ↓
[UI Update]        [Position Calculation]
    ↓                     ↓
[Voice Guidance]   [Point Detection]
    ↓
[globalTts]

[WalkNaviScreen] ←→ [FlutterCompass]
    ↓
[Compass UI]

[WalkNaviScreen] → [RouteMapScreen]
                        ↓
                    [Google Maps]
```

### 主要クラスの責務

| クラス | 責務 | 状態 |
|--------|------|------|
| `WalkRoute` | ルートデータの保持 | イミ ュータブル |
| `NaviPoint` | 地点データと計算ロジック | イミュータブル |
| `RouteService` | CSV読み込み | ステートレス |
| `RouteSelectScreen` | ルート選択 UI | ステートフル |
| `WalkNaviScreen` | ナビ UI とタイマー管理 | ステートフル |
| `WalkNaviEngine` | GPS 監視とナビロジック | ステートフル |
| `RouteMapScreen` | 地図 UI | ステートフル |

### 画面遷移フロー

```
[HomeScreen (main.dart)]
    ↓ ElevatedButton("ルート選択")
[RouteSelectScreen]
    ↓ ListView.builder → onTap(route)
[WalkNaviScreen]
    ├→ IconButton("地図") → [RouteMapScreen]
    │                           ↓ AppBar Back
    │                        [WalkNaviScreen]
    └→ IconButton("停止") → showDialog
                               ↓ "はい"
                          Navigator.popUntil
                               ↓
                          [HomeScreen]
```

### 依存関係図

```
main.dart
    ↓ (provides globalTts)
    ├→ route_select_screen.dart
    │       ↓
    │   route_service.dart → walking_route.dart
    │       ↓
    │   walk_navi_screen.dart
    │       ├→ walk_navi_engine.dart → walking_route.dart
    │       └→ route_map_screen.dart → walking_route.dart
    │
    └→ (uses globalTts)
        walk_navi_engine.dart
```

### センサー統合

#### GPS (geolocator)
- **設定**: `LocationSettings`
  - accuracy: `LocationAccuracy.bestForNavigation`
  - distanceFilter: 1m
- **ストリーム**: `Geolocator.getPositionStream()`
- **使用箇所**: `WalkNaviEngine._onPositionUpdate()`

#### コンパス (flutter_compass)
- **ストリーム**: `FlutterCompass.events`
- **データ**: `heading` (0-360度、磁北基準)
- **使用箇所**: `WalkNaviScreen._deviceHeading`
- **注意**: デバイス依存性あり、センサー未搭載の場合0度固定

#### TTS (flutter_tts)
- **初期化**: `main.dart` でグローバルインスタンス作成
- **設定**: 日本語 (`setLanguage("ja-JP")`)
- **使用箇所**:
  - `WalkNaviEngine._announcePoint()`: 地点到達時
  - `WalkNaviScreen._speakDirection()`: 定期音声案内

### 拡張ポイント（ルート編集機能追加用）

以下の箇所が拡張対象となります：

#### 1. ルート保存機能
- **追加ファイル**: `lib/route_save_service.dart`
- **機能**: `WalkRoute` オブジェクトを CSV 形式で保存
- **保存先**: `getApplicationDocumentsDirectory()` 配下
- **既存コードへの影響**: なし（RouteService と並列）

#### 2. ルート編集画面
- **追加ファイル**: `lib/route_edit_screen.dart`
- **機能**:
  - 既存ルートの地点追加・削除・並び替え
  - 地点の緯度・経度・メッセージ編集
  - 地図上でのタップによる地点追加
- **遷移元**: `RouteSelectScreen`（編集ボタン追加）
- **依存**: `route_map_screen.dart` の地図ロジック再利用可能

#### 3. ルート録画機能
- **追加ファイル**: `lib/route_record_screen.dart`
- **機能**:
  - GPS 位置を一定間隔で記録
  - 手動で地点追加（メッセージ入力）
  - 録画停止後にルートとして保存
- **既存ロジック再利用**: `WalkNaviEngine` の GPS 監視ロジック参考

#### 4. データモデル拡張
- **ファイル**: `walking_route.dart`
- **追加メソッド**:
  - `WalkRoute.toCSV()`: CSV 文字列に変換
  - `WalkRoute.copyWith()`: イミュータブル更新用
  - `NaviPoint.copyWith()`: イミュータブル更新用

#### 5. RouteService の拡張
- **ファイル**: `route_service.dart`
- **追加メソッド**:
  - `loadCustomRoutes()`: ユーザー作成ルートを読み込み
  - `deleteRoute(String)`: ルート削除
- **データソース**: アセットとドキュメントディレクトリの統合

## 権限要件

### Android（AndroidManifest.xml）
```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
```

### 実行時権限
- 位置情報: アプリ起動時に要求
- TTS: システム設定に依存

## 今後の設定手順

### 1. Google Maps API キー取得
1. [Google Cloud Console](https://console.cloud.google.com/) にアクセス
2. 新規プロジェクト作成
3. Maps SDK for Android を有効化
4. 認証情報 → API キーを作成
5. API キーに制限を設定（Android アプリ、パッケージ名: `com.example.walk_guide2`）

### 2. API キー設定
`android/app/src/main/AndroidManifest.xml` の31行目を編集：
```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="実際のAPIキーをここに貼り付け"/>
```

### 3. GitHub リポジトリ作成
```powershell
cd C:\Users\Express580053xguser\Dropbox\31Develop\walk_guide2
git init
git add .
git commit -m "Initial commit: GPS route navigation app"
gh repo create walk_guide2 --public --source=. --push
```

## 開発履歴

### 2026-04-18
- ✅ プロジェクト作成
- ✅ GPS ナビゲーション機能実装
- ✅ 音声案内機能実装
- ✅ コンパス表示実装
- ✅ 地図表示機能追加（API キー待ち）
- ✅ 音声案内を端末向き基準に変更
- ✅ バックグラウンド音声停止処理追加
- ✅ Spec.md 更新

---

**Note**: このプロジェクトは `walk_guide`（AI 画像解析プロジェクト）とは独立しています。ファイルを混在させないよう注意してください。
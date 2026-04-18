# Walk Guide - ルートナビゲーション機能の実装ガイド

## 概要

RemoteNavi54_1.aiaアプリの機能をFlutterで再現し、Walk Guideアプリにルートベースのナビゲーション機能を追加しました。

## 完成したファイル

### 1. **route_service.dart** - ルート読み込みサービス
- CSVファイルからルートデータを読み込む
- 利用可能なルート一覧を提供
- ルートの保存機能（将来の編集用）

### 2. **walk_navi_engine.dart** - ナビゲーションエンジン
- GPS追跡
- 地点接近判定
- 音声案内タイミング制御
- ナビゲーション状態管理

### 3. **route_select_screen.dart** - ルート選択画面
- 利用可能なルート一覧表示
- ルート選択とナビゲーション開始

### 4. **walk_navi_screen.dart** - ナビゲーション画面
- リアルタイムGPS追跡
- 方位表示（コンパス）
- 次の地点までの距離表示
- ナビゲーション制御

### 5. **walking_route.dart** (既存ファイルを活用)
- NaviPointクラス: ルート上の地点データ
- WalkRouteクラス: ルート全体のデータ

## ルートデータ形式

CSVフォーマット：
```
ID, 緯度, 経度, 方位, 距離しきい値, メッセージ
```

例：
```csv
1,35.410191,139.525466,0,10,自宅付近です
2,35.410148,139.525345,0,10,目的地付近です
```

## メイン画面への統合方法

### オプション1: 音声コマンドでルート選択（推奨）

既存の`_executeCommand`メソッドに以下を追加：

```dart
Future<void> _executeCommand(String command) async {
  // ... 既存のコマンド処理 ...
  
  // ルート選択コマンド
  if (command.contains('ルート') || command.contains('ナビ')) {
    setState(() => _currentState = AppState.processing);
    await _tts.stop();
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RouteSelectScreen(tts: _tts),
      ),
    );
    
    setState(() => _currentState = AppState.normal);
    _startAnalysisTimer();
    return;
  }
  
  // ... 残りのコマンド処理 ...
}
```

### オプション2: 設定画面にボタン追加

settings_screen.dartに以下を追加：

```dart
ListTile(
  leading: Icon(Icons.navigation, size: 32),
  title: Text('ルートナビゲーション', style: TextStyle(fontSize: 20)),
  subtitle: Text('ルートを選択してナビゲーション開始'),
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RouteSelectScreen(tts: widget.tts),
      ),
    );
  },
),
```

### オプション3: 専用のナビゲーションアプリとして起動

main.dartを以下のように変更：

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // ... 初期化処理 ...
  
  // ナビゲーションモードかどうかを判定（例：環境変数）
  final bool naviMode = dotenv.env['START_MODE'] == 'navigation';
  
  if (naviMode) {
    // ナビゲーション専用モード
    runApp(MaterialApp(
      home: RouteSelectScreen(tts: FlutterTts()),
    ));
  } else {
    // 通常の画像解析モード
    runApp(MaterialApp(home: WalkingGuideApp(camera: camera)));
  }
}
```

## 使用方法

### 1. ルート選択
1. アプリを起動
2. 音声コマンド「ルート」または設定画面から「ルートナビゲーション」をタップ
3. 利用可能なルート一覧から選択

### 2. ナビゲーション
1. ルートを選択するとナビゲーション画面が表示
2. GPS追跡が自動的に開始
3. 各地点に近づくと音声で案内
4. 画面には以下が表示：
   - ナビゲーション状態
   - 現在の方位（コンパス）
   - 次の地点までの距離
   - 現在位置の緯度・経度

### 3. ナビゲーション終了
- 画面右上の停止ボタンをタップ
- 目的地に到着すると自動的にダイアログが表示

## 新しいルートの追加方法

### 方法1: CSVファイルを直接作成

1. `assets/routes/`フォルダに新しいCSVファイルを作成
2. フォーマットに従ってデータを入力
3. `pubspec.yaml`のassetsセクションに追加：
   ```yaml
   assets:
     - assets/routes/your_new_route.csv
   ```
4. `route_service.dart`の`getAvailableRoutes()`に追加：
   ```dart
   RouteInfo(
     fileName: 'your_new_route.csv',
     displayName: '新しいルート',
     description: 'ルートの説明',
   ),
   ```

### 方法2: ルート編集画面を使用（今後実装予定）

- 地図上で地点をタップして追加
- 既存の地点をドラッグして移動
- メッセージを編集

## RemoteNavi機能との対応

| RemoteNavi機能 | Walk Guide実装 | ファイル |
|--------------|--------------|---------|
| Screen1（メニュー） | RouteSelectScreen | route_select_screen.dart |
| NaviScreen（ナビ画面） | WalkNaviScreen | walk_navi_screen.dart |
| GPS追跡 | WalkNaviEngine | walk_navi_engine.dart |
| CSV読み込み | RouteService | route_service.dart |
| 地点データ | NaviPoint/WalkRoute | walking_route.dart |
| 音声案内 | FlutterTts統合 | walk_navi_engine.dart内 |
| 方位表示 | Transform.rotate | walk_navi_screen.dart内 |

## 今後の拡張機能

### 1. ルート編集機能（優先度: 高）
- 地図上で地点を視覚的に編集
- ドラッグ&ドロップで地点移動
- 現在地を地点として追加

### 2. 複数ルートの管理（優先度: 中）
- ルートのインポート/エクスポート
- クラウド同期
- ルートの共有

### 3. 高度なナビゲーション（優先度: 中）
- 音声コマンドでナビゲーション制御
- ルート逸脱検知
- 代替ルート提案

### 4. AI画像解析との統合（優先度: 高）
- ナビゲーション中も前方の障害物を検知
- 「前方注意」と「次の地点案内」を両立
- 信号機・横断歩道の検出

## 注意事項

### GPS精度
- 屋内ではGPS精度が低下します
- トンネルや高層ビルの間では位置情報が不正確になることがあります
- `triggerDistance`（案内距離）を調整して誤案内を防ぎます

### バッテリー消費
- GPS追跡は電力を消費します
- 長時間の使用時はモバイルバッテリーを推奨

### 音声案内
- ナビゲーション中の音声案内は既存のTTSエンジンを使用
- 音声コマンドとの競合を避けるため、案内中は音声認識を一時停止

## トラブルシューティング

### ルートが読み込めない
- CSVファイルのフォーマットを確認
- `pubspec.yaml`にファイルが登録されているか確認
- アプリを再ビルド（`flutter clean && flutter build apk`）

### 位置情報が取得できない
- Androidの位置情報権限を確認
- GPSがオンになっているか確認
- 屋外で試す

### 音声案内が流れない
- TTSの初期化を確認
- デバイスの音量を確認
- 他のアプリがTTSを使用していないか確認

## 開発者向けメモ

### アーキテクチャ

```
RouteSelectScreen（ルート選択）
  ↓ RouteService.loadRoute()
WalkNaviScreen（ナビ画面）
  ↓ WalkNaviEngine.start()
  ├─ GPS追跡（Geolocator）
  ├─ 地点判定（NaviPoint.distanceTo）
  └─ 音声案内（FlutterTts）
```

### 状態管理
- `NaviState`: ナビゲーションの状態を管理
- `setState`: 画面更新
- `StreamSubscription<Position>`: GPS追跡

### テスト方法
- エミュレーターでGPSシミュレーション
- 実機で実際に歩いてテスト
- CSV地点座標を現在地付近に設定してテスト

---

**実装完了日**: 2026年4月17日  
**バージョン**: v0.0.12+11（予定）

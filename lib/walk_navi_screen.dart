import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:camera/camera.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'walking_route.dart';
import 'walk_navi_engine.dart';
import 'route_map_screen.dart';
import 'ai_service.dart';

/// ナビゲーション画面
class WalkNaviScreen extends StatefulWidget {
  final WalkRoute route;
  final FlutterTts tts;

  const WalkNaviScreen({
    super.key,
    required this.route,
    required this.tts,
  });

  @override
  State<WalkNaviScreen> createState() => _WalkNaviScreenState();
}

class _WalkNaviScreenState extends State<WalkNaviScreen> {
  late WalkNaviEngine _naviEngine;
  NaviState _currentState = NaviState.initial;
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<CompassEvent>? _compassStream;
  double _deviceHeading = 0.0; // 端末の向き（方位センサー）
  double _bearingToNext = 0.0; // 次の地点への方位

  NaviPoint? _nextPoint;
  double? _distanceToNext;
  
  // 音声ナビ用タイマー
  Timer? _voiceNaviTimer;

  // 障害者支援機能
  CameraController? _cameraController;
  final SpeechToText _speechToText = SpeechToText();
  bool _isListening = false;
  bool _isCameraProcessing = false;
  File? _lastCapturedImage; // 最後に撮影した画像
  bool _isNavigationPaused = false; // ルート案内一時停止フラグ

  @override
  void initState() {
    super.initState();
    _initializeEngine();
    _startPositionTracking();
    _initializeCamera();
    _initializeSpeech();
  }

  /// カメラ初期化
  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      _cameraController = CameraController(
        cameras.first,
        ResolutionPreset.medium,
      );
      await _cameraController!.initialize();
    } catch (e) {
      print('カメラ初期化エラー: $e');
    }
  }

  /// 音声認識初期化
  Future<void> _initializeSpeech() async {
    try {
      await _speechToText.initialize(
        onError: (error) => print('音声認識エラー: $error'),
      );
    } catch (e) {
      print('音声認識初期化エラー: $e');
    }
  }

  void _initializeEngine() {
    _naviEngine = WalkNaviEngine(
      route: widget.route,
      tts: widget.tts,
      onStateChanged: (state) {
        setState(() {
          _currentState = state;
        });
        if (state == NaviState.arrived) {
          _showArrivalDialog();
        }
      },
    );
  }

  Future<void> _startPositionTracking() async {
    try {
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 1,
        ),
      ).listen((position) {
        setState(() {
          _currentPosition = position;
          _updateNextPoint();
        });
      });
      
      // 端末の方位センサーを監視
      _compassStream = FlutterCompass.events?.listen((CompassEvent event) {
        setState(() {
          _deviceHeading = event.heading ?? 0.0;
        });
      });

      await _naviEngine.start();
      
      // 音声ナビを15秒ごとに実行
      _voiceNaviTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        _announceDirection();
      });
    } catch (e) {
      _showError('位置情報の取得に失敗しました: $e');
    }
  }

  void _updateNextPoint() {
    if (_currentPosition == null) return;

    NaviPoint? nearest;
    double? nearestDistance;

    for (final point in widget.route.points) {
      final distance = point.distanceTo(_currentPosition!);
      if (nearestDistance == null || distance < nearestDistance) {
        nearest = point;
        nearestDistance = distance;
      }
    }

    setState(() {
      _nextPoint = nearest;
      _distanceToNext = nearestDistance;
      
      // 次の地点への方位を計算
      if (nearest != null) {
        _bearingToNext = nearest.bearingFrom(_currentPosition!);
      }
    });
  }
  
  // 音声で方向と距離を案内
  Future<void> _announceDirection() async {
    // ルート案内が一時停止中の場合はスキップ
    if (_isNavigationPaused) return;
    
    if (_nextPoint == null || _distanceToNext == null || _currentPosition == null) return;
    
    final distance = _distanceToNext!.round();
    
    // 端末の向きと目的地方向の差分（相対角度）
    double relativeBearing = _bearingToNext - _deviceHeading;
    
    // -180～180度の範囲に正規化
    while (relativeBearing > 180) relativeBearing -= 360;
    while (relativeBearing < -180) relativeBearing += 360;
    
    String direction;
    if (relativeBearing.abs() < 15) {
      direction = 'まっすぐ';
    } else if (relativeBearing > 0) {
      direction = '右へ${relativeBearing.round().abs()}度';
    } else {
      direction = '左へ${relativeBearing.round().abs()}度';
    }

    final message = '$direction、${distance}メートル先';
    await widget.tts.speak(message);
  }
  
  /// 音声ナビを再開
  void _startVoiceNavi() {
    if (_voiceNaviTimer == null || !(_voiceNaviTimer!.isActive)) {
      _voiceNaviTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        _announceDirection();
      });
    }
  }

  /// 前方カメラで撮影してAI説明（右ボタン）
  Future<void> _describeFrontView() async {
    if (_isCameraProcessing) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      await widget.tts.speak('カメラが利用できません');
      return;
    }

    setState(() {
      _isCameraProcessing = true;
      _isNavigationPaused = true; // ルート案内を一時停止
    });

    try {
      // 音声ナビを一時停止
      _voiceNaviTimer?.cancel();
      await widget.tts.stop();
      
      await widget.tts.speak('撮影します');
      
      final image = await _cameraController!.takePicture();
      final imageFile = File(image.path);
      
      // 最後に撮影した画像として保存
      setState(() {
        _lastCapturedImage = imageFile;
      });

      // 撮影した画像を表示
      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => _ImageDescriptionDialog(
            imageFile: imageFile,
            tts: widget.tts,
            onCompleted: () {
              // ダイアログが閉じられた後、ルート案内を再開
              setState(() {
                _isNavigationPaused = false;
              });
              _startVoiceNavi(); // 音声ナビを再開
            },
          ),
        );
      }
    } catch (e) {
      await widget.tts.speak('エラーが発生しました');
      print('カメラエラー: $e');
      setState(() {
        _isNavigationPaused = false;
      });
      _startVoiceNavi(); // エラー時も再開
    } finally {
      setState(() {
        _isCameraProcessing = false;
      });
    }
  }

  /// 音声命令を聞く（左ボタン）
  Future<void> _listenToVoiceCommand() async {
    if (_isListening) return;
    if (!_speechToText.isAvailable) {
      await widget.tts.speak('音声認識が利用できません');
      return;
    }

    setState(() {
      _isListening = true;
      _isNavigationPaused = true; // ルート案内を一時停止
    });

    try {
      // 音声ナビを一時停止
      _voiceNaviTimer?.cancel();
      await widget.tts.stop();
      
      await widget.tts.speak('どうぞ');
      
      await _speechToText.listen(
        onResult: (result) async {
          if (result.finalResult) {
            final command = result.recognizedWords;
            print('認識された命令: $command');

            setState(() {
              _isListening = false;
            });

            if (command.isNotEmpty) {
              // 画像に関する質問かどうかチェック
              final imageKeywords = ['前', '写真', '画像', '見える', '何', '景色', '風景', 'まえ', 'しゃしん'];
              final isImageQuestion = imageKeywords.any((keyword) => command.contains(keyword));
              
              // 命令とAIの返事を表示するダイアログを表示
              if (mounted) {
                await showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => _VoiceCommandDialog(
                    command: command,
                    tts: widget.tts,
                    imageFile: (isImageQuestion && _lastCapturedImage != null) ? _lastCapturedImage : null,
                    onCompleted: () {
                      // ダイアログが閉じられた後、ルート案内を再開
                      setState(() {
                        _isNavigationPaused = false;
                      });
                      _startVoiceNavi(); // 音声ナビを再開
                    },
                  ),
                );
              }
            } else {
              setState(() {
                _isNavigationPaused = false;
              });
              _startVoiceNavi();
            }
          }
        },
        localeId: 'ja_JP',
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
      );

      // タイムアウト処理
      await Future.delayed(const Duration(seconds: 10));
      if (_isListening) {
        await _speechToText.stop();
        setState(() {
          _isListening = false;
          _isNavigationPaused = false;
        });
        _startVoiceNavi();
      }
    } catch (e) {
      await widget.tts.speak('音声認識エラー');
      print('音声認識エラー: $e');
      setState(() {
        _isListening = false;
        _isNavigationPaused = false;
      });
      _startVoiceNavi();
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showArrivalDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text(
          '到着',
          style: TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          '目的地に到着しました。\nお疲れ様でした。',
          style: TextStyle(color: Colors.white, fontSize: 24),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
            child: const Text(
              '終了',
              style: TextStyle(fontSize: 24, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _stopNavigation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text(
          'ナビゲーション終了',
          style: TextStyle(color: Colors.white, fontSize: 28),
        ),
        content: const Text(
          'ナビゲーションを終了しますか?',
          style: TextStyle(color: Colors.white, fontSize: 20),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル', style: TextStyle(fontSize: 20)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('終了', style: TextStyle(fontSize: 20)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _naviEngine.stop();
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  String _getStateText() {
    switch (_currentState) {
      case NaviState.initial:
        return '準備中...';
      case NaviState.navigating:
        return 'ナビゲーション中';
      case NaviState.paused:
        return '一時停止';
      case NaviState.arrived:
        return '到着';
      case NaviState.stopped:
        return '停止';
      case NaviState.error:
        return 'エラー';
    }
  }

  // 相対方向をテキストで返す
  String _getDirectionText() {
    if (_nextPoint == null) return '待機中...';
    
    // 端末の向きと目的地方向の差分（相対角度）
    double relativeBearing = _bearingToNext - _deviceHeading;
    
    // -180～180度の範囲に正規化
    while (relativeBearing > 180) relativeBearing -= 360;
    while (relativeBearing < -180) relativeBearing += 360;
    
    if (relativeBearing.abs() < 15) {
      return 'まっすぐ';
    } else if (relativeBearing > 0) {
      return '右へ ${relativeBearing.round().abs()}°';
    } else {
      return '左へ ${relativeBearing.round().abs()}°';
    }
  }

  @override
  void deactivate() {
    // 画面を離れるとき音声タイマーを停止
    _voiceNaviTimer?.cancel();
    super.deactivate();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _compassStream?.cancel();
    _voiceNaviTimer?.cancel();
    _cameraController?.dispose();
    _naviEngine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          widget.route.name,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        toolbarHeight: 70, // AppBarの高さを増やす
        backgroundColor: Colors.grey[900],
        iconTheme: const IconThemeData(color: Colors.white, size: 20),
        actions: [
          // ステータスインジケータ
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: _currentState == NaviState.navigating
                  ? Colors.green[700]
                  : Colors.grey[700],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _currentState == NaviState.navigating
                    ? Colors.green[400]!
                    : Colors.grey[500]!,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _currentState == NaviState.navigating
                      ? Icons.navigation
                      : Icons.pause_circle,
                  size: 14,
                  color: Colors.white,
                ),
                const SizedBox(width: 4),
                Text(
                  _getStateText(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // 地図ボタン（大きく分かりやすく）
          Container(
            decoration: BoxDecoration(
              color: Colors.blue[700],
              borderRadius: BorderRadius.circular(8),
            ),
            margin: const EdgeInsets.only(right: 4),
            child: IconButton(
              icon: const Icon(Icons.map, size: 32, color: Colors.white),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RouteMapScreen(route: widget.route),
                  ),
                );
              },
              tooltip: '地図',
              padding: const EdgeInsets.all(8),
            ),
          ),
          // 停止ボタン（大きく分かりやすく）
          Container(
            decoration: BoxDecoration(
              color: Colors.red[700],
              borderRadius: BorderRadius.circular(8),
            ),
            margin: const EdgeInsets.only(right: 8),
            child: IconButton(
              icon: const Icon(Icons.stop_circle, size: 32, color: Colors.white),
              onPressed: _stopNavigation,
              tooltip: '終了',
              padding: const EdgeInsets.all(8),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 介助者用情報エリア（上半分）
          Expanded(
            flex: 5,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.grey[900]!, Colors.grey[850]!],
                ),
              ),
              child: Column(
                children: [
                  // セクション1: ナビゲーション情報
                  Expanded(
                    flex: 3,
                    child: Container(
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[800]!.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[700]!, width: 1),
                      ),
                      child: Row(
                        children: [
                          // コンパス表示
                          Expanded(
                            flex: 2,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              child: Stack(
                                children: [
                                  Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.blue[900]!.withOpacity(0.3),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Transform.rotate(
                                            angle: (_bearingToNext - _deviceHeading) * 3.141592653589793 / 180,
                                            child: Icon(
                                              Icons.navigation,
                                              size: 60,
                                              color: Colors.blue[300],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          _getDirectionText(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // 磁北コンパス
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.7),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.red[900]!, width: 1),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Transform.rotate(
                                            angle: -_deviceHeading * 3.141592653589793 / 180,
                                            child: const Icon(
                                              Icons.navigation,
                                              size: 16,
                                              color: Colors.red,
                                            ),
                                          ),
                                          const Text(
                                            'N',
                                            style: TextStyle(
                                              color: Colors.red,
                                              fontSize: 8,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            '${_deviceHeading.round()}°',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 8,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // 地点情報
                          Expanded(
                            flex: 3,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(color: Colors.grey[700]!, width: 1),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.place, size: 16, color: Colors.blue[300]),
                                      const SizedBox(width: 6),
                                      const Text(
                                        '次の地点',
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _nextPoint?.message ?? '地点情報なし',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      // 距離カード
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Colors.blue[900]!.withOpacity(0.3),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: Colors.blue[700]!, width: 1),
                                          ),
                                          child: Column(
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(Icons.straighten, size: 12, color: Colors.grey[400]),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '距離',
                                                    style: TextStyle(
                                                      color: Colors.grey[400],
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${_distanceToNext?.round() ?? '--'} m',
                                                style: TextStyle(
                                                  color: Colors.blue[300],
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // 進捗カード
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Colors.green[900]!.withOpacity(0.3),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: Colors.green[700]!, width: 1),
                                          ),
                                          child: Column(
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(Icons.flag, size: 12, color: Colors.grey[400]),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '進捗',
                                                    style: TextStyle(
                                                      color: Colors.grey[400],
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${_nextPoint?.no ?? '--'}/${widget.route.points.length}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // セクション2: 位置情報
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey[800]!.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[700]!, width: 1),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.my_location, size: 14, color: Colors.green[400]),
                            const SizedBox(width: 6),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '緯度',
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 9,
                                  ),
                                ),
                                Text(
                                  _currentPosition?.latitude.toStringAsFixed(5) ?? '--',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Container(
                          width: 1,
                          height: 30,
                          color: Colors.grey[700],
                        ),
                        Row(
                          children: [
                            Icon(Icons.my_location, size: 14, color: Colors.green[400]),
                            const SizedBox(width: 6),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '経度',
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 9,
                                  ),
                                ),
                                Text(
                                  _currentPosition?.longitude.toStringAsFixed(5) ?? '--',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),

          // 区切り線
          Container(
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, Colors.grey[700]!, Colors.transparent],
              ),
            ),
          ),

          // 障害者用操作エリア（下半分）
          Expanded(
            flex: 5,
            child: Container(
              color: Colors.black,
              child: Row(
                children: [
                  // 左ボタン：音声命令
                  Expanded(
                    child: GestureDetector(
                      onTap: _listenToVoiceCommand,
                      child: Container(
                        margin: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _isListening ? Colors.green : Colors.blue[700],
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: (_isListening ? Colors.green : Colors.blue).withOpacity(0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _isListening ? Icons.mic : Icons.mic_none,
                              size: 100,

                              color: Colors.white,
                            ),
                            const SizedBox(height: 20),
                            Text(
                              _isListening ? '聞いています...' : '音声命令',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'タップして質問',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 20,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // 右ボタン：カメラ説明
                  Expanded(
                    child: GestureDetector(
                      onTap: _describeFrontView,
                      child: Container(
                        margin: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _isCameraProcessing ? Colors.orange : Colors.purple[700],
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: (_isCameraProcessing ? Colors.orange : Colors.purple).withOpacity(0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _isCameraProcessing ? Icons.hourglass_empty : Icons.camera_alt,
                              size: 100,
                              color: Colors.white,
                            ),
                            const SizedBox(height: 20),
                            Text(
                              _isCameraProcessing ? '分析中...' : '前方確認',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'タップして撮影',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 20,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 画像説明ダイアログ（前方確認ボタン用）
class _ImageDescriptionDialog extends StatefulWidget {
  final File imageFile;
  final FlutterTts tts;
  final VoidCallback? onCompleted;

  const _ImageDescriptionDialog({
    required this.imageFile,
    required this.tts,
    this.onCompleted,
  });

  @override
  State<_ImageDescriptionDialog> createState() => _ImageDescriptionDialogState();
}

class _ImageDescriptionDialogState extends State<_ImageDescriptionDialog> {
  String _status = '画像を分析中です...';
  String _description = '';
  bool _isProcessing = true;

  @override
  void initState() {
    super.initState();
    _processImage();
  }

  Future<void> _processImage() async {
    try {
      await widget.tts.speak('画像を分析中です');
      
      final description = await AIService.describeImage(widget.imageFile);
      
      setState(() {
        _description = description;
        _status = '説明完了';
      });
      
      await widget.tts.speak(description);
      
      setState(() {
        _isProcessing = false;
      });
      
      // 音声が終わっても自動では閉じない（ユーザーが閉じるボタンを押すまで表示）
    } catch (e) {
      setState(() {
        _description = 'エラーが発生しました: $e';
        _status = 'エラー';
        _isProcessing = false;
      });
      await widget.tts.speak('エラーが発生しました');
    }
  }
  
  void _closeDialog() {
    if (widget.onCompleted != null) {
      widget.onCompleted!();
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black.withOpacity(0.95),
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // タイトル
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '前方確認',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 32),
                  onPressed: _closeDialog,
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // 撮影した画像
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.purple, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(
                    widget.imageFile,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // ステータス
            if (_isProcessing)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.purple),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _status,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            
            // 説明文
            if (_description.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[700]!, width: 1),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _description,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 音声命令ダイアログ（音声命令ボタン用）
class _VoiceCommandDialog extends StatefulWidget {
  final String command;
  final FlutterTts tts;
  final File? imageFile; // 画像に関する質問の場合に使用
  final VoidCallback? onCompleted;

  const _VoiceCommandDialog({
    required this.command,
    required this.tts,
    this.imageFile,
    this.onCompleted,
  });

  @override
  State<_VoiceCommandDialog> createState() => _VoiceCommandDialogState();
}

class _VoiceCommandDialogState extends State<_VoiceCommandDialog> {
  String _status = 'AIに問い合わせ中...';
  String _response = '';
  bool _isProcessing = true;

  @override
  void initState() {
    super.initState();
    _processCommand();
  }

  Future<void> _processCommand() async {
    try {
      await widget.tts.speak('お待ちください');
      
      String response;
      
      // 画像ファイルがある場合は画像説明APIを使用
      if (widget.imageFile != null) {
        response = await AIService.describeImage(widget.imageFile!);
      } else {
        response = await AIService.processVoiceCommand(widget.command);
      }
      
      setState(() {
        _response = response;
        _status = '説明完了';
      });
      
      await widget.tts.speak(response);
      
      setState(() {
        _isProcessing = false;
      });
      
      // 音声が終わっても自動では閉じない（ユーザーが閉じるボタンを押すまで表示）
    } catch (e) {
      setState(() {
        _response = 'エラーが発生しました: $e';
        _status = 'エラー';
        _isProcessing = false;
      });
      await widget.tts.speak('エラーが発生しました');
    }
  }
  
  void _closeDialog() {
    if (widget.onCompleted != null) {
      widget.onCompleted!();
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black.withOpacity(0.95),
      child: Container(
        padding: const EdgeInsets.all(20),
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight: widget.imageFile != null ? 750 : 600,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // タイトル
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '音声命令',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 32),
                  onPressed: _closeDialog,
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // 画像がある場合は表示
            if (widget.imageFile != null) ...[
              Container(
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.purple, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(
                    widget.imageFile!,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
            
            // あなたの命令
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[900]!.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[700]!, width: 2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.mic, color: Colors.blue, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'あなたの命令',
                        style: TextStyle(
                          color: Colors.blue,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.command,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            // ステータス表示
            if (_isProcessing)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _status,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            
            // AIの返事
            if (_response.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.purple[900]!.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.purple[700]!, width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.smart_toy, color: Colors.purple, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'AIの返事',
                          style: TextStyle(
                            color: Colors.purple,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      child: Text(
                        _response,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

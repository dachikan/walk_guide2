import 'dart:async';
import 'dart:io';
import 'dart:math' as dart_math;
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
import 'common_header.dart';

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
  
  // GPS状態デバッグ用
  String _gpsStatus = '初期化中...';
  LocationPermission? _locationPermission;
  int _positionUpdateCount = 0; // 位置更新回数
  DateTime? _lastPositionUpdateTime; // 最終更新時刻
  
  // パフォーマンス対策
  bool _isDisposed = false; // 破棄済みフラグ
  DateTime? _lastSetStateTime; // 最終setState時刻
  static const _minSetStateInterval = Duration(milliseconds: 500); // setState最小間隔

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
    // カメラ初期化を遅延（メモリ節約）
    Future.delayed(const Duration(seconds: 2), () {
      if (!_isDisposed) _initializeCamera();
    });
    _initializeSpeech();
  }

  /// カメラ初期化（遅延）
  Future<void> _initializeCamera() async {
    if (_isDisposed) return;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty || _isDisposed) return;

      _cameraController = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false, // 音声不要
      );
      if (!_isDisposed) {
        await _cameraController!.initialize();
      }
    } catch (e) {
      if (!_isDisposed) {
        debugPrint('カメラ初期化エラー: $e');
      }
    }
  }

  /// 音声認識初期化
  Future<void> _initializeSpeech() async {
    if (_isDisposed) return;
    try {
      await _speechToText.initialize(
        onError: (error) => debugPrint('音声認識エラー: $error'),
      );
    } catch (e) {
      if (!_isDisposed) {
        debugPrint('音声認識初期化エラー: $e');
      }
    }
  }
  
  /// setState の最適化版（過剰な更新を防止）
  void _safeSetState(VoidCallback fn) {
    if (_isDisposed || !mounted) return;
    
    final now = DateTime.now();
    if (_lastSetStateTime != null &&
        now.difference(_lastSetStateTime!) < _minSetStateInterval) {
      // 更新が頻繁すぎる場合はスキップ
      return;
    }
    
    _lastSetStateTime = now;
    setState(fn);
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
      print('=== GPS初期化開始 ===');
      
      // GPS有効化チェック
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      print('📡 位置情報サービス: ${serviceEnabled ? "有効" : "無効"}');
      
      if (!serviceEnabled) {
        setState(() {
          _gpsStatus = 'GPS無効: 設定でGPSを有効にしてください';
        });
        await widget.tts.speak('GPSが無効です。設定で有効にしてください。');
        _showError('GPSが無効です。設定から位置情報サービスを有効にしてください。');
        print('❌ GPSサービスが無効です');
        return;
      }

      // 権限チェック
      _locationPermission = await Geolocator.checkPermission();
      print('🔐 位置情報権限: $_locationPermission');
      
      if (_locationPermission == LocationPermission.denied) {
        print('⚠️ 権限が拒否されています。権限をリクエストします...');
        _locationPermission = await Geolocator.requestPermission();
        print('🔐 権限リクエスト結果: $_locationPermission');
        
        if (_locationPermission == LocationPermission.denied) {
          setState(() {
            _gpsStatus = '権限拒否: 位置情報の権限を許可してください';
          });
          await widget.tts.speak('位置情報の権限が必要です。');
          _showError('位置情報の権限が拒否されました。');
          print('❌ 権限が拒否されました');
          return;
        }
      }

      if (_locationPermission == LocationPermission.deniedForever) {
        setState(() {
          _gpsStatus = '権限永久拒否: 設定から権限を許可してください';
        });
        await widget.tts.speak('設定から位置情報の権限を許可してください。');
        _showError('位置情報の権限が永久に拒否されています。設定から許可してください。');
        print('❌ 権限が永久拒否されています');
        return;
      }

      setState(() {
        _gpsStatus = 'GPS情報取得中... (最大15秒待機)';
      });
      print('🔍 位置情報取得を開始します...');

      // 最初の位置を取得（タイムアウト付き）
      try {
        debugPrint('=== GPS初期位置取得開始 ===');
        
        // メインスレッドをブロックしないように少し待機
        await Future.delayed(const Duration(milliseconds: 500));
        
        final initialPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15),
        ).timeout(
          const Duration(seconds: 20),
          onTimeout: () {
            debugPrint('⏱️ GPS取得がタイムアウトしました（20秒）');
            throw TimeoutException('GPS信号受信タイムアウト');
          },
        );
        
        _safeSetState(() {
          _currentPosition = initialPosition;
          _positionUpdateCount = 1;
          _lastPositionUpdateTime = DateTime.now();
          _gpsStatus = 'GPS取得成功 (精度: ${initialPosition.accuracy.toStringAsFixed(1)}m)';
          _updateNextPoint();
        });
        debugPrint('✅ 初期位置: ${initialPosition.latitude}, ${initialPosition.longitude} (精度: ${initialPosition.accuracy}m)');
        
        // GPS取得成功後にナビゲーションエンジンを開始
        await _naviEngine.start();
        debugPrint('✅ ナビゲーションエンジン開始');
        
        // 音声ナビを15秒ごとに実行
        _voiceNaviTimer?.cancel();
        _voiceNaviTimer = Timer.periodic(const Duration(seconds: 15), (_) {
          if (!_isDisposed && !_isNavigationPaused) {
            _announceDirection();
          }
        });
        debugPrint('✅ 音声ナビタイマー開始');
        
      } on TimeoutException catch (e) {
        _safeSetState(() {
          _gpsStatus = 'GPS取得タイムアウト: 屋外で再試行してください';
        });
        debugPrint('❌ タイムアウト: $e');
        await widget.tts.speak('GPS信号を受信できません。屋外で再試行してください。');
        return; // エラー時はストリーム開始せずに終了
      } catch (e) {
        _safeSetState(() {
          _gpsStatus = 'GPS取得失敗: $e';
        });
        debugPrint('❌ 初期位置取得エラー: $e');
        await widget.tts.speak('位置情報の取得に失敗しました。');
        return; // エラー時はストリーム開始せずに終了
      }

      // 位置情報ストリーム開始
      debugPrint('=== GPS位置情報ストリーム開始 ===');
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 2, // 2m移動で更新（更新頻度を下げる）
        ),
      ).listen(
        (position) {
          if (_isDisposed) return;
          
          _positionUpdateCount++;
          _lastPositionUpdateTime = DateTime.now();
          
          _safeSetState(() {
            _currentPosition = position;
            _gpsStatus = 'GPS更新中 (精度: ${position.accuracy.toStringAsFixed(1)}m, 更新: $_positionUpdateCount回)';
            _updateNextPoint();
          });
          
          // デバッグログは10回に1回だけ出力
          if (_positionUpdateCount % 10 == 0) {
            debugPrint('📍 位置更新 #$_positionUpdateCount: ${position.latitude}, ${position.longitude}');
          }
        },
        onError: (error) {
          debugPrint('❌ GPS位置情報ストリームエラー: $error');
          if (!_isDisposed) {
            _safeSetState(() {
              _gpsStatus = 'GPSエラー: $error';
            });
          }
        },
      );
      
      // 端末の方位センサーを監視（更新頻度を制限）
      _compassStream = FlutterCompass.events?.listen((CompassEvent event) {
        if (_isDisposed) return;
        // 方位は頻繁に更新されるので_safeSetStateを使用
        _safeSetState(() {
          _deviceHeading = event.heading ?? 0.0;
        });
      });
      
    } catch (e) {
      if (!_isDisposed) {
        _safeSetState(() {
          _gpsStatus = '致命的エラー: $e';
        });
        _showError('位置情報の取得に失敗しました: $e');
        debugPrint('位置情報追跡開始エラー: $e');
      }
    }
  }

  void _updateNextPoint() {
    if (_currentPosition == null || _isDisposed) return;

    NaviPoint? nearest;
    double? nearestDistance;

    for (final point in widget.route.points) {
      final distance = point.distanceTo(_currentPosition!);
      if (nearestDistance == null || distance < nearestDistance) {
        nearest = point;
        nearestDistance = distance;
      }
    }

    // 値が変わった場合のみ更新
    if (_nextPoint != nearest || _distanceToNext != nearestDistance) {
      setState(() {
        _nextPoint = nearest;
        _distanceToNext = nearestDistance;
        
        // 次の地点への方位を計算
        if (nearest != null) {
          _bearingToNext = nearest.bearingFrom(_currentPosition!);
        }
      });
    }
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
    if (_isDisposed) return;
    
    // 既存のタイマーをキャンセル
    _voiceNaviTimer?.cancel();
    _voiceNaviTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_isDisposed && !_isNavigationPaused) {
        _announceDirection();
      }
    });
  }

  /// 前方カメラで撮影してAI説明（右ボタン）
  Future<void> _describeFrontView() async {
    if (_isCameraProcessing || _isDisposed) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      await widget.tts.speak('カメラが利用できません');
      return;
    }

    _safeSetState(() {
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
      if (!_isDisposed) {
        _safeSetState(() {
          _lastCapturedImage = imageFile;
        });
      }

      // 撮影した画像を表示
      if (mounted && !_isDisposed) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => _ImageDescriptionDialog(
            imageFile: imageFile,
            tts: widget.tts,
            onCompleted: () {
              // ダイアログが閉じられた後、ルート案内を再開
              if (!_isDisposed) {
                _safeSetState(() {
                  _isNavigationPaused = false;
                });
                _startVoiceNavi(); // 音声ナビを再開
              }
            },
          ),
        );
      }
    } catch (e) {
      await widget.tts.speak('エラーが発生しました');
      debugPrint('カメラエラー: $e');
      if (!_isDisposed) {
        _safeSetState(() {
          _isNavigationPaused = false;
        });
        _startVoiceNavi(); // エラー時も再開
      }
    } finally {
      if (!_isDisposed) {
        _safeSetState(() {
          _isCameraProcessing = false;
        });
      }
    }
  }

  /// 音声命令を聞く（左ボタン）
  Future<void> _listenToVoiceCommand() async {
    if (_isListening || _isDisposed) return;
    if (!_speechToText.isAvailable) {
      await widget.tts.speak('音声認識が利用できません');
      return;
    }

    _safeSetState(() {
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
            debugPrint('認識された命令: $command');

            if (!_isDisposed) {
              _safeSetState(() {
                _isListening = false;
              });
            }

            if (command.isNotEmpty) {
              // 画像に関する質問かどうかチェック
              final imageKeywords = ['前', '写真', '画像', '見える', '何', '景色', '風景', 'まえ', 'しゃしん'];
              final isImageQuestion = imageKeywords.any((keyword) => command.contains(keyword));
              
              // 命令とAIの返事を表示するダイアログを表示
              if (mounted && !_isDisposed) {
                await showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => _VoiceCommandDialog(
                    command: command,
                    tts: widget.tts,
                    imageFile: (isImageQuestion && _lastCapturedImage != null) ? _lastCapturedImage : null,
                    onCompleted: () {
                      // ダイアログが閉じられた後、ルート案内を再開
                      if (!_isDisposed) {
                        _safeSetState(() {
                          _isNavigationPaused = false;
                        });
                        _startVoiceNavi(); // 音声ナビを再開
                      }
                    },
                  ),
                );
              }
            } else {
              if (!_isDisposed) {
                _safeSetState(() {
                  _isNavigationPaused = false;
                });
                _startVoiceNavi();
              }
            }
          }
        },
        localeId: 'ja_JP',
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
      );

      // タイムアウト処理
      await Future.delayed(const Duration(seconds: 10));
      if (_isListening && !_isDisposed) {
        await _speechToText.stop();
        _safeSetState(() {
          _isListening = false;
          _isNavigationPaused = false;
        });
        _startVoiceNavi();
      }
    } catch (e) {
      await widget.tts.speak('音声認識エラー');
      debugPrint('音声認識エラー: $e');
      if (!_isDisposed) {
        _safeSetState(() {
          _isListening = false;
          _isNavigationPaused = false;
        });
        _startVoiceNavi();
      }
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
        // GPS取得前は「GPS情報取得中」、取得後は「準備中」
        return _currentPosition == null ? 'GPS情報取得中...' : '準備中...';
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
    // 最初にdisposeフラグを設定して、以降の更新を防ぐ
    _isDisposed = true;
    
    // 全てのストリームをキャンセル
    _positionStream?.cancel();
    _positionStream = null;
    
    _compassStream?.cancel();
    _compassStream = null;
    
    // タイマーをキャンセル
    _voiceNaviTimer?.cancel();
    _voiceNaviTimer = null;
    
    // カメラを停止
    _cameraController?.dispose();
    _cameraController = null;
    
    // ナビゲーションエンジンを停止
    _naviEngine.dispose();
    
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: CommonAppBar(
          pageTitle: 'ナビゲーション',
          onAIChanged: () {
            // AI変更時の処理（必要に応じて）
          },
        ),
      ),
      body: Column(
        children: [
          // AppBarの下に追加のツールバー（ステータス、地図、中止ボタン）
          Container(
            height: 50,
            color: Colors.grey[900],
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // ステータス表示（文字）
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: _currentState == NaviState.navigating
                        ? Colors.green[700]
                        : Colors.grey[700],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _getStateText(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // 地図ボタン（文字表示）
                Container(
                  margin: const EdgeInsets.only(right: 4),
                  child: TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => RouteMapScreen(route: widget.route),
                        ),
                      );
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.blue[700],
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      '地図',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                // 中止ボタン（文字表示）
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  child: TextButton(
                    onPressed: _stopNavigation,
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.red[700],
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      '中止',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ルート名表示エリア（専用の行）
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[850],
              border: Border(
                bottom: BorderSide(color: Colors.grey[700]!, width: 1),
              ),
            ),
            child: Text(
              widget.route.name,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
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
                  // セクション1: 3ブロックレイアウト（現在地 | 方向矢印 | 地点情報）
                  Expanded(
                    flex: 3,
                    child: Container(
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[800]!.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[700]!, width: 1),
                      ),
                      child: _currentPosition != null && _distanceToNext != null
                          ? Row(
                              children: [
                                // 左ブロック：現在地情報
                                Expanded(
                                  flex: 2,
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          '現在地',
                                          style: TextStyle(
                                            color: Colors.blue[300],
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          '緯度 ${_currentPosition!.latitude.toStringAsFixed(5)}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.visible,
                                          softWrap: false,
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '経度 ${_currentPosition!.longitude.toStringAsFixed(5)}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.visible,
                                          softWrap: false,
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '方位 北${_deviceHeading.round()}°',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.visible,
                                          softWrap: false,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                // 中ブロック：方向矢印とGPS状態
                                Expanded(
                                  flex: 3,
                                  child: Stack(
                                    children: [
                                      // 矢印を中央に配置
                                      Center(
                                        child: Container(
                                          padding: const EdgeInsets.all(16),
                                          child: CustomPaint(
                                            size: Size.infinite,
                                            painter: _DirectionArrowPainter(
                                              relativeBearing: _bearingToNext - _deviceHeading,
                                              deviceHeading: _deviceHeading,
                                            ),
                                          ),
                                        ),
                                      ),
                                      // GPS状態を右下に小さく表示
                                      Positioned(
                                        right: 8,
                                        bottom: 8,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              _gpsStatus.contains('成功') ? 'GPS取得成功' : _gpsStatus,
                                              style: TextStyle(
                                                color: Colors.grey[500],
                                                fontSize: 9,
                                              ),
                                            ),
                                            if (_currentPosition?.accuracy != null)
                                              Text(
                                                '精度 ${_currentPosition!.accuracy.toStringAsFixed(1)}m',
                                                style: TextStyle(
                                                  color: Colors.grey[500],
                                                  fontSize: 9,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // 右ブロック：地点情報
                                Expanded(
                                  flex: 2,
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          '行き先',
                                          style: TextStyle(
                                            color: Colors.blue[300],
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          '地点 ${_nextPoint?.no ?? '--'}/${widget.route.points.length}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.visible,
                                          softWrap: false,
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '方向 ${_getDirectionText()}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.visible,
                                          softWrap: false,
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '距離 ${_distanceToNext!.round()}m先',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.visible,
                                          softWrap: false,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Center(
                              child: Text(
                                'GPS情報取得中...',
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 14,
                                ),
                              ),
                            ),
                    ),
                  ),
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

/// 方向矢印を描画するCustomPainter（2等辺三角形）
class _DirectionArrowPainter extends CustomPainter {
  final double relativeBearing; // 目的地への相対方位（-180〜180度）
  final double deviceHeading; // 端末の絶対方位（0〜360度）

  _DirectionArrowPainter({
    required this.relativeBearing,
    required this.deviceHeading,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // 正方形エリアを最大限確保（幅と高さの小さい方を使用）
    final maxSize = size.width < size.height ? size.width : size.height;
    final outerRadius = maxSize * 0.48; // 外側リング半径（大きく）
    final innerRadius = maxSize * 0.32; // 内側リング半径（大きく）
    final ringThickness = outerRadius - innerRadius;

    // 1. ドーナツリング（外側の黒いリング）を描画
    _drawDonutRing(canvas, center, outerRadius, innerRadius);

    // 2. 東西南北の位置に白い丸を描画
    _drawCardinalDots(canvas, center, outerRadius);

    // 3. 大きな2等辺三角形（目的地方向）を描画（頂点が外側の円に接する）
    _drawDirectionTriangle(canvas, center, outerRadius, innerRadius, relativeBearing);

    // 4. 小さな赤い2等辺三角形（磁針/北方位）を中に描画
    _drawCompassNeedle(canvas, center, innerRadius * 0.6, deviceHeading);
  }

  /// ドーナツリング（外側の黒いリング）
  void _drawDonutRing(Canvas canvas, Offset center, double outerRadius, double innerRadius) {
    final paint = Paint()
      ..color = Colors.grey[900]!
      ..style = PaintingStyle.fill;

    // 外側の円を描画
    canvas.drawCircle(center, outerRadius, paint);

    // 内側の円を白で塗りつぶして穴を開ける
    final holePaint = Paint()
      ..color = Colors.grey[850]!
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, innerRadius, holePaint);

    // リングの外縁
    final borderPaint = Paint()
      ..color = Colors.grey[700]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, outerRadius, borderPaint);
    canvas.drawCircle(center, innerRadius, borderPaint);
  }

  /// 東西南北の位置に白い丸を描画
  void _drawCardinalDots(Canvas canvas, Offset center, double radius) {
    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final dotRadius = 6.0;
    final angles = [0.0, 90.0, 180.0, 270.0]; // 上、右、下、左

    for (final angle in angles) {
      final rad = (angle - 90) * 3.141592653589793 / 180; // -90で上が0度に
      final dotCenter = Offset(
        center.dx + radius * cos(rad),
        center.dy + radius * sin(rad),
      );
      canvas.drawCircle(dotCenter, dotRadius, dotPaint);
    }
  }

  /// 大きな2等辺三角形（目的地方向）
  void _drawDirectionTriangle(Canvas canvas, Offset center, double outerRadius, double innerRadius, double bearing) {
    final paint = Paint()
      ..color = Colors.grey[700]!
      ..style = PaintingStyle.fill;

    // 角度をラジアンに変換（上向きを0度として、bearing分回転）
    final angle = (bearing - 90) * 3.141592653589793 / 180;

    // 三角形の3つの頂点を全て外側の円周上に配置
    // 円周角の定理：頂点角度 = 180° - baseAngle
    // 頂点角度45°にするため、baseAngle = 135°
    final baseAngle = 135 * 3.141592653589793 / 180; // 先端から左右への中心角（135度）

    final tip = Offset(
      center.dx + outerRadius * cos(angle),
      center.dy + outerRadius * sin(angle),
    );
    final left = Offset(
      center.dx + outerRadius * cos(angle - baseAngle),
      center.dy + outerRadius * sin(angle - baseAngle),
    );
    final right = Offset(
      center.dx + outerRadius * cos(angle + baseAngle),
      center.dy + outerRadius * sin(angle + baseAngle),
    );

    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();

    canvas.drawPath(path, paint);

    // 輪郭を描画
    final borderPaint = Paint()
      ..color = Colors.grey[500]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(path, borderPaint);
  }

  /// 小さな赤い2等辺三角形（磁針/北方位）
  void _drawCompassNeedle(Canvas canvas, Offset center, double radius, double heading) {
    final paint = Paint()
      ..color = Colors.red[400]!
      ..style = PaintingStyle.fill;

    // 北の方位（常に上向き、端末の回転に合わせて逆回転）
    final angle = (-heading - 90) * 3.141592653589793 / 180;

    // 三角形の頂点を計算（小さめの三角形）
    final tipDistance = radius * 1.2;
    final baseDistance = radius * 0.2;
    final baseWidth = radius * 0.4;

    final tip = Offset(
      center.dx + tipDistance * cos(angle),
      center.dy + tipDistance * sin(angle),
    );
    final left = Offset(
      center.dx + baseDistance * cos(angle) - baseWidth * sin(angle),
      center.dy + baseDistance * sin(angle) + baseWidth * cos(angle),
    );
    final right = Offset(
      center.dx + baseDistance * cos(angle) + baseWidth * sin(angle),
      center.dy + baseDistance * sin(angle) - baseWidth * cos(angle),
    );

    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();

    canvas.drawPath(path, paint);

    // 輪郭を描画
    final borderPaint = Paint()
      ..color = Colors.red[200]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _DirectionArrowPainter oldDelegate) {
    return oldDelegate.relativeBearing != relativeBearing ||
        oldDelegate.deviceHeading != deviceHeading;
  }
}

// cos/sin関数のヘルパー
double cos(double radians) => dart_math.cos(radians);
double sin(double radians) => dart_math.sin(radians);


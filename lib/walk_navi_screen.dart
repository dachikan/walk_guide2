import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'walking_route.dart';
import 'walk_navi_engine.dart';
import 'route_map_screen.dart';

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
  double _currentHeading = 0.0;
  double _deviceHeading = 0.0; // 端末の向き（方位センサー）
  double _bearingToNext = 0.0; // 次の地点への方位

  NaviPoint? _nextPoint;
  double? _distanceToNext;
  
  // 音声ナビ用タイマー
  Timer? _voiceNaviTimer;

  @override
  void initState() {
    super.initState();
    _initializeEngine();
    _startPositionTracking();
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
          _currentHeading = position.heading; // 移動方向
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
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.map, size: 32),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => RouteMapScreen(route: widget.route),
                ),
              );
            },
            tooltip: '地図を表示',
          ),
          IconButton(
            icon: const Icon(Icons.stop, size: 32),
            onPressed: _stopNavigation,
            tooltip: 'ナビゲーション終了',
          ),
        ],
      ),
      body: Column(
        children: [
          // ステータス表示
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: _currentState == NaviState.navigating
                ? Colors.green[900]
                : Colors.grey[900],
            child: Text(
              _getStateText(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // 方位表示（コンパス風）+ 磁針
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                // メイン表示：相対方向コンパス
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Transform.rotate(
                        angle: (_bearingToNext - _deviceHeading) * 3.141592653589793 / 180,
                        child: Icon(
                          Icons.navigation,
                          size: 120,
                          color: Colors.blue[300],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _getDirectionText(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                // 介助者用：小さな磁針（絶対方位）
                Positioned(
                  top: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[700]!, width: 1),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          '介助者用',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // 北を指す磁針
                        Transform.rotate(
                          angle: -_deviceHeading * 3.141592653589793 / 180,
                          child: const Icon(
                            Icons.navigation,
                            size: 24,
                            color: Colors.red,
                          ),
                        ),
                        const Text(
                          'N',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '端末: ${_deviceHeading.round()}°',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                        ),
                        Text(
                          '目的: ${_bearingToNext.round()}°',
                          style: TextStyle(
                            color: Colors.blue[300],
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 次の地点情報
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.grey[900],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '次の地点',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _nextPoint?.message ?? '地点情報なし',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '距離: ${_distanceToNext?.round() ?? '--'} m',
                      style: TextStyle(
                        color: Colors.blue[300],
                        fontSize: 22,
                      ),
                    ),
                    Text(
                      '地点 ${_nextPoint?.no ?? '--'} / ${widget.route.points.length}',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 現在位置表示
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.black,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Text(
                  '緯度: ${_currentPosition?.latitude.toStringAsFixed(5) ?? '--'}',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                Text(
                  '経度: ${_currentPosition?.longitude.toStringAsFixed(5) ?? '--'}',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

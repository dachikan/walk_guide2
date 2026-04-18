import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'walking_route.dart';

/// ナビゲーションエンジン
/// GPS追跡、地点接近判定、音声案内を管理
class WalkNaviEngine {
  final WalkRoute route;
  final FlutterTts tts;
  final Function(NaviState) onStateChanged;

  // すでに案内した地点を記憶（重複案内を防ぐ）
  final Set<int> _announcedPoints = {};

  // GPS追跡ストリーム
  StreamSubscription<Position>? _positionStream;

  // 現在の状態
  NaviState _currentState = NaviState.initial;

  // 前回の位置（移動方向計算用）
  Position? _previousPosition;

  // 現在の歩行方向
  double _walkingDirection = 0.0;

  WalkNaviEngine({
    required this.route,
    required this.tts,
    required this.onStateChanged,
  });

  /// ナビゲーション開始
  Future<void> start() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      final request = await Geolocator.requestPermission();
      if (request == LocationPermission.denied ||
          request == LocationPermission.deniedForever) {
        _updateState(NaviState.error);
        await _speak('位置情報の権限がありません');
        return;
      }
    }

    _updateState(NaviState.navigating);
    await _speak('${route.name}のナビゲーションを開始します。');

    // GPS追跡開始
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 1,
      ),
    ).listen(_onPositionUpdate);
  }

  /// 位置更新時の処理
  void _onPositionUpdate(Position position) {
    // 移動方向を計算
    if (_previousPosition != null) {
      final distance = Geolocator.distanceBetween(
        _previousPosition!.latitude,
        _previousPosition!.longitude,
        position.latitude,
        position.longitude,
      );

      // 2メートル以上移動した場合のみ方向を更新
      if (distance >= 2.0) {
        _walkingDirection = Geolocator.bearingBetween(
          _previousPosition!.latitude,
          _previousPosition!.longitude,
          position.latitude,
          position.longitude,
        );
      }
    }
    _previousPosition = position;

    // ルート上の全地点をチェック
    for (final point in route.points) {
      if (_announcedPoints.contains(point.no)) continue;

      final distance = point.distanceTo(position);

      if (distance <= point.triggerDistance) {
        _announcePoint(point, distance);
        break;
      }
    }

    // 最終地点到達判定
    if (route.points.isNotEmpty) {
      final lastPoint = route.points.last;
      if (!_announcedPoints.contains(lastPoint.no)) {
        final distance = lastPoint.distanceTo(position);
        if (distance <= lastPoint.triggerDistance) {
          _announceGoal();
        }
      }
    }

    _updateState(NaviState.navigating);
  }

  /// 地点案内
  Future<void> _announcePoint(NaviPoint point, double distance) async {
    _announcedPoints.add(point.no);
    final distanceText = distance < 1.0
        ? '${distance.toStringAsFixed(1)}メートル'
        : '${distance.round()}メートル';
    await _speak('${point.message}。距離$distanceText');
  }

  /// 目的地到達案内
  Future<void> _announceGoal() async {
    final lastPoint = route.points.last;
    _announcedPoints.add(lastPoint.no);
    _updateState(NaviState.arrived);
    await _speak('目的地に到着しました。お疲れ様でした。');
  }

  /// 音声出力
  Future<void> _speak(String text) async {
    try {
      await tts.speak(text);
    } catch (e) {
      print('TTS エラー: $e');
    }
  }

  /// 状態更新
  void _updateState(NaviState newState) {
    _currentState = newState;
    onStateChanged(newState);
  }

  /// ナビゲーション停止
  Future<void> stop() async {
    await _positionStream?.cancel();
    _positionStream = null;
    _updateState(NaviState.stopped);
    await _speak('ナビゲーションを終了しました');
  }

  /// 現在の歩行方向を取得
  double get walkingDirection => _walkingDirection;

  /// 現在の状態を取得
  NaviState get currentState => _currentState;

  /// リソース解放
  void dispose() {
    _positionStream?.cancel();
  }
}

/// ナビゲーション状態
enum NaviState {
  initial,
  navigating,
  paused,
  arrived,
  stopped,
  error,
}

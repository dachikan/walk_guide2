import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'walking_route.dart';
import 'common_header.dart';
import 'route_service.dart';

/// ルート地図表示画面
class RouteMapScreen extends StatefulWidget {
  final WalkRoute route;

  const RouteMapScreen({
    super.key,
    required this.route,
  });

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<RouteMapScreen> {
  GoogleMapController? _mapController;
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lngController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _headingController = TextEditingController();
  late List<NaviPoint> _editablePoints;
  int? _activePointIndex;
  int? _midpointFirstIndex;
  bool _isEditPanelVisible = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _editablePoints = widget.route.points
        .map(
          (p) => p.copyWith(),
        )
        .toList();
    _rebuildMapObjects();
    _startLocationTracking();
  }

  void _syncRoutePoints() {
    widget.route.points
      ..clear()
      ..addAll(_editablePoints);
  }

  void _loadPointToEditors(int index) {
    if (index < 0 || index >= _editablePoints.length) return;
    final point = _editablePoints[index];
    _latController.text = point.latitude.toString();
    _lngController.text = point.longitude.toString();
    _messageController.text = point.message;
    _headingController.text = point.heading.toString();
  }

  void _clearEditors() {
    _latController.clear();
    _lngController.clear();
    _messageController.clear();
    _headingController.clear();
  }

  List<NaviPoint> _renumberPoints(List<NaviPoint> points) {
    return List<NaviPoint>.generate(
      points.length,
      (index) => points[index].copyWith(no: index + 1),
    );
  }

  /// ルートのマーカー/ポリラインを再構築
  void _rebuildMapObjects() {
    _markers.clear();
    _polylines.clear();

    debugPrint('=== マーカー設定開始 ===');
    debugPrint('地点数: ${_editablePoints.length}');
    
    for (int i = 0; i < _editablePoints.length; i++) {
      final point = _editablePoints[i];
      final markerColor = i == _activePointIndex
          ? BitmapDescriptor.hueYellow
          : i == _midpointFirstIndex
              ? BitmapDescriptor.hueOrange
              : i == 0
          ? BitmapDescriptor.hueGreen // 開始地点
          : i == _editablePoints.length - 1
              ? BitmapDescriptor.hueRed // 終了地点
              : BitmapDescriptor.hueBlue; // 中間地点
      
      debugPrint('地点${point.no}: (${point.latitude}, ${point.longitude})');
      
      _markers.add(
        Marker(
          markerId: MarkerId('point_${point.no}'),
          position: LatLng(point.latitude, point.longitude),
          onTap: () => _onMarkerTap(i),
          infoWindow: InfoWindow(
            title: point.message,
            snippet: '地点 ${point.no}${i == 0 ? " (開始)" : i == _editablePoints.length - 1 ? " (終了)" : " (中間)"}',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(markerColor),
          zIndex: i == _activePointIndex ? 1000 : (10 + i).toDouble(),
          alpha: 1.0,
        ),
      );
    }

    if (_currentPosition != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: '現在位置'),
          zIndex: 1,
        ),
      );
    }

    final routePath = _editablePoints
        .map((point) => LatLng(point.latitude, point.longitude))
        .toList();

    debugPrint('=== ポリライン設定 ===');
    debugPrint('ポイント数: ${routePath.length}');
    for (int i = 0; i < routePath.length; i++) {
      debugPrint('  ポイント${i + 1}: ${routePath[i].latitude}, ${routePath[i].longitude}');
    }

    _polylines.add(
      Polyline(
        polylineId: const PolylineId('route'),
        points: routePath,
        color: Colors.blue,
        width: 5,
        patterns: [PatternItem.dot, PatternItem.gap(10)],
      ),
    );

    debugPrint('=== マーカー設定完了: ${_markers.length}個 ===');
    debugPrint('=== ポリライン設定完了 ===');
  }

  /// 現在位置の追跡を開始
  Future<void> _startLocationTracking() async {
    try {
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen((position) {
        setState(() {
          _currentPosition = position;
          _rebuildMapObjects();
        });
      });
    } catch (e) {
      // エラー処理
    }
  }

  void _onPointTap(int index) {
    if (index < 0 || index >= _editablePoints.length) return;

    if (_activePointIndex == index && !_isEditPanelVisible) {
      setState(() {
        _isEditPanelVisible = true;
      });
      return;
    }

    setState(() {
      _activePointIndex = index;
      _midpointFirstIndex = null;
      _isEditPanelVisible = false;
      _loadPointToEditors(index);
      _rebuildMapObjects();
    });

    final point = _editablePoints[index];
    _mapController?.animateCamera(
      CameraUpdate.newLatLng(
        LatLng(point.latitude, point.longitude),
      ),
    );
  }

  void _onMarkerTap(int index) {
    if (index < 0 || index >= _editablePoints.length) return;

    setState(() {
      _activePointIndex = index;
      _midpointFirstIndex = null;
      _isEditPanelVisible = false;
      _loadPointToEditors(index);
      _rebuildMapObjects();
    });
  }

  void _onMapTap(LatLng _) {
    if (!_isEditPanelVisible) return;
    setState(() {
      _isEditPanelVisible = false;
    });
  }

  void _deletePoint(int index) {
    if (index < 0 || index >= _editablePoints.length) return;

    final removed = _editablePoints[index];
    final updated = List<NaviPoint>.from(_editablePoints)..removeAt(index);

    setState(() {
      _editablePoints = _renumberPoints(updated);
      _activePointIndex = null;
      _midpointFirstIndex = null;
      _isEditPanelVisible = false;
      _clearEditors();
      _rebuildMapObjects();
      _syncRoutePoints();
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('地点${removed.no}を削除しました')),
      );
    }
  }

  void _insertMidpointBetween(int a, int b) {
    if (a < 0 || b < 0 || a >= _editablePoints.length || b >= _editablePoints.length || a == b) {
      return;
    }

    final first = _editablePoints[a];
    final second = _editablePoints[b];
    final insertAt = a < b ? a + 1 : b + 1;
    final midpoint = NaviPoint(
      no: 0,
      latitude: (first.latitude + second.latitude) / 2,
      longitude: (first.longitude + second.longitude) / 2,
      heading: (first.heading + second.heading) / 2,
      triggerDistance: (first.triggerDistance + second.triggerDistance) / 2,
      message: '中間地点',
    );

    final updated = List<NaviPoint>.from(_editablePoints)..insert(insertAt, midpoint);

    setState(() {
      _editablePoints = _renumberPoints(updated);
      _activePointIndex = insertAt;
      _midpointFirstIndex = null;
      _isEditPanelVisible = false;
      _loadPointToEditors(insertAt);
      _rebuildMapObjects();
      _syncRoutePoints();
    });

    final newPoint = _editablePoints[insertAt];
    _mapController?.animateCamera(
      CameraUpdate.newLatLng(
        LatLng(newPoint.latitude, newPoint.longitude),
      ),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('地点${first.no}と地点${second.no}の中間地点を追加しました')),
      );
    }
  }

  void _onPointLongPress(int index) {
    if (index < 0 || index >= _editablePoints.length) return;

    if (_midpointFirstIndex == null) {
      setState(() {
        _midpointFirstIndex = index;
        _activePointIndex = index;
        _isEditPanelVisible = false;
        _loadPointToEditors(index);
        _rebuildMapObjects();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('地点${_editablePoints[index].no}を選択中: 同じ地点を再度長押しで削除、別地点を長押しで中間地点を追加')),
        );
      }
      return;
    }

    if (_midpointFirstIndex == index) {
      _deletePoint(index);
      return;
    }

    _insertMidpointBetween(_midpointFirstIndex!, index);
  }

  String _sanitizeFileName(String input) {
    return input.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  }

  bool _applySelectedPointEdits({bool showFeedback = true}) {
    final index = _activePointIndex;
    if (index == null || index < 0 || index >= _editablePoints.length) {
      return true;
    }

    final latitude = double.tryParse(_latController.text.trim());
    final longitude = double.tryParse(_lngController.text.trim());
    final heading = double.tryParse(_headingController.text.trim());
    final message = _messageController.text.trim();

    if (latitude == null || longitude == null || heading == null) {
      if (showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('緯度・経度・方向は数値で入力してください')),
        );
      }
      return false;
    }

    setState(() {
      _editablePoints[index] = _editablePoints[index].copyWith(
        latitude: latitude,
        longitude: longitude,
        heading: heading,
        message: message.isEmpty ? '地点${_editablePoints[index].no}' : message,
      );
      _rebuildMapObjects();
      _syncRoutePoints();
    });

    _mapController?.animateCamera(
      CameraUpdate.newLatLng(
        LatLng(latitude, longitude),
      ),
    );

    if (showFeedback) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('地点${_editablePoints[index].no}を更新しました')),
      );
    }

    return true;
  }

  Future<void> _saveEditedRoute() async {
    if (_editablePoints.isEmpty || _isSaving) return;

    if (!_applySelectedPointEdits(showFeedback: false)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存前に入力内容を確認してください')),
        );
      }
      return;
    }

    final safeName = _sanitizeFileName(widget.route.name.trim());
    if (safeName.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存できません: ルート名が不正です')),
        );
      }
      return;
    }

    final fileName = '$safeName.csv';

    setState(() {
      _isSaving = true;
    });

    try {
      _syncRoutePoints();
      final routeToSave = WalkRoute(name: widget.route.name, points: List<NaviPoint>.from(_editablePoints));
      await RouteService.saveRoute(routeToSave, fileName);

      if (mounted) {
        setState(() {
          _midpointFirstIndex = null;
          _isEditPanelVisible = false;
          _rebuildMapObjects();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存しました: $fileName')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  /// 地図が作成されたときの処理
  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    _fitRouteInView();
  }

  /// ルート全体が見えるようにカメラを調整
  void _fitRouteInView() {
    if (_editablePoints.isEmpty) return;

    double minLat = _editablePoints.first.latitude;
    double maxLat = _editablePoints.first.latitude;
    double minLng = _editablePoints.first.longitude;
    double maxLng = _editablePoints.first.longitude;

    for (final point in _editablePoints) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    // 緯度・経度の差分を計算
    final latDiff = maxLat - minLat;
    final lngDiff = maxLng - minLng;
    
    debugPrint('ルート範囲: 緯度差=${latDiff}, 経度差=${lngDiff}');
    
    // 地点が非常に近い場合（約50m以内）は固定ズームレベルを使用
    if (latDiff < 0.0005 && lngDiff < 0.0005) {
      // 中心点を計算
      final centerLat = (minLat + maxLat) / 2;
      final centerLng = (minLng + maxLng) / 2;
      debugPrint('近距離ルート: 中心点=(${centerLat}, ${centerLng}), ズームレベル=18');
      
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(centerLat, centerLng),
          18, // 近距離の場合は高ズームレベル
        ),
      );
    } else {
      // 通常の範囲表示
      final bounds = LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      );
      debugPrint('通常ルート: bounds表示');
      
      _mapController?.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 50),
      );
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _mapController?.dispose();
    _latController.dispose();
    _lngController.dispose();
    _messageController.dispose();
    _headingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: CommonAppBar(
          pageTitle: '${widget.route.name} - 地図',
          onAIChanged: () {
            // AI変更時の処理（必要に応じて）
          },
        ),
      ),
      body: _editablePoints.isEmpty
          ? const Center(
              child: Text(
                'ルートデータがありません',
                style: TextStyle(fontSize: 18),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      GoogleMap(
                        onMapCreated: _onMapCreated,
                        onTap: _onMapTap,
                        initialCameraPosition: CameraPosition(
                          target: LatLng(
                            _editablePoints.first.latitude,
                            _editablePoints.first.longitude,
                          ),
                          zoom: 18,
                        ),
                        markers: _markers,
                        polylines: _polylines,
                        myLocationEnabled: true,
                        myLocationButtonEnabled: false,
                        mapType: MapType.normal,
                        compassEnabled: true,
                        zoomControlsEnabled: false,
                      ),
                      Positioned(
                        top: 16,
                        right: 16,
                        child: Column(
                          children: [
                            FloatingActionButton(
                              heroTag: 'my_location',
                              mini: true,
                              backgroundColor: Colors.white,
                              child: const Icon(Icons.my_location, color: Colors.blue),
                              onPressed: () {
                                if (_currentPosition != null) {
                                  _mapController?.animateCamera(
                                    CameraUpdate.newLatLngZoom(
                                      LatLng(
                                        _currentPosition!.latitude,
                                        _currentPosition!.longitude,
                                      ),
                                      16,
                                    ),
                                  );
                                }
                              },
                            ),
                            const SizedBox(height: 8),
                            FloatingActionButton(
                              heroTag: 'zoom_out',
                              mini: true,
                              backgroundColor: Colors.white,
                              child: const Icon(Icons.zoom_out_map, color: Colors.blue),
                              onPressed: _fitRouteInView,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  color: Colors.black87,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '登録地点: ${_editablePoints.length}箇所',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: _saveEditedRoute,
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: _isSaving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    )
                                  : const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.save, color: Colors.white, size: 16),
                                        SizedBox(width: 4),
                                        Text(
                                          '保存',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 60,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _editablePoints.length,
                          itemBuilder: (context, index) {
                            final point = _editablePoints[index];
                            final markerColor = index == _activePointIndex
                                ? Colors.yellow
                                : index == _midpointFirstIndex
                                    ? Colors.orange
                                    : index == 0
                                        ? Colors.green
                                        : index == _editablePoints.length - 1
                                            ? Colors.red
                                            : Colors.blue;
                            final label = index == _midpointFirstIndex
                                ? '基準'
                                : index == 0
                                    ? '開始'
                                    : index == _editablePoints.length - 1
                                        ? '終了'
                                        : '中間';

                            final textColor = index == _activePointIndex || index == _midpointFirstIndex
                                ? Colors.black87
                                : markerColor;

                            return GestureDetector(
                              onTap: () => _onPointTap(index),
                              onLongPress: () => _onPointLongPress(index),
                              child: Container(
                                width: 100,
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: markerColor.withOpacity(index == _activePointIndex || index == _midpointFirstIndex ? 0.72 : 0.28),
                                  border: Border.all(color: markerColor, width: 2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      point.message,
                                      style: TextStyle(
                                        color: textColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                    ),
                                    Text(
                                      '地点${point.no} / $label',
                                      style: TextStyle(
                                        color: textColor,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      if (_activePointIndex != null && _isEditPanelVisible) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.yellow.shade700, width: 2),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '地点${_editablePoints[_activePointIndex!].no}を編集',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _latController,
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                                      decoration: const InputDecoration(
                                        labelText: '緯度',
                                        isDense: true,
                                        filled: true,
                                        fillColor: Colors.white,
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: _lngController,
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                                      decoration: const InputDecoration(
                                        labelText: '経度',
                                        isDense: true,
                                        filled: true,
                                        fillColor: Colors.white,
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _messageController,
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w600,
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'コメント',
                                  isDense: true,
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _headingController,
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                                      decoration: const InputDecoration(
                                        labelText: '方向',
                                        isDense: true,
                                        filled: true,
                                        fillColor: Colors.white,
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton(
                                    onPressed: () => _applySelectedPointEdits(),
                                    child: const Text('反映'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

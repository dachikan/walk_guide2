import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'walking_route.dart';
import 'common_header.dart';

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

  @override
  void initState() {
    super.initState();
    _setupRouteMarkers();
    _setupPolyline();
    _startLocationTracking();
  }

  /// ルートのマーカーを設定
  void _setupRouteMarkers() {
    debugPrint('=== マーカー設定開始 ===');
    debugPrint('地点数: ${widget.route.points.length}');
    
    for (int i = 0; i < widget.route.points.length; i++) {
      final point = widget.route.points[i];
      final markerColor = i == 0
          ? BitmapDescriptor.hueGreen // 開始地点
          : i == widget.route.points.length - 1
              ? BitmapDescriptor.hueRed // 終了地点
              : BitmapDescriptor.hueBlue; // 中間地点
      
      debugPrint('地点${point.no}: (${point.latitude}, ${point.longitude}) - 色: ${i == 0 ? "緑" : i == widget.route.points.length - 1 ? "赤" : "青"}');
      
      _markers.add(
        Marker(
          markerId: MarkerId('point_${point.no}'),
          position: LatLng(point.latitude, point.longitude),
          infoWindow: InfoWindow(
            title: '地点 ${point.no}${i == 0 ? " (開始)" : i == widget.route.points.length - 1 ? " (終了)" : " (中間)"}',
            snippet: point.message,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(markerColor),
          // マーカーを見やすくするため、ラベルを追加
          alpha: 1.0,
        ),
      );
    }
    debugPrint('=== マーカー設定完了: ${_markers.length}個 ===');
  }

  /// ルートのポリラインを設定
  void _setupPolyline() {
    final routePath = widget.route.points
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
          _updateCurrentLocationMarker(position);
        });
      });
    } catch (e) {
      // エラー処理
    }
  }

  /// 現在位置のマーカーを更新
  void _updateCurrentLocationMarker(Position position) {
    _markers.removeWhere((m) => m.markerId.value == 'current_location');
    _markers.add(
      Marker(
        markerId: const MarkerId('current_location'),
        position: LatLng(position.latitude, position.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: '現在位置'),
      ),
    );
  }

  /// 地図が作成されたときの処理
  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    _fitRouteInView();
  }

  /// ルート全体が見えるようにカメラを調整
  void _fitRouteInView() {
    if (widget.route.points.isEmpty) return;

    double minLat = widget.route.points.first.latitude;
    double maxLat = widget.route.points.first.latitude;
    double minLng = widget.route.points.first.longitude;
    double maxLng = widget.route.points.first.longitude;

    for (final point in widget.route.points) {
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
      body: widget.route.points.isEmpty
          ? const Center(
              child: Text(
                'ルートデータがありません',
                style: TextStyle(fontSize: 18),
              ),
            )
          : Stack(
              children: [
                // 地図表示
                GoogleMap(
                  onMapCreated: _onMapCreated,
                  initialCameraPosition: CameraPosition(
                    target: LatLng(
                      widget.route.points.first.latitude,
                      widget.route.points.first.longitude,
                    ),
                    zoom: 18, // ズームレベルを上げて近距離の地点を区別しやすく
                  ),
                  markers: _markers,
                  polylines: _polylines,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  mapType: MapType.normal,
                  compassEnabled: true,
                  zoomControlsEnabled: false,
                ),
                // 右上に操作ボタン
                Positioned(
                  top: 16,
                  right: 16,
                  child: Column(
                    children: [
                      // 現在位置に移動ボタン
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
                      // ルート全体を表示ボタン
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
                // 画面下部に地点リスト表示
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    color: Colors.black87,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '登録地点: ${widget.route.points.length}箇所',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 60,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: widget.route.points.length,
                            itemBuilder: (context, index) {
                              final point = widget.route.points[index];
                              final markerColor = index == 0
                                  ? Colors.green
                                  : index == widget.route.points.length - 1
                                      ? Colors.red
                                      : Colors.blue;
                              final label = index == 0
                                  ? "開始"
                                  : index == widget.route.points.length - 1
                                      ? "終了"
                                      : "中間";
                              
                              return GestureDetector(
                                onTap: () {
                                  // 地点に移動
                                  _mapController?.animateCamera(
                                    CameraUpdate.newLatLngZoom(
                                      LatLng(point.latitude, point.longitude),
                                      18,
                                    ),
                                  );
                                },
                                child: Container(
                                  width: 100,
                                  margin: const EdgeInsets.only(right: 8),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: markerColor.withOpacity(0.2),
                                    border: Border.all(color: markerColor, width: 2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        '地点${point.no}',
                                        style: TextStyle(
                                          color: markerColor,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        label,
                                        style: TextStyle(
                                          color: markerColor,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
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

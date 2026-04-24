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
    for (int i = 0; i < widget.route.points.length; i++) {
      final point = widget.route.points[i];
      _markers.add(
        Marker(
          markerId: MarkerId('point_${point.no}'),
          position: LatLng(point.latitude, point.longitude),
          infoWindow: InfoWindow(
            title: '地点 ${point.no}',
            snippet: point.message,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            i == 0
                ? BitmapDescriptor.hueGreen // 開始地点
                : i == widget.route.points.length - 1
                    ? BitmapDescriptor.hueRed // 終了地点
                    : BitmapDescriptor.hueBlue, // 中間地点
          ),
        ),
      );
    }
  }

  /// ルートのポリラインを設定
  void _setupPolyline() {
    final routePath = widget.route.points
        .map((point) => LatLng(point.latitude, point.longitude))
        .toList();

    _polylines.add(
      Polyline(
        polylineId: const PolylineId('route'),
        points: routePath,
        color: Colors.blue,
        width: 5,
        patterns: [PatternItem.dot, PatternItem.gap(10)],
      ),
    );
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

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 50),
    );
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
                    zoom: 15,
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
              ],
            ),
    );
  }
}

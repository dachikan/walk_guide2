import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'common_header.dart';
import 'route_service.dart';
import 'walking_route.dart';

/// ルート初期作成画面
class RouteEditScreen extends StatefulWidget {
  final WalkRoute? initialRoute;
  final bool isNewRoute;
  final String? originalFileName;

  const RouteEditScreen({
    Key? key,
    this.initialRoute,
    this.isNewRoute = true,
    this.originalFileName,
  }) : super(key: key);

  @override
  State<RouteEditScreen> createState() => _RouteEditScreenState();
}

class _RouteEditScreenState extends State<RouteEditScreen> {
  late TextEditingController _routeNameController;
  late TextEditingController _stepIntervalController;
  late List<NaviPoint> _points;

  bool _isSaving = false;
  bool _isAutoRegistering = false;

  StreamSubscription<Position>? _positionSubscription;
  Position? _lastAutoPosition;
  double _accumulatedMeters = 0.0;
  double _autoRegisterMeters = 3.5;

  static const double _duplicateThresholdMeters = 1.0;
  static const double _estimatedMetersPerStep = 0.7;
  static const double _colNoWidth = 40;
  static const double _colLatWidth = 94;
  static const double _colLonWidth = 94;
  static const double _colHeadingWidth = 52;

  @override
  void initState() {
    super.initState();

    if (widget.initialRoute != null) {
      _routeNameController = TextEditingController(text: widget.initialRoute!.name);
      _points = List.from(widget.initialRoute!.points);
    } else {
      _routeNameController = TextEditingController();
      _points = [];
    }

    _stepIntervalController = TextEditingController(text: '5');
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _routeNameController.dispose();
    _stepIntervalController.dispose();
    super.dispose();
  }

  Future<bool> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('位置情報サービスがOFFです')),
        );
      }
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('位置情報の権限が必要です')),
        );
      }
      return false;
    }

    return true;
  }

  bool _addPointFromPosition(
    Position position, {
    bool showAddedMessage = false,
    bool showDuplicateMessage = true,
  }) {
    if (_points.isNotEmpty) {
      final lastPoint = _points.last;
      final distance = Geolocator.distanceBetween(
        lastPoint.latitude,
        lastPoint.longitude,
        position.latitude,
        position.longitude,
      );

      if (distance < _duplicateThresholdMeters) {
        if (showDuplicateMessage && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('直前地点から1m以内のため追加しませんでした')),
          );
        }
        return false;
      }
    }

    setState(() {
      _points.add(
        NaviPoint(
          no: _points.length + 1,
          latitude: position.latitude,
          longitude: position.longitude,
          heading: 0.0,
          triggerDistance: 10.0,
          message: '地点${_points.length + 1}',
        ),
      );
    });

    if (showAddedMessage && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('地点${_points.length}を追加しました')),
      );
    }

    return true;
  }

  Future<void> _addCurrentLocation() async {
    try {
      final allowed = await _ensureLocationPermission();
      if (!allowed) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      _addPointFromPosition(position, showAddedMessage: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('位置取得エラー: $e')),
        );
      }
    }
  }

  Future<void> _toggleAutoRegister() async {
    if (_isAutoRegistering) {
      await _stopAutoRegister();
      return;
    }

    final steps = int.tryParse(_stepIntervalController.text.trim()) ?? 5;
    final clampedSteps = math.max(1, steps);
    _autoRegisterMeters = clampedSteps * _estimatedMetersPerStep;

    final allowed = await _ensureLocationPermission();
    if (!allowed) {
      return;
    }

    setState(() {
      _isAutoRegistering = true;
      _accumulatedMeters = 0.0;
      _lastAutoPosition = null;
    });

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 1,
      ),
    ).listen(_onAutoPosition, onError: (Object e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('自動登録エラー: $e')),
        );
      }
      _stopAutoRegister();
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${clampedSteps}歩ごとの自動登録を開始しました')),
      );
    }
  }

  void _onAutoPosition(Position position) {
    if (!_isAutoRegistering) {
      return;
    }

    if (_lastAutoPosition == null) {
      _lastAutoPosition = position;
      _addPointFromPosition(position, showDuplicateMessage: false);
      return;
    }

    final segment = Geolocator.distanceBetween(
      _lastAutoPosition!.latitude,
      _lastAutoPosition!.longitude,
      position.latitude,
      position.longitude,
    );

    _lastAutoPosition = position;
    _accumulatedMeters += segment;

    if (_accumulatedMeters >= _autoRegisterMeters) {
      final added = _addPointFromPosition(position, showDuplicateMessage: false);
      if (added) {
        _accumulatedMeters = 0.0;
      }
    }
  }

  Future<void> _stopAutoRegister() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;

    if (!mounted) {
      return;
    }

    setState(() {
      _isAutoRegistering = false;
      _accumulatedMeters = 0.0;
      _lastAutoPosition = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('自動登録を停止しました')),
    );
  }

  void _renumberPoints() {
    if (_points.isEmpty) {
      return;
    }

    setState(() {
      for (int i = 0; i < _points.length; i++) {
        _points[i] = _points[i].copyWith(no: i + 1, message: '地点${i + 1}');
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('番号を振り直しました')),
    );
  }

  String _sanitizeFileName(String name) {
    // 全角文字はそのまま保持し、ファイル名として使えない記号のみ_に置換
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  Future<void> _saveRoute() async {
    if (_routeNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ルート名を入力してください')),
      );
      return;
    }

    if (_points.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('地点を1つ以上追加してください')),
      );
      return;
    }

    final safeName = _sanitizeFileName(_routeNameController.text.trim());
    if (safeName.isEmpty || safeName.replaceAll('_', '').isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('有効なルート名を入力してください')),
      );
      return;
    }

    final targetFileName = '$safeName.csv';
    final originalFileName = widget.originalFileName;
    final isRenamedExistingRoute =
        !widget.isNewRoute &&
        originalFileName != null &&
        originalFileName != targetFileName;

    setState(() {
      _isSaving = true;
    });

    try {
      final route = WalkRoute(
        name: _routeNameController.text.trim(),
        points: _points,
      );

      await RouteService.saveRoute(route, targetFileName);

      if (isRenamedExistingRoute) {
        await RouteService.deleteRoute(originalFileName);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ルートを保存しました')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存エラー: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
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

  double _distanceFromPrevious(int index) {
    if (index == 0) {
      return 0.0;
    }

    final prev = _points[index - 1];
    final curr = _points[index];
    return Geolocator.distanceBetween(
      prev.latitude,
      prev.longitude,
      curr.latitude,
      curr.longitude,
    );
  }

  Widget _buildHeaderRow() {
    const compactHeaderStyle = TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.bold,
    );
    const headerStyle = TextStyle(
      color: Colors.white,
      fontSize: 16,
      fontWeight: FontWeight.bold,
    );

    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(width: _colNoWidth, child: Text('No', style: compactHeaderStyle)),
          SizedBox(width: _colLatWidth, child: Text('緯度', style: compactHeaderStyle)),
          SizedBox(width: _colLonWidth, child: Text('経度', style: compactHeaderStyle)),
          SizedBox(width: _colHeadingWidth, child: Text('方向', style: headerStyle)),
          Expanded(child: Text('コメント', style: headerStyle, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _buildPointRow(int index) {
    final point = _points[index];
    const compactValueStyle = TextStyle(
      color: Colors.white,
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );
    const valueStyle = TextStyle(
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );

    return Container(
      color: index.isEven ? Colors.black : Colors.grey[900],
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(width: _colNoWidth, child: Text('${point.no}', style: compactValueStyle)),
          SizedBox(
            width: _colLatWidth,
            child: Text(point.latitude.toStringAsFixed(5), style: compactValueStyle),
          ),
          SizedBox(
            width: _colLonWidth,
            child: Text(point.longitude.toStringAsFixed(5), style: compactValueStyle),
          ),
          SizedBox(
            width: _colHeadingWidth,
            child: Text(point.heading.toStringAsFixed(0), style: valueStyle),
          ),
          Expanded(
            child: Text(
              point.message,
              style: valueStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: CommonAppBar(
          pageTitle: 'ルート初期作成',
          onAIChanged: () {},
        ),
      ),
      body: Column(
        children: [
          Container(
            color: Colors.black,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.my_location),
                    label: const Text(
                      '現在位置\n追加',
                      textAlign: TextAlign.center,
                    ),
                    onPressed: _addCurrentLocation,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      textStyle: const TextStyle(fontSize: 13, height: 1.15),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: Icon(_isAutoRegistering ? Icons.pause : Icons.directions_walk),
                    label: const Text(
                      '自動登録\n間隔',
                      textAlign: TextAlign.center,
                    ),
                    onPressed: _toggleAutoRegister,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isAutoRegistering ? Colors.orange[700] : Colors.blue[700],
                      minimumSize: const Size.fromHeight(56),
                      textStyle: const TextStyle(fontSize: 13, height: 1.15),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 64,
                  child: TextField(
                    controller: _stepIntervalController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: '歩数',
                      labelStyle: TextStyle(color: Colors.grey[300]),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey[600]!),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            color: Colors.black,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _routeNameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'ルート名',
                      labelStyle: TextStyle(color: Colors.grey[300]),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey[600]!),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 132,
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.save),
                          label: const Text('保存'),
                          onPressed: _isSaving ? null : _saveRoute,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.format_list_numbered),
                          label: const Text('リナンバー'),
                          onPressed: _renumberPoints,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _buildHeaderRow(),
          Expanded(
            child: _points.isEmpty
                ? const Center(
                    child: Text(
                      '現在位置追加 または 自動登録開始で地点を作成してください',
                      style: TextStyle(color: Colors.white70, fontSize: 18),
                    ),
                  )
                : ListView.builder(
                    itemCount: _points.length,
                    itemBuilder: (context, index) => _buildPointRow(index),
                  ),
          ),
        ],
      ),
    );
  }
}

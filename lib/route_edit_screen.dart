import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'walking_route.dart';
import 'route_service.dart';
import 'common_header.dart';

/// ルート編集画面
class RouteEditScreen extends StatefulWidget {
  final WalkRoute? initialRoute; // 既存ルート編集の場合
  final bool isNewRoute; // 新規作成かどうか

  const RouteEditScreen({
    Key? key,
    this.initialRoute,
    this.isNewRoute = true,
  }) : super(key: key);

  @override
  State<RouteEditScreen> createState() => _RouteEditScreenState();
}

class _RouteEditScreenState extends State<RouteEditScreen> {
  late TextEditingController _routeNameController;
  late List<NaviPoint> _points;
  bool _isSaving = false;

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
  }

  @override
  void dispose() {
    _routeNameController.dispose();
    super.dispose();
  }

  /// 現在位置を新しい地点として追加
  void _addCurrentLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      setState(() {
        _points.add(NaviPoint(
          no: _points.length + 1,
          latitude: position.latitude,
          longitude: position.longitude,
          heading: 0.0,
          triggerDistance: 10.0,
          message: '地点${_points.length + 1}',
        ));
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('現在位置を追加しました')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('位置取得エラー: $e')),
      );
    }
  }

  /// 地点を手動で追加
  void _addPointManually() {
    showDialog(
      context: context,
      builder: (context) {
        final latController = TextEditingController();
        final lonController = TextEditingController();
        final msgController = TextEditingController(text: '地点${_points.length + 1}');

        return AlertDialog(
          title: const Text('地点を追加'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: latController,
                decoration: const InputDecoration(labelText: '緯度'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: lonController,
                decoration: const InputDecoration(labelText: '経度'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: msgController,
                decoration: const InputDecoration(labelText: 'メッセージ'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () {
                final lat = double.tryParse(latController.text);
                final lon = double.tryParse(lonController.text);

                if (lat != null && lon != null) {
                  setState(() {
                    _points.add(NaviPoint(
                      no: _points.length + 1,
                      latitude: lat,
                      longitude: lon,
                      heading: 0.0,
                      triggerDistance: 10.0,
                      message: msgController.text,
                    ));
                  });
                  Navigator.pop(context);
                }
              },
              child: const Text('追加'),
            ),
          ],
        );
      },
    );
  }

  /// 地点を編集
  void _editPoint(int index) {
    final point = _points[index];
    
    showDialog(
      context: context,
      builder: (context) {
        final latController = TextEditingController(text: point.latitude.toString());
        final lonController = TextEditingController(text: point.longitude.toString());
        final msgController = TextEditingController(text: point.message);
        final distController = TextEditingController(text: point.triggerDistance.toString());

        return AlertDialog(
          title: Text('地点${point.no}を編集'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: latController,
                  decoration: const InputDecoration(labelText: '緯度'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: lonController,
                  decoration: const InputDecoration(labelText: '経度'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: msgController,
                  decoration: const InputDecoration(labelText: 'メッセージ'),
                ),
                TextField(
                  controller: distController,
                  decoration: const InputDecoration(labelText: 'トリガー距離(m)'),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () {
                final lat = double.tryParse(latController.text);
                final lon = double.tryParse(lonController.text);
                final dist = double.tryParse(distController.text);

                if (lat != null && lon != null && dist != null) {
                  setState(() {
                    _points[index] = _points[index].copyWith(
                      latitude: lat,
                      longitude: lon,
                      message: msgController.text,
                      triggerDistance: dist,
                    );
                  });
                  Navigator.pop(context);
                }
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  /// 地点を削除
  void _deletePoint(int index) {
    setState(() {
      _points.removeAt(index);
      // 地点番号を振り直す
      for (int i = 0; i < _points.length; i++) {
        _points[i] = _points[i].copyWith(no: i + 1);
      }
    });
  }

  /// 地点を上に移動
  void _movePointUp(int index) {
    if (index > 0) {
      setState(() {
        final temp = _points[index];
        _points[index] = _points[index - 1];
        _points[index - 1] = temp;
        // 地点番号を振り直す
        for (int i = 0; i < _points.length; i++) {
          _points[i] = _points[i].copyWith(no: i + 1);
        }
      });
    }
  }

  /// 地点を下に移動
  void _movePointDown(int index) {
    if (index < _points.length - 1) {
      setState(() {
        final temp = _points[index];
        _points[index] = _points[index + 1];
        _points[index + 1] = temp;
        // 地点番号を振り直す
        for (int i = 0; i < _points.length; i++) {
          _points[i] = _points[i].copyWith(no: i + 1);
        }
      });
    }
  }

  /// ルートを保存
  void _saveRoute() async {
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

    setState(() {
      _isSaving = true;
    });

    try {
      final route = WalkRoute(
        name: _routeNameController.text.trim(),
        points: _points,
      );

      final fileName = '${_routeNameController.text.trim()}.csv';
      await RouteService.saveRoute(route, fileName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ルートを保存しました')),
        );
        Navigator.pop(context, true); // 保存成功を通知
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存エラー: $e')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: CommonAppBar(
          pageTitle: widget.isNewRoute ? 'ルート新規作成' : 'ルート編集',
          onAIChanged: () {
            // AI変更時の処理（必要に応じて）
          },
        ),
      ),
      body: Column(
        children: [
          // 保存ボタンのツールバー
          Container(
            height: 50,
            color: Colors.grey[200],
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('保存'),
                  onPressed: _isSaving ? null : _saveRoute,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[700],
                  ),
                ),
              ],
            ),
          ),
          // ルート名入力
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _routeNameController,
              decoration: const InputDecoration(
                labelText: 'ルート名',
                border: OutlineInputBorder(),
              ),
            ),
          ),

          // 地点追加ボタン
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.my_location),
                    label: const Text('現在位置'),
                    onPressed: _addCurrentLocation,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('手動追加'),
                    onPressed: _addPointManually,
                  ),
                ),
              ],
            ),
          ),

          const Divider(),

          // 地点リスト
          Expanded(
            child: _points.isEmpty
                ? const Center(
                    child: Text(
                      '地点を追加してください',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: _points.length,
                    itemBuilder: (context, index) {
                      final point = _points[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text('${point.no}'),
                          ),
                          title: Text(point.message),
                          subtitle: Text(
                            '緯度: ${point.latitude.toStringAsFixed(5)}\n'
                            '経度: ${point.longitude.toStringAsFixed(5)}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_upward, size: 20),
                                onPressed: index == 0 ? null : () => _movePointUp(index),
                              ),
                              IconButton(
                                icon: const Icon(Icons.arrow_downward, size: 20),
                                onPressed: index == _points.length - 1
                                    ? null
                                    : () => _movePointDown(index),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit, size: 20),
                                onPressed: () => _editPoint(index),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                                onPressed: () => _deletePoint(index),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // 総距離表示
          if (_points.length >= 2)
            Container(
              padding: const EdgeInsets.all(16.0),
              color: Colors.grey[200],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.straighten),
                  const SizedBox(width: 8),
                  Text(
                    '総距離: ${WalkRoute(name: '', points: _points).getTotalDistance().toStringAsFixed(0)}m',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

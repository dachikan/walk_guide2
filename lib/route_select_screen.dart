import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'route_service.dart';
import 'walk_navi_screen.dart';
import 'route_edit_screen.dart';
import 'common_header.dart';

/// ルート選択画面
class RouteSelectScreen extends StatefulWidget {
  final FlutterTts tts;

  const RouteSelectScreen({
    super.key,
    required this.tts,
  });

  @override
  State<RouteSelectScreen> createState() => _RouteSelectScreenState();
}

class _RouteSelectScreenState extends State<RouteSelectScreen> {
  List<RouteInfo> _routes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRoutes();
  }

  Future<void> _loadRoutes() async {
    try {
      final routes = await RouteService.getAvailableRoutes();
      setState(() {
        _routes = routes;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showError('ルート一覧の読み込みに失敗しました: $e');
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

  Future<void> _selectRoute(RouteInfo routeInfo) async {
    try {
      print('[RouteSelectScreen] ルート選択: ${routeInfo.fileName}');
      print('[RouteSelectScreen] カスタム: ${routeInfo.isCustom}');
      
      final route = await RouteService.loadRoute(routeInfo.fileName, isCustom: routeInfo.isCustom);
      
      print('[RouteSelectScreen] ルート読み込み成功');
      print('[RouteSelectScreen] ルート名: ${route.name}');
      print('[RouteSelectScreen] 地点数: ${route.points.length}');
      
      await widget.tts.speak('${routeInfo.displayName}を読み込みました。ナビゲーションを開始します。');

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => WalkNaviScreen(
              route: route,
              tts: widget.tts,
            ),
          ),
        );
      }
    } catch (e, stackTrace) {
      print('[RouteSelectScreen] ルート読み込みエラー: $e');
      print('[RouteSelectScreen] スタックトレース: $stackTrace');
      _showError('ルートの読み込みに失敗しました: $e');
    }
  }

  /// ルート編集画面を開く
  Future<void> _editRoute(RouteInfo routeInfo) async {
    try {
      final route = await RouteService.loadRoute(routeInfo.fileName, isCustom: routeInfo.isCustom);
      
      if (mounted) {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RouteEditScreen(
              initialRoute: route,
              isNewRoute: false,
              originalFileName: routeInfo.fileName,
            ),
          ),
        );

        // 保存された場合はリロード
        if (result == true) {
          _loadRoutes();
        }
      }
    } catch (e) {
      _showError('ルートの読み込みに失敗しました: $e');
    }
  }

  /// 新規ルート作成画面を開く
  Future<void> _createNewRoute() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const RouteEditScreen(
          isNewRoute: true,
        ),
      ),
    );

    // 保存された場合はリロード
    if (result == true) {
      _loadRoutes();
    }
  }

  /// ルート削除確認
  Future<void> _deleteRoute(RouteInfo routeInfo) async {
    if (!routeInfo.isCustom) {
      _showError('組み込みルートは削除できません');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ルート削除'),
        content: Text('「${routeInfo.displayName}」を削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await RouteService.deleteRoute(routeInfo.fileName);
        _loadRoutes();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ルートを削除しました')),
          );
        }
      } catch (e) {
        _showError('削除に失敗しました: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: CommonAppBar(
          pageTitle: 'ルート選択',
          onAIChanged: () {},
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : _routes.isEmpty
                    ? Center(
                        child: Text(
                          'ルートが見つかりません',
                          style: TextStyle(color: Colors.white, fontSize: 24),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _routes.length,
                        itemBuilder: (context, index) {
                          final route = _routes[index];
                          return Card(
                            color: Colors.grey[900],
                            margin: const EdgeInsets.only(bottom: 16),
                            child: InkWell(
                              onTap: () => _selectRoute(route),
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            route.displayName,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 28,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        if (route.isCustom)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.blue[700],
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Text(
                                              'カスタム',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      route.description,
                                      style: TextStyle(
                                        color: Colors.grey[400],
                                        fontSize: 18,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        if (route.isCustom) ...[
                                          IconButton(
                                            icon: const Icon(Icons.edit, color: Colors.white),
                                            onPressed: () => _editRoute(route),
                                            tooltip: '編集',
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete, color: Colors.red),
                                            onPressed: () => _deleteRoute(route),
                                            tooltip: '削除',
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        Icon(
                                          Icons.arrow_forward,
                                          color: Colors.blue[300],
                                          size: 32,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('新規ルート作成'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _createNewRoute,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

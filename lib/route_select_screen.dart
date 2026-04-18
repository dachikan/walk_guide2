import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'route_service.dart';
import 'walk_navi_screen.dart';

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
      final route = await RouteService.loadRoute(routeInfo.fileName);
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
    } catch (e) {
      _showError('ルートの読み込みに失敗しました: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'ルート選択',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          : _routes.isEmpty
              ? const Center(
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
                              Text(
                                route.displayName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
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
    );
  }
}

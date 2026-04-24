import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

/// 全ページ共通のヘッダーウィジェット
/// タイトル、バージョン、AI切り替え歯車アイコンを表示
class CommonAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? pageTitle; // ページ固有のタイトル（オプション）
  final VoidCallback? onAIChanged; // AI変更時のコールバック

  const CommonAppBar({
    super.key,
    this.pageTitle,
    this.onAIChanged,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  Future<void> _showAISelectionDialog(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final currentAIKey = prefs.getString('selected_ai') ?? 'chatgpt';
    AIService currentAI = AIServiceHelper.fromKey(currentAIKey);

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        AIService selectedAI = currentAI;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Colors.grey[900],
              title: const Row(
                children: [
                  Icon(Icons.smart_toy, color: Colors.blue),
                  SizedBox(width: 8),
                  Text(
                    'AIサービス選択',
                    style: TextStyle(color: Colors.white, fontSize: 20),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: AIService.values.map((service) {
                  return RadioListTile<AIService>(
                    title: Text(
                      AIServiceHelper.getDisplayName(service),
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    subtitle: Text(
                      AIServiceHelper.getDescription(service),
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    value: service,
                    groupValue: selectedAI,
                    activeColor: Colors.blue,
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          selectedAI = value;
                        });
                      }
                    },
                  );
                }).toList(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text(
                    'キャンセル',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    // 選択を保存
                    await prefs.setString(
                      'selected_ai',
                      AIServiceHelper.toKey(selectedAI),
                    );
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    // コールバックを呼び出す
                    onAIChanged?.call();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                  ),
                  child: const Text(
                    '決定',
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: kToolbarHeight,
      backgroundColor: Colors.blue[800],
      foregroundColor: Colors.white,
      title: Row(
        children: [
          // タイトルとバージョン
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  pageTitle ?? '歩行ガイドWalk_Guide',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  'V0.0.20+1',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          // 歯車アイコン（AI切り替え）
          IconButton(
            icon: const Icon(Icons.settings, size: 28),
            tooltip: 'AI切り替え',
            onPressed: () => _showAISelectionDialog(context),
          ),
        ],
      ),
    );
  }
}

/// 現在選択中のAIを取得するヘルパー関数
Future<AIService> getCurrentAI() async {
  final prefs = await SharedPreferences.getInstance();
  final aiKey = prefs.getString('selected_ai') ?? 'chatgpt';
  return AIServiceHelper.fromKey(aiKey);
}

/// 現在選択中のAIの表示名を取得するヘルパー関数
Future<String> getCurrentAIDisplayName() async {
  final ai = await getCurrentAI();
  return AIServiceHelper.getDisplayName(ai);
}

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'route_select_screen.dart';
import 'ai_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 環境変数を読み込み
  try {
    await dotenv.load(fileName: ".walking_guide.env");
  } catch (e) {
    print('警告: .walking_guide.envファイルが見つかりません。AIService機能は利用できません。');
  }
  
  // AIサービスを初期化
  AIService.initialize();
  
  final tts = FlutterTts();
  await tts.setLanguage('ja-JP');
  await tts.setSpeechRate(0.5);
  await tts.setVolume(1.0);
  await tts.setPitch(1.0);
  
  runApp(WalkGuide2App(tts: tts));
}

class WalkGuide2App extends StatelessWidget {
  final FlutterTts tts;

  const WalkGuide2App({super.key, required this.tts});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Walk Guide - ルートナビ',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: HomeScreen(tts: tts),
    );
  }
}

class HomeScreen extends StatelessWidget {
  final FlutterTts tts;

  const HomeScreen({super.key, required this.tts});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // アプリタイトル
              const Icon(
                Icons.navigation,
                size: 120,
                color: Colors.blue,
              ),
              const SizedBox(height: 32),
              const Text(
                'Walk Guide',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'ルートナビゲーション',
                style: TextStyle(
                  fontSize: 24,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 64),

              // ルート選択ボタン
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => RouteSelectScreen(tts: tts),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48,
                    vertical: 24,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'ルートを選択',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // 説明文
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'GPS追跡により、登録されたルートに沿って\n音声で案内します',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey,
                  ),
                ),
              ),

              const SizedBox(height: 64),

              // バージョン情報
              const Text(
                'v1.0.0',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

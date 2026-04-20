import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// OpenAI API サービス
class AIService {
  static String? _apiKey;

  /// APIキーを初期化
  static void initialize() {
    _apiKey = dotenv.env['OPENAI_API_KEY'];
    if (_apiKey == null || _apiKey!.isEmpty || _apiKey == 'your_openai_api_key_here') {
      print('警告: OpenAI APIキーが設定されていません。.envファイルを確認してください。');
    }
  }

  /// Markdown記号を除去して音声読み上げに適したテキストに変換
  static String _cleanTextForSpeech(String text) {
    // アスタリスク（太字・強調）を除去
    text = text.replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'\1'); // **text** -> text
    text = text.replaceAll(RegExp(r'\*([^*]+)\*'), r'\1'); // *text* -> text
    
    // その他のMarkdown記号を除去
    text = text.replaceAll(RegExp(r'#+\s'), ''); // # 見出し
    text = text.replaceAll(RegExp(r'`([^`]+)`'), r'\1'); // `code`
    text = text.replaceAll(RegExp(r'\[([^\]]+)\]\([^\)]+\)'), r'\1'); // [text](url)
    
    return text.trim();
  }

  /// 画像を分析して説明を取得（GPT-4 Vision API）
  static Future<String> describeImage(File imageFile) async {
    if (_apiKey == null || _apiKey!.isEmpty || _apiKey == 'your_openai_api_key_here') {
      return 'APIキーが設定されていません。.envファイルにOPENAI_API_KEYを設定してください。';
    }

    try {
      // 画像をBase64エンコード
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-4o',
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'text',
                  'text': '視覚障害者のために、この画像に写っている景色を説明してください。安全かどうかを最初に一言で答えてから、道路の状態、障害物、目印となる建物や看板などを説明してください。音声で読み上げるので、箇条書きや記号を使わず、自然な日本語で答えてください。',
                },
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:image/jpeg;base64,$base64Image',
                  },
                },
              ],
            },
          ],
          'max_tokens': 500,
        }),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('接続タイムアウト: APIサーバーからの応答がありません');
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final rawContent = data['choices'][0]['message']['content'];
        return _cleanTextForSpeech(rawContent);
      } else {
        return 'エラー: API呼び出しに失敗しました (${response.statusCode})';
      }
    } on SocketException {
      return 'ネットワークエラー: インターネット接続を確認してください。Wi-Fiまたはモバイルデータがオンになっているか確認してください。';
    } on TimeoutException {
      return '接続タイムアウト: ネットワークが遅いか、APIサーバーが応答していません。';
    } catch (e) {
      return 'エラー: $e';
    }
  }

  /// 音声命令をAIに送信して返答を取得
  static Future<String> processVoiceCommand(String command) async {
    if (_apiKey == null || _apiKey!.isEmpty || _apiKey == 'your_openai_api_key_here') {
      return 'APIキーが設定されていません。.envファイルにOPENAI_API_KEYを設定してください。';
    }

    try {
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-4o',
          'messages': [
            {
              'role': 'system',
              'content': 'あなたは視覚障害者をサポートするアシスタントです。質問に対して、まず結論を一言で答えてから、詳しい説明を続けてください。音声で読み上げるので、箇条書きや記号を使わず、自然な日本語で答えてください。危険に関する質問の場合は「○○に注意」のように端的に答えてから解説してください。',
            },
            {
              'role': 'user',
              'content': command,
            },
          ],
          'max_tokens': 300,
        }),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('接続タイムアウト: APIサーバーからの応答がありません');
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final rawContent = data['choices'][0]['message']['content'];
        return _cleanTextForSpeech(rawContent);
      } else {
        return 'エラー: API呼び出しに失敗しました (${response.statusCode})';
      }
    } on SocketException {
      return 'ネットワークエラー: インターネット接続を確認してください。Wi-Fiまたはモバイルデータがオンになっているか確認してください。';
    } on TimeoutException {
      return '接続タイムアウト: ネットワークが遅いか、APIサーバーが応答していません。';
    } catch (e) {
      return 'エラー: $e';
    }
  }
}

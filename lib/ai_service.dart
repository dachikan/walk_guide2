import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart' as app_models;

/// AI API サービス（OpenAI / Gemini）
class AIService {
  static String? _openAiApiKey;
  static String? _geminiApiKey;
  static String? _claudeApiKey;
  static String? _deepSeekApiKey;
  static const String _openAiChatCompletionsUrl = 'https://api.openai.com/v1/chat/completions';
  static const String _geminiBaseUrl = 'https://generativelanguage.googleapis.com/v1beta/models';
  static const String _claudeMessagesUrl = 'https://api.anthropic.com/v1/messages';
  static const String _deepSeekChatCompletionsUrl = 'https://api.deepseek.com/chat/completions';

  /// APIキーを初期化
  static void initialize() {
    _openAiApiKey = dotenv.env['OPENAI_API_KEY'];
    _geminiApiKey = dotenv.env['GEMINI_API_KEY'];
    _claudeApiKey = dotenv.env['CLAUDE_API_KEY'] ?? dotenv.env['SONNET_API_KEY'];
    _deepSeekApiKey = dotenv.env['DEEPSEEK_API_KEY'];

    if (_openAiApiKey == null ||
        _openAiApiKey!.isEmpty ||
        _openAiApiKey == 'your_openai_api_key_here') {
      print('警告: OpenAI APIキーが設定されていません。.envファイルを確認してください。');
    }

    if (_geminiApiKey == null ||
        _geminiApiKey!.isEmpty ||
        _geminiApiKey == 'your_gemini_api_key_here') {
      print('警告: Gemini APIキーが設定されていません。.envファイルを確認してください。');
    }

    if (_claudeApiKey == null || _claudeApiKey!.isEmpty) {
      print('警告: Claude APIキーが設定されていません。.envファイルのCLAUDE_API_KEYまたはSONNET_API_KEYを確認してください。');
    }

    if (_deepSeekApiKey == null || _deepSeekApiKey!.isEmpty) {
      print('警告: DeepSeek APIキーが設定されていません。.envファイルのDEEPSEEK_API_KEYを確認してください。');
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

  static Future<app_models.AIService> _getSelectedAI() async {
    final prefs = await SharedPreferences.getInstance();
    final selected = prefs.getString('selected_ai') ?? 'chatgpt';
    return app_models.AIServiceHelper.fromKey(selected);
  }

  /// 画像を分析して説明を取得
  static Future<String> describeImage(File imageFile) async {
    final selectedAI = await _getSelectedAI();

    switch (selectedAI) {
      case app_models.AIService.chatgpt:
        return _describeImageWithOpenAI(imageFile);
      case app_models.AIService.gemini:
        return _describeImageWithGemini(imageFile);
      case app_models.AIService.claude:
        return _describeImageWithClaude(imageFile);
      case app_models.AIService.deepseek:
        return _describeImageWithDeepSeek(imageFile);
    }
  }

  static Future<String> _describeImageWithOpenAI(File imageFile) async {
    if (_openAiApiKey == null || _openAiApiKey!.isEmpty || _openAiApiKey == 'your_openai_api_key_here') {
      return 'APIキーが設定されていません。.envファイルにOPENAI_API_KEYを設定してください。';
    }

    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      final response = await _postWithRetryOpenAI(
        body: {
          'model': dotenv.env['OPENAI_MODEL_VISION'] ?? 'gpt-4o-mini',
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
                    'detail': 'low',
                  },
                },
              ],
            },
          ],
          'max_tokens': 300,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final rawContent = data['choices'][0]['message']['content'];
        return _cleanTextForSpeech(rawContent);
      }
      return _buildOpenAiErrorMessage(response);
    } on SocketException {
      return 'ネットワークエラー: インターネット接続を確認してください。Wi-Fiまたはモバイルデータがオンになっているか確認してください。';
    } on TimeoutException {
      return '接続タイムアウト: ネットワークが遅いか、APIサーバーが応答していません。';
    } catch (e) {
      return 'エラー: $e';
    }
  }

  static Future<String> _describeImageWithGemini(File imageFile) async {
    if (_geminiApiKey == null || _geminiApiKey!.isEmpty || _geminiApiKey == 'your_gemini_api_key_here') {
      return 'APIキーが設定されていません。.envファイルにGEMINI_API_KEYを設定してください。';
    }

    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);
      final model = dotenv.env['GEMINI_MODEL_VISION'] ?? 'gemini-2.5-flash';

      final response = await _postWithRetryGemini(
        model: model,
        body: {
          'contents': [
            {
              'parts': [
                {
                  'text': '視覚障害者のために、この画像に写っている景色を説明してください。安全かどうかを最初に一言で答えてから、道路の状態、障害物、目印となる建物や看板などを説明してください。音声で読み上げるので、箇条書きや記号を使わず、自然な日本語で答えてください。',
                },
                {
                  'inline_data': {
                    'mime_type': 'image/jpeg',
                    'data': base64Image,
                  },
                },
              ],
            },
          ],
          'generationConfig': {
            'maxOutputTokens': 300,
          },
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final candidates = data['candidates'] as List<dynamic>?;
        if (candidates == null || candidates.isEmpty) {
          return 'エラー: Geminiの応答が空でした。';
        }
        final parts = candidates.first['content']?['parts'] as List<dynamic>?;
        final text = parts != null && parts.isNotEmpty ? (parts.first['text']?.toString() ?? '') : '';
        if (text.isEmpty) {
          return 'エラー: Geminiの応答テキストを取得できませんでした。';
        }
        return _cleanTextForSpeech(text);
      }
      return _buildGeminiErrorMessage(response);
    } on SocketException {
      return 'ネットワークエラー: インターネット接続を確認してください。Wi-Fiまたはモバイルデータがオンになっているか確認してください。';
    } on TimeoutException {
      return '接続タイムアウト: ネットワークが遅いか、APIサーバーが応答していません。';
    } catch (e) {
      return 'エラー: $e';
    }
  }

  static Future<String> _describeImageWithClaude(File imageFile) async {
    if (_claudeApiKey == null || _claudeApiKey!.isEmpty) {
      return 'APIキーが設定されていません。.envファイルにCLAUDE_API_KEYを設定してください。';
    }

    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);
      final model = dotenv.env['CLAUDE_MODEL_VISION'] ?? 'claude-3-5-sonnet-latest';

      final response = await _postWithRetryClaude(
        body: {
          'model': model,
          'max_tokens': 500,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'text',
                  'text': '視覚障害者のために、この画像に写っている景色を説明してください。安全かどうかを最初に一言で答えてから、道路の状態、障害物、目印となる建物や看板などを説明してください。音声で読み上げるので、箇条書きや記号を使わず、自然な日本語で答えてください。',
                },
                {
                  'type': 'image',
                  'source': {
                    'type': 'base64',
                    'media_type': 'image/jpeg',
                    'data': base64Image,
                  },
                },
              ],
            },
          ],
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final content = data['content'] as List<dynamic>?;
        if (content == null || content.isEmpty) {
          return 'エラー: Claudeの応答が空でした。';
        }
        final text = content.first['text']?.toString() ?? '';
        if (text.isEmpty) {
          return 'エラー: Claudeの応答テキストを取得できませんでした。';
        }
        return _cleanTextForSpeech(text);
      }
      return _buildClaudeErrorMessage(response);
    } on SocketException {
      return 'ネットワークエラー: インターネット接続を確認してください。Wi-Fiまたはモバイルデータがオンになっているか確認してください。';
    } on TimeoutException {
      return '接続タイムアウト: ネットワークが遅いか、APIサーバーが応答していません。';
    } catch (e) {
      return 'エラー: $e';
    }
  }

  static Future<String> _describeImageWithDeepSeek(File imageFile) async {
    if (_deepSeekApiKey == null || _deepSeekApiKey!.isEmpty) {
      return 'APIキーが設定されていません。.envファイルにDEEPSEEK_API_KEYを設定してください。';
    }

    final model = dotenv.env['DEEPSEEK_MODEL_VISION'];
    if (model == null || model.trim().isEmpty) {
      return 'エラー: DeepSeekの画像解析モデルが未設定です。.envにDEEPSEEK_MODEL_VISIONを設定してください。';
    }

    // DeepSeek Chat APIは画像入力に非対応のため、前方確認は他のAIを案内
    return 'DeepSeekは前方確認（画像解析）に対応していません。前方確認はClaude、Gemini、またはChatGPTを選択してください。';

    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      final response = await _postWithRetryDeepSeek(
        body: {
          'model': model,
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
          'max_tokens': 300,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final rawContent = data['choices'][0]['message']['content'];
        return _cleanTextForSpeech(rawContent);
      }
      return _buildDeepSeekErrorMessage(response);
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
    final selectedAI = await _getSelectedAI();

    switch (selectedAI) {
      case app_models.AIService.chatgpt:
        return _processVoiceCommandWithOpenAI(command);
      case app_models.AIService.gemini:
        return _processVoiceCommandWithGemini(command);
      case app_models.AIService.claude:
        return _processVoiceCommandWithClaude(command);
      case app_models.AIService.deepseek:
        return _processVoiceCommandWithDeepSeek(command);
    }
  }

  static Future<String> _processVoiceCommandWithOpenAI(String command) async {
    if (_openAiApiKey == null || _openAiApiKey!.isEmpty || _openAiApiKey == 'your_openai_api_key_here') {
      return 'APIキーが設定されていません。.envファイルにOPENAI_API_KEYを設定してください。';
    }

    try {
      final response = await _postWithRetryOpenAI(
        body: {
          'model': dotenv.env['OPENAI_MODEL_TEXT'] ?? 'gpt-4o-mini',
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
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final rawContent = data['choices'][0]['message']['content'];
        return _cleanTextForSpeech(rawContent);
      }
      return _buildOpenAiErrorMessage(response);
    } on SocketException {
      return 'ネットワークエラー: インターネット接続を確認してください。Wi-Fiまたはモバイルデータがオンになっているか確認してください。';
    } on TimeoutException {
      return '接続タイムアウト: ネットワークが遅いか、APIサーバーが応答していません。';
    } catch (e) {
      return 'エラー: $e';
    }
  }

  static Future<String> _processVoiceCommandWithGemini(String command) async {
    if (_geminiApiKey == null || _geminiApiKey!.isEmpty || _geminiApiKey == 'your_gemini_api_key_here') {
      return 'APIキーが設定されていません。.envファイルにGEMINI_API_KEYを設定してください。';
    }

    try {
      final model = dotenv.env['GEMINI_MODEL_TEXT'] ?? 'gemini-2.5-flash';
      final response = await _postWithRetryGemini(
        model: model,
        body: {
          'contents': [
            {
              'parts': [
                {
                  'text': 'あなたは視覚障害者をサポートするアシスタントです。質問に対して、まず結論を一言で答えてから、詳しい説明を続けてください。音声で読み上げるので、箇条書きや記号を使わず、自然な日本語で答えてください。危険に関する質問の場合は「○○に注意」のように端的に答えてから解説してください。',
                },
                {'text': command},
              ],
            },
          ],
          'generationConfig': {
            'maxOutputTokens': 300,
          },
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final candidates = data['candidates'] as List<dynamic>?;
        if (candidates == null || candidates.isEmpty) {
          return 'エラー: Geminiの応答が空でした。';
        }
        final parts = candidates.first['content']?['parts'] as List<dynamic>?;
        final text = parts != null && parts.isNotEmpty ? (parts.first['text']?.toString() ?? '') : '';
        if (text.isEmpty) {
          return 'エラー: Geminiの応答テキストを取得できませんでした。';
        }
        return _cleanTextForSpeech(text);
      }
      return _buildGeminiErrorMessage(response);
    } on SocketException {
      return 'ネットワークエラー: インターネット接続を確認してください。Wi-Fiまたはモバイルデータがオンになっているか確認してください。';
    } on TimeoutException {
      return '接続タイムアウト: ネットワークが遅いか、APIサーバーが応答していません。';
    } catch (e) {
      return 'エラー: $e';
    }
  }

  static Future<String> _processVoiceCommandWithClaude(String command) async {
    if (_claudeApiKey == null || _claudeApiKey!.isEmpty) {
      return 'APIキーが設定されていません。.envファイルにCLAUDE_API_KEYを設定してください。';
    }

    try {
      final model = dotenv.env['CLAUDE_MODEL_TEXT'] ?? 'claude-3-5-sonnet-latest';
      final response = await _postWithRetryClaude(
        body: {
          'model': model,
          'max_tokens': 500,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'text',
                  'text': 'あなたは視覚障害者をサポートするアシスタントです。質問に対して、まず結論を一言で答えてから、詳しい説明を続けてください。音声で読み上げるので、箇条書きや記号を使わず、自然な日本語で答えてください。危険に関する質問の場合は「○○に注意」のように端的に答えてから解説してください。\n\nユーザーの質問: $command',
                },
              ],
            },
          ],
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final content = data['content'] as List<dynamic>?;
        if (content == null || content.isEmpty) {
          return 'エラー: Claudeの応答が空でした。';
        }
        final text = content.first['text']?.toString() ?? '';
        if (text.isEmpty) {
          return 'エラー: Claudeの応答テキストを取得できませんでした。';
        }
        return _cleanTextForSpeech(text);
      }
      return _buildClaudeErrorMessage(response);
    } on SocketException {
      return 'ネットワークエラー: インターネット接続を確認してください。Wi-Fiまたはモバイルデータがオンになっているか確認してください。';
    } on TimeoutException {
      return '接続タイムアウト: ネットワークが遅いか、APIサーバーが応答していません。';
    } catch (e) {
      return 'エラー: $e';
    }
  }

  static Future<String> _processVoiceCommandWithDeepSeek(String command) async {
    if (_deepSeekApiKey == null || _deepSeekApiKey!.isEmpty) {
      return 'APIキーが設定されていません。.envファイルにDEEPSEEK_API_KEYを設定してください。';
    }

    try {
      final model = dotenv.env['DEEPSEEK_MODEL_TEXT'] ?? 'deepseek-v4-flash';
      final response = await _postWithRetryDeepSeek(
        body: {
          'model': model,
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
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final rawContent = data['choices'][0]['message']['content'];
        return _cleanTextForSpeech(rawContent);
      }
      return _buildDeepSeekErrorMessage(response);
    } on SocketException {
      return 'ネットワークエラー: インターネット接続を確認してください。Wi-Fiまたはモバイルデータがオンになっているか確認してください。';
    } on TimeoutException {
      return '接続タイムアウト: ネットワークが遅いか、APIサーバーが応答していません。';
    } catch (e) {
      return 'エラー: $e';
    }
  }

  static Future<http.Response> _postWithRetryOpenAI({
    required Map<String, dynamic> body,
  }) async {
    const int maxAttempts = 3;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      final response = await http
          .post(
            Uri.parse(_openAiChatCompletionsUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_openAiApiKey',
            },
            body: jsonEncode(body),
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception('接続タイムアウト: APIサーバーからの応答がありません');
            },
          );

      final canRetry = (response.statusCode == 429 || response.statusCode >= 500) && attempt < maxAttempts;
      if (!canRetry) {
        return response;
      }

      final retryAfterHeader = response.headers['retry-after'];
      final retrySeconds = int.tryParse(retryAfterHeader ?? '') ?? attempt * 2;
      await Future.delayed(Duration(seconds: retrySeconds.clamp(1, 10)));
    }

    throw Exception('API呼び出しに失敗しました');
  }

  static Future<http.Response> _postWithRetryGemini({
    required String model,
    required Map<String, dynamic> body,
  }) async {
    const int maxAttempts = 3;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      final url = '$_geminiBaseUrl/$model:generateContent?key=$_geminiApiKey';
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception('接続タイムアウト: APIサーバーからの応答がありません');
            },
          );

      final canRetry = (response.statusCode == 429 || response.statusCode >= 500) && attempt < maxAttempts;
      if (!canRetry) {
        return response;
      }

      final retryAfterHeader = response.headers['retry-after'];
      final retrySeconds = int.tryParse(retryAfterHeader ?? '') ?? attempt * 2;
      await Future.delayed(Duration(seconds: retrySeconds.clamp(1, 10)));
    }

    throw Exception('API呼び出しに失敗しました');
  }

  static Future<http.Response> _postWithRetryClaude({
    required Map<String, dynamic> body,
  }) async {
    const int maxAttempts = 3;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      final response = await http
          .post(
            Uri.parse(_claudeMessagesUrl),
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': _claudeApiKey ?? '',
              'anthropic-version': '2023-06-01',
            },
            body: jsonEncode(body),
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception('接続タイムアウト: APIサーバーからの応答がありません');
            },
          );

      final canRetry = (response.statusCode == 429 || response.statusCode >= 500) && attempt < maxAttempts;
      if (!canRetry) {
        return response;
      }

      final retryAfterHeader = response.headers['retry-after'];
      final retrySeconds = int.tryParse(retryAfterHeader ?? '') ?? attempt * 2;
      await Future.delayed(Duration(seconds: retrySeconds.clamp(1, 10)));
    }

    throw Exception('API呼び出しに失敗しました');
  }

  static Future<http.Response> _postWithRetryDeepSeek({
    required Map<String, dynamic> body,
  }) async {
    const int maxAttempts = 3;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      final response = await http
          .post(
            Uri.parse(_deepSeekChatCompletionsUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_deepSeekApiKey',
            },
            body: jsonEncode(body),
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception('接続タイムアウト: APIサーバーからの応答がありません');
            },
          );

      final canRetry = (response.statusCode == 429 || response.statusCode >= 500) && attempt < maxAttempts;
      if (!canRetry) {
        return response;
      }

      final retryAfterHeader = response.headers['retry-after'];
      final retrySeconds = int.tryParse(retryAfterHeader ?? '') ?? attempt * 2;
      await Future.delayed(Duration(seconds: retrySeconds.clamp(1, 10)));
    }

    throw Exception('API呼び出しに失敗しました');
  }

  static String _buildOpenAiErrorMessage(http.Response response) {
    final status = response.statusCode;

    try {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final error = data['error'];
      final type = error?['type']?.toString() ?? '';
      final code = error?['code']?.toString() ?? '';
      final message = error?['message']?.toString() ?? '';

      if (status == 429) {
        if (code == 'insufficient_quota') {
          return 'エラー: API利用上限に達しました。OpenAIの請求設定または残高をご確認ください。';
        }
        return 'エラー: OpenAI APIが混み合っています。少し待ってから再度お試しください。';
      }

      if (status == 401) {
        return 'エラー: APIキーが無効です。OPENAI_API_KEYを確認してください。';
      }

      if (message.isNotEmpty) {
        return 'エラー: API呼び出しに失敗しました ($status) $message';
      }

      if (type.isNotEmpty || code.isNotEmpty) {
        return 'エラー: API呼び出しに失敗しました ($status) type=$type code=$code';
      }
    } catch (_) {
      // レスポンスがJSONでない場合は汎用メッセージを返す
    }

    return 'エラー: OpenAI API呼び出しに失敗しました ($status)';
  }

  static String _buildGeminiErrorMessage(http.Response response) {
    final status = response.statusCode;

    try {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final error = data['error'];
      final message = error?['message']?.toString() ?? '';
      final apiStatus = error?['status']?.toString() ?? '';

      if (status == 429) {
        return 'エラー: Gemini API利用制限に達しました。時間をおいて再試行するか、Google AI Studioの利用状況をご確認ください。';
      }

      if (status == 400) {
        final lowerMessage = message.toLowerCase();
        if (lowerMessage.contains('api key not valid') || lowerMessage.contains('invalid api key')) {
          return 'エラー: Gemini APIキーが無効です。GEMINI_API_KEYを確認してください。';
        }
        if (lowerMessage.contains('model') && lowerMessage.contains('not found')) {
          return 'エラー: Geminiモデル名が無効です。GEMINI_MODEL_VISION / GEMINI_MODEL_TEXTを確認してください。';
        }
        if (message.isNotEmpty) {
          return 'エラー: Gemini APIリクエストが不正です。$message';
        }
        return 'エラー: Gemini APIリクエストが不正です。モデル名またはキー設定を確認してください。';
      }

      if (status == 401 || status == 403) {
        return 'エラー: Gemini APIキーが無効、または権限がありません。GEMINI_API_KEYを確認してください。';
      }

      if (message.isNotEmpty) {
        return 'エラー: Gemini API呼び出しに失敗しました ($status) $message';
      }

      if (apiStatus.isNotEmpty) {
        return 'エラー: Gemini API呼び出しに失敗しました ($status) status=$apiStatus';
      }
    } catch (_) {
      // レスポンスがJSONでない場合は汎用メッセージを返す
    }

    return 'エラー: Gemini API呼び出しに失敗しました ($status)';
  }

  static String _buildClaudeErrorMessage(http.Response response) {
    final status = response.statusCode;

    try {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final error = data['error'];
      final type = error?['type']?.toString() ?? '';
      final message = error?['message']?.toString() ?? '';

      if (status == 429) {
        return 'エラー: Claude API利用制限に達しました。時間をおいて再試行してください。';
      }
      if (status == 401 || status == 403) {
        return 'エラー: Claude APIキーが無効、または権限がありません。CLAUDE_API_KEYを確認してください。';
      }
      if (message.isNotEmpty) {
        return 'エラー: Claude API呼び出しに失敗しました ($status) $message';
      }
      if (type.isNotEmpty) {
        return 'エラー: Claude API呼び出しに失敗しました ($status) type=$type';
      }
    } catch (_) {
      // レスポンスがJSONでない場合は汎用メッセージを返す
    }

    return 'エラー: Claude API呼び出しに失敗しました ($status)';
  }

  static String _buildDeepSeekErrorMessage(http.Response response) {
    final status = response.statusCode;

    try {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final error = data['error'];
      final type = error?['type']?.toString() ?? '';
      final code = error?['code']?.toString() ?? '';
      final message = error?['message']?.toString() ?? '';

      if (status == 429) {
        return 'エラー: DeepSeek API利用制限に達しました。時間をおいて再試行してください。';
      }
      if (status == 401 || status == 403) {
        return 'エラー: DeepSeek APIキーが無効、または権限がありません。DEEPSEEK_API_KEYを確認してください。';
      }
      if (status == 400) {
        final lowerMessage = message.toLowerCase();
        if (lowerMessage.contains('failed to deserialize') ||
            lowerMessage.contains('deserialize the json body')) {
          return 'エラー: DeepSeek APIリクエスト形式が仕様と一致していません。前方確認(画像解析)は現在DeepSeekでは利用しづらいため、Claude/Gemini/ChatGPTを使用してください。';
        }
      }
      if (message.isNotEmpty) {
        return 'エラー: DeepSeek API呼び出しに失敗しました ($status) $message';
      }
      if (type.isNotEmpty || code.isNotEmpty) {
        return 'エラー: DeepSeek API呼び出しに失敗しました ($status) type=$type code=$code';
      }
    } catch (_) {
      // レスポンスがJSONでない場合は汎用メッセージを返す
    }

    return 'エラー: DeepSeek API呼び出しに失敗しました ($status)';
  }
}

// 共通データモデル・列挙型

/// AIサービスの種類
enum AIService { 
  chatgpt,  // デフォルト
  gemini,
  claude,
}

/// AIサービスのヘルパークラス
class AIServiceHelper {
  static String getDisplayName(AIService service) {
    switch (service) {
      case AIService.chatgpt:
        return 'ChatGPT (OpenAI)';
      case AIService.gemini:
        return 'Google Gemini';
      case AIService.claude:
        return 'Claude (Anthropic)';
    }
  }

  static String getDescription(AIService service) {
    switch (service) {
      case AIService.chatgpt:
        return '安定性高・実績豊富【デフォルト】';
      case AIService.gemini:
        return '高速・無料枠が多い';
      case AIService.claude:
        return '高品質・日本語が得意';
    }
  }

  /// AIServiceをString（shared_preferences用）に変換
  static String toKey(AIService service) {
    return service.toString().split('.').last;
  }

  /// StringからAIServiceに変換
  static AIService fromKey(String key) {
    switch (key) {
      case 'chatgpt':
        return AIService.chatgpt;
      case 'gemini':
        return AIService.gemini;
      case 'claude':
        return AIService.claude;
      default:
        return AIService.chatgpt; // デフォルト
    }
  }
}

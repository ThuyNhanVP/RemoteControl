import 'package:flutter_test/flutter_test.dart';
import 'package:test2/ai_assistant.dart' show openRouterFreeModels;
import 'package:test2/secrets.dart';
import 'package:test2/settings.dart';

void main() {
  test('AiConfig dùng key đã lưu, rỗng thì dùng key mặc định', () {
    final c = AiConfig.from(provider: 'gemini', gemini: 'abc', openRouter: '');
    expect(c.geminiKey, 'abc');
    expect(c.openRouterKey, defaultOpenRouterApiKey);
    expect(c.apiKey, 'abc');
  });

  test('AiConfig chọn key theo nhà cung cấp, giá trị lạ về gemini', () {
    final o = AiConfig.from(provider: 'openrouter', gemini: 'g', openRouter: 'o');
    expect(o.apiKey, 'o');
    expect(AiConfig.from(provider: 'xyz', gemini: 'g', openRouter: 'o').apiKey, 'g');
    expect(AiConfig.from().provider, 'gemini');
  });

  test('AiConfig mô hình ngoài danh sách về mô hình đầu tiên', () {
    expect(AiConfig.from(model: 'khong-co').model, openRouterFreeModels.first);
    final m = openRouterFreeModels.last;
    expect(AiConfig.from(model: m).model, m);
  });
}

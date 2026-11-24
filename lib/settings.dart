import 'package:flutter/material.dart';

import 'ai_assistant.dart';
import 'db.dart';
import 'firebase_sync.dart';
import 'secrets.dart';

/// Cấu hình trợ lý AI dùng chung cho hub, trang điều hòa và trang TV.
class AiConfig {
  const AiConfig({
    required this.provider,
    required this.geminiKey,
    required this.openRouterKey,
    required this.model,
  });

  final String provider; // 'gemini' | 'openrouter'
  final String geminiKey; // key đã lưu, rỗng thì dùng key mặc định
  final String openRouterKey;
  final String model;

  String get apiKey => provider == 'openrouter' ? openRouterKey : geminiKey;

  static String _pick(String? stored, String fallback) =>
      (stored != null && stored.isNotEmpty) ? stored : fallback;

  /// Dựng cấu hình từ giá trị đã lưu (null/rỗng thì dùng mặc định).
  factory AiConfig.from({String? provider, String? gemini, String? openRouter, String? model}) =>
      AiConfig(
        provider: provider == 'openrouter' ? 'openrouter' : 'gemini',
        geminiKey: _pick(gemini, defaultGeminiApiKey),
        openRouterKey: _pick(openRouter, defaultOpenRouterApiKey),
        model: openRouterFreeModels.contains(model) ? model! : openRouterFreeModels.first,
      );

  static Future<AiConfig> load() async => AiConfig.from(
        provider: await Db.getMeta('ai_provider'),
        gemini: await Db.getMeta('gemini_api_key'),
        openRouter: await Db.getMeta('openrouter_api_key'),
        model: await Db.getMeta('openrouter_model'),
      );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String provider = 'gemini';
  String model = openRouterFreeModels.first;
  final gemini = TextEditingController();
  final openRouter = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    gemini.dispose();
    openRouter.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final c = await AiConfig.load();
    // Ô nhập chỉ hiện key người dùng tự lưu, không lộ key mặc định trong APK.
    final g = await Db.getMeta('gemini_api_key') ?? '';
    final o = await Db.getMeta('openrouter_api_key') ?? '';
    if (!mounted) return;
    setState(() {
      provider = c.provider;
      model = c.model;
      gemini.text = g;
      openRouter.text = o;
    });
  }

  void _snack(String msg, bool ok) {
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: ok ? Colors.green.shade800 : Colors.red.shade800,
      duration: const Duration(seconds: 3),
    ));
  }

  Future<void> _test() async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Đang kiểm tra kết nối...'),
      duration: Duration(seconds: 2),
    ));
    final c = AiConfig.from(
      provider: provider,
      gemini: gemini.text.trim(),
      openRouter: openRouter.text.trim(),
      model: model,
    );
    final ok = provider == 'openrouter'
        ? await AiAssistantEngine.testOpenRouterApiKey(c.openRouterKey, model: c.model)
        : await AiAssistantEngine.testApiKey(c.geminiKey);
    if (!mounted) return;
    final name = provider == 'openrouter' ? 'OpenRouter' : 'Gemini';
    _snack(ok ? '🟢 $name API Key hợp lệ và hoạt động tốt!' : '🔴 $name API Key không hợp lệ hoặc lỗi kết nối mạng.', ok);
  }

  InputDecoration _dec(String label) => const InputDecoration(
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
      ).copyWith(labelText: label);

  @override
  Widget build(BuildContext context) {
    final isOr = provider == 'openrouter';
    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SyncCard(),
          const SizedBox(height: 24),
          const Text('Trợ lý AI (tùy chọn)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            'Chọn dịch vụ AI Cloud (Gemini hoặc OpenRouter với các mô hình miễn phí). Để trống key thì dùng key mặc định của ứng dụng (nếu có).',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'gemini', label: Text('Google Gemini')),
              ButtonSegment(value: 'openrouter', label: Text('OpenRouter (Free)')),
            ],
            selected: {provider},
            onSelectionChanged: (s) {
              setState(() => provider = s.first);
              Db.setMeta('ai_provider', s.first);
            },
          ),
          const SizedBox(height: 14),
          if (isOr) ...[
            const Text('Chọn mô hình OpenRouter miễn phí:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: model,
              decoration: _dec('Mô hình'),
              items: [
                for (final m in openRouterFreeModels)
                  DropdownMenuItem(
                    value: m,
                    child: Text(m.replaceAll(':free', ' (Miễn phí)'), style: const TextStyle(fontSize: 13)),
                  ),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => model = v);
                Db.setMeta('openrouter_model', v);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: openRouter,
              decoration: _dec('OpenRouter API Key'),
              onChanged: (v) => Db.setMeta('openrouter_api_key', v.trim()),
            ),
          ] else
            TextField(
              controller: gemini,
              decoration: _dec('Gemini API Key'),
              onChanged: (v) => Db.setMeta('gemini_api_key', v.trim()),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _test,
            icon: const Icon(Icons.verified_outlined),
            label: Text('Kiểm tra ${isOr ? "OpenRouter" : "Gemini"} API Key'),
          ),
        ],
      ),
    );
  }
}

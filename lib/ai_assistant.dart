import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'protocols.dart';
import 'secrets.dart';

/// Kết quả xử lý câu lệnh tự nhiên của AI.
class AiResult {
  final String query;
  final String response;
  final bool? power;
  final int? temp;
  final AcMode? mode;
  final AcFan? fan;
  final Map<Feat, bool> featChanges;
  final String? targetDeviceName;
  final bool isWeatherQuery;
  final bool actionTaken;

  AiResult({
    required this.query,
    required this.response,
    this.power,
    this.temp,
    this.mode,
    this.fan,
    this.featChanges = const {},
    this.targetDeviceName,
    this.isWeatherQuery = false,
    this.actionTaken = false,
  });
}


const openRouterFreeModels = [
  'openrouter/auto',
  'google/gemini-2.0-flash-lite-001',
  'meta-llama/llama-3.1-8b-instruct',
  'mistralai/mistral-7b-instruct',
  'deepseek/deepseek-chat',
];

/// Động cơ xử lý ngôn ngữ tự nhiên (Local Smart Engine & Cloud Gemini / OpenRouter AI).
class AiAssistantEngine {
  /// Xử lý câu lệnh ngôn ngữ tự nhiên tiếng Việt.
  static Future<AiResult> processQuery(
    String query, {
    required bool currentPower,
    required int currentTemp,
    required AcMode currentMode,
    required AcFan currentFan,
    required Map<Feat, bool> currentFeat,
    required List<String> availableDevices,
    String? currentDeviceName,
    int minTemp = 16,
    String aiProvider = 'gemini',
    String? apiKey,
    String? openRouterModel,
    String? weatherSummary,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      return AiResult(
        query: query,
        response: 'Vui lòng nói hoặc nhập câu lệnh.',
      );
    }

    if (aiProvider == 'openrouter') {
      final effectiveKey = (apiKey != null && apiKey.trim().isNotEmpty)
          ? apiKey.trim()
          : defaultOpenRouterApiKey;
      if (effectiveKey.isNotEmpty) {
        try {
          final cloudResult = await _processWithOpenRouter(
            cleanQuery,
            currentPower: currentPower,
            currentTemp: currentTemp,
            currentMode: currentMode,
            currentFan: currentFan,
            currentFeat: currentFeat,
            availableDevices: availableDevices,
            currentDeviceName: currentDeviceName,
            minTemp: minTemp,
            apiKey: effectiveKey,
            openRouterModel: openRouterModel,
            weatherSummary: weatherSummary,
          );
          if (cloudResult != null) return cloudResult;
        } catch (_) {}
      }
    } else {
      // Mặc định gọi Gemini API
      final effectiveKey = (apiKey != null && apiKey.trim().isNotEmpty)
          ? apiKey.trim()
          : defaultGeminiApiKey;

      if (effectiveKey.isNotEmpty) {
        try {
          final cloudResult = await _processWithGemini(
            cleanQuery,
            currentPower: currentPower,
            currentTemp: currentTemp,
            currentMode: currentMode,
            currentFan: currentFan,
            currentFeat: currentFeat,
            availableDevices: availableDevices,
            currentDeviceName: currentDeviceName,
            minTemp: minTemp,
            apiKey: effectiveKey,
            weatherSummary: weatherSummary,
          );
          if (cloudResult != null) return cloudResult;
        } catch (_) {}
      }
    }

    // Bộ xử lý ngôn ngữ tự nhiên cục bộ (chạy offline 100%, cực nhanh)
    return _processLocally(
      cleanQuery,
      currentPower: currentPower,
      currentTemp: currentTemp,
      currentMode: currentMode,
      currentFan: currentFan,
      currentFeat: currentFeat,
      availableDevices: availableDevices,
      currentDeviceName: currentDeviceName,
      minTemp: minTemp,
      weatherSummary: weatherSummary,
    );
  }

  /// Kiểm tra API Key xem có kết nối tốt với Gemini hay không.
  static Future<bool> testApiKey(String apiKey) async {
    final key = apiKey.trim().isEmpty ? defaultGeminiApiKey : apiKey.trim();
    try {
      final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$key');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': 'Hello'}
              ]
            }
          ]
        }),
      ).timeout(const Duration(seconds: 6));

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Bộ xử lý ngôn ngữ tự nhiên Local (Vietnamese Smart Parser).
  static AiResult _processLocally(
    String query, {
    required bool currentPower,
    required int currentTemp,
    required AcMode currentMode,
    required AcFan currentFan,
    required Map<Feat, bool> currentFeat,
    required List<String> availableDevices,
    String? currentDeviceName,
    int minTemp = 16,
    String? weatherSummary,
  }) {
    final q = query.toLowerCase();
    final changes = <String>[];

    bool? newPower;
    int? newTemp;
    AcMode? newMode;
    AcFan? newFan;
    final featChanges = <Feat, bool>{};
    String? targetDevice;
    bool isWeather = false;

    // 1. Kiểm tra hỏi thời tiết
    if (q.contains('thời tiết') || q.contains('dự báo') || q.contains('trời hôm nay') || q.contains('ngoài trời')) {
      isWeather = true;
    }

    // 2. Kiểm tra đổi thiết bị
    for (final dev in availableDevices) {
      if (q.contains(dev.toLowerCase())) {
        targetDevice = dev;
        changes.add('Chuyển sang $dev');
        break;
      }
    }

    // 3. Kiểm tra Nguồn (On / Off)
    final isOnKeyword = q.contains('bật') || q.contains('mở') || q.contains('khởi động') || q.contains('chạy') || q.contains('on');
    final isOffKeyword = q.contains('tắt') || q.contains('dừng') || q.contains('nghỉ') || q.contains('tắt đi') || q.contains('off');

    if (isOffKeyword && !isOnKeyword) {
      newPower = false;
      changes.add('Tắt điều hòa');
    } else if (isOnKeyword && !isOffKeyword) {
      newPower = true;
      changes.add('Bật điều hòa');
    }

    // 4. Kiểm tra Chế độ (Mode)
    if (q.contains('làm lạnh') || q.contains('làm mát') || q.contains('mát') || q.contains('cool') || q.contains('chế độ lạnh')) {
      newMode = AcMode.cool;
      newPower = true;
      changes.add('Chế độ Làm lạnh');
    } else if (q.contains('sưởi') || q.contains('làm ấm') || q.contains('ấm') || q.contains('heat') || q.contains('chế độ sưởi')) {
      newMode = AcMode.heat;
      newPower = true;
      changes.add('Chế độ Sưởi');
    } else if (q.contains('hút ẩm') || q.contains('chống nồm') || q.contains('khô') || q.contains('dry') || q.contains('chế độ khô')) {
      newMode = AcMode.dry;
      newPower = true;
      changes.add('Chế độ Hút ẩm');
    } else if (q.contains('chỉ quạt') || q.contains('chế độ quạt') || (q.contains('quạt') && !q.contains('quạt nhẹ') && !q.contains('quạt mạnh') && !q.contains('quạt vừa') && !q.contains('quạt tự động'))) {
      if (!q.contains('bật quạt') && !q.contains('quạt lớn') && !q.contains('quạt nhỏ')) {
        newMode = AcMode.fan;
        newPower = true;
        changes.add('Chế độ Quạt');
      }
    } else if (q.contains('tự động') || q.contains('tự chỉnh') || q.contains('auto')) {
      newMode = AcMode.auto;
      newPower = true;
      changes.add('Chế độ Tự động');
    }

    // 5. Kiểm tra Tốc độ quạt (Fan speed)
    if (q.contains('quạt nhẹ') || q.contains('quạt nhỏ') || q.contains('quạt yếu') || q.contains('hiu hiu') || q.contains('mức 1') || q.contains('quạt 1')) {
      newFan = AcFan.low;
      newPower = true;
      changes.add('Quạt nhẹ');
    } else if (q.contains('quạt vừa') || q.contains('quạt trung bình') || q.contains('mức 2') || q.contains('quạt 2')) {
      newFan = AcFan.medium;
      newPower = true;
      changes.add('Quạt vừa');
    } else if (q.contains('quạt mạnh') || q.contains('quạt lớn') || q.contains('tối đa') || q.contains('mức 3') || q.contains('quạt 3') || q.contains('quạt to')) {
      newFan = AcFan.high;
      newPower = true;
      changes.add('Quạt mạnh');
    } else if (q.contains('quạt tự động') || q.contains('fan auto') || q.contains('quạt auto')) {
      newFan = AcFan.auto;
      newPower = true;
      changes.add('Quạt tự động');
    }

    // 6. Kiểm tra Nhiệt độ (Trực tiếp hoặc Tương đối)
    final explicitTemp = _extractTempFromQuery(q, minTemp);
    if (explicitTemp != null) {
      newTemp = explicitTemp;
      newPower = true;
      changes.add('Nhiệt độ $newTemp°C');
    } else {
      // Xử lý tăng / giảm tương đối
      final delta = _extractTempDelta(q);
      if (delta != 0) {
        final target = (currentTemp + delta).clamp(minTemp, 30);
        newTemp = target;
        newPower = true;
        changes.add('${delta > 0 ? "Tăng" : "Giảm"} nhiệt độ thành $newTemp°C');
      } else if (q.contains('nóng quá') || q.contains('nóng quá trời') || q.contains('ngột ngạt')) {
        final target = (currentTemp - 2).clamp(minTemp, 30);
        newTemp = target;
        newMode = AcMode.cool;
        newPower = true;
        changes.add('Làm mát phòng: $newTemp°C, chế độ Làm lạnh');
      } else if (q.contains('lạnh quá') || q.contains('rét quá') || q.contains('buốt quá')) {
        final target = (currentTemp + 2).clamp(minTemp, 30);
        newTemp = target;
        newPower = true;
        changes.add('Tăng nhiệt độ lên $newTemp°C cho bớt lạnh');
      }
    }

    // 7. Tính năng thêm (Feat)
    if (q.contains('đảo gió') || q.contains('cánh gió') || q.contains('xoay cánh') || q.contains('quay quạt') || q.contains('swing')) {
      featChanges[Feat.swing] = true;
      changes.add('Bật đảo gió');
    }
    if (q.contains('ngủ') || q.contains('ban đêm') || q.contains('sleep')) {
      featChanges[Feat.sleep] = true;
      changes.add('Bật chế độ ngủ');
    }
    if (q.contains('turbo') || q.contains('mát nhanh') || q.contains('làm lạnh nhanh') || q.contains('siêu tốc')) {
      featChanges[Feat.turbo] = true;
      changes.add('Bật Turbo làm lạnh nhanh');
    }
    if (q.contains('bật đèn')) {
      featChanges[Feat.light] = true;
      changes.add('Bật đèn màn hình');
    } else if (q.contains('tắt đèn')) {
      featChanges[Feat.light] = false;
      changes.add('Tắt đèn màn hình');
    }

    // Dựng câu trả lời
    final String responseMsg;
    final bool hasAction = changes.isNotEmpty;

    if (isWeather) {
      final weatherInfo = weatherSummary ?? 'Chưa có thông tin thời tiết.';
      if (hasAction) {
        responseMsg = '$weatherInfo\n\nĐã thực hiện: ${changes.join(", ")}.';
      } else {
        responseMsg = weatherInfo;
      }
    } else if (hasAction) {
      responseMsg = 'Đã nhận lệnh: ${changes.join(", ")}.';
    } else {
      responseMsg = 'Chưa nhận diện được lệnh điều khiển cụ thể. Bạn thử nói: "Bật 24 độ làm lạnh", "Nóng quá hạ 2 độ", "Tắt điều hòa"...';
    }

    return AiResult(
      query: query,
      response: responseMsg,
      power: newPower,
      temp: newTemp,
      mode: newMode,
      fan: newFan,
      featChanges: featChanges,
      targetDeviceName: targetDevice,
      isWeatherQuery: isWeather,
      actionTaken: hasAction,
    );
  }

  /// Trích xuất nhiệt độ cụ thể từ câu (VD: "24 độ", "set 25°C", "hai mươi tư độ")
  static int? _extractTempFromQuery(String q, int minTemp) {
    // Tìm số dạng chữ hoặc số
    final numMatch = RegExp(r'(\d+)\s*(độ|c|°)?').firstMatch(q);
    if (numMatch != null) {
      final val = int.tryParse(numMatch.group(1)!);
      if (val != null && val >= 16 && val <= 30) {
        return val.clamp(minTemp, 30);
      }
    }

    // Các từ ngữ chữ số thông dụng
    final wordsMap = {
      'mười tám': 18, 'mười chín': 19, 'hai mươi': 20,
      'hai mốt': 21, 'hai mươi mốt': 21,
      'hai hai': 22, 'hai mươi hai': 22,
      'hai ba': 23, 'hai mươi ba': 23,
      'hai tư': 24, 'hai mươi tư': 24, 'hai bốn': 24, 'hai mươi bốn': 24,
      'hai lăm': 25, 'hai mươi lăm': 25, 'hai năm': 25,
      'hai sáu': 26, 'hai mươi sáu': 26,
      'hai bảy': 27, 'hai mươi bảy': 27,
      'hai tám': 28, 'hai mươi tám': 28,
      'hai chín': 29, 'hai mươi chín': 29,
      'ba mươi': 30, 'ba chục': 30,
    };

    for (final entry in wordsMap.entries) {
      if (q.contains(entry.key)) {
        return entry.value.clamp(minTemp, 30);
      }
    }
    return null;
  }

  /// Trích xuất độ chênh lệch nhiệt độ (VD: "tăng 3 độ" -> +3, "giảm 2 độ" -> -2)
  static int _extractTempDelta(String q) {
    final isIncrease = q.contains('tăng') || q.contains('cộng');
    final isDecrease = q.contains('giảm') || q.contains('trừ') || q.contains('hạ');

    if (!isIncrease && !isDecrease) return 0;

    final match = RegExp(r'(tăng|giảm|hạ|cộng|trừ)\s*(\d+)').firstMatch(q);
    int amount = 2; // mặc định 2 độ nếu không nói rõ số
    if (match != null) {
      amount = int.tryParse(match.group(2)!) ?? 2;
    }

    return isDecrease ? -amount : amount;
  }

  /// Xử lý qua Gemini REST API nếu có API key
  static Future<AiResult?> _processWithGemini(
    String query, {
    required bool currentPower,
    required int currentTemp,
    required AcMode currentMode,
    required AcFan currentFan,
    required Map<Feat, bool> currentFeat,
    required List<String> availableDevices,
    String? currentDeviceName,
    int minTemp = 16,
    required String apiKey,
    String? weatherSummary,
  }) async {
    final systemPrompt = '''
Bạn là trợ lý điều khiển điều hòa thông minh. Hãy phân tích yêu cầu tiếng Việt của người dùng và trả về kết quả định dạng JSON thuần túy (không dải markdown), chứa các trường:
{
  "power": true|false|null (bật/tắt nguồn),
  "temp": number|null (nhiệt độ từ $minTemp đến 30),
  "mode": "cool"|"heat"|"dry"|"fan"|"auto"|null,
  "fan": "low"|"medium"|"high"|"auto"|null,
  "swing": true|false|null,
  "sleep": true|false|null,
  "turbo": true|false|null,
  "light": true|false|null,
  "device": string|null (tên thiết bị nếu người dùng yêu cầu chuyển thiết bị),
  "reply": "câu trả lời thân thiện cho người dùng"
}
Trạng thái hiện tại: Nguồn ${currentPower ? "BẬT" : "TẮT"}, Nhiệt độ $currentTemp°C, Chế độ ${currentMode.name}, Quạt ${currentFan.name}, Thiết bị hiện tại: ${currentDeviceName ?? "Chưa rõ"}.
Danh sách thiết bị sẵn có: ${availableDevices.join(", ")}.
Thời tiết ngoài trời: ${weatherSummary ?? "Không có"}.
''';

    final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$apiKey');

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': '$systemPrompt\nLệnh của người dùng: "$query"'}
            ]
          }
        ]
      }),
    ).timeout(const Duration(seconds: 8));

    if (response.statusCode == 200) {
      final jsonBody = jsonDecode(response.body);
      final text = jsonBody['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
      if (text != null) {
        return _parseJsonResponse(text, query: query, minTemp: minTemp);
      }
    }
    return null;
  }

  /// Xử lý qua OpenRouter REST API
  static Future<AiResult?> _processWithOpenRouter(
    String query, {
    required bool currentPower,
    required int currentTemp,
    required AcMode currentMode,
    required AcFan currentFan,
    required Map<Feat, bool> currentFeat,
    required List<String> availableDevices,
    String? currentDeviceName,
    int minTemp = 16,
    required String apiKey,
    String? openRouterModel,
    String? weatherSummary,
  }) async {
    final systemPrompt = '''
Bạn là trợ lý điều khiển điều hòa thông minh. Hãy phân tích yêu cầu tiếng Việt của người dùng và trả về kết quả định dạng JSON thuần túy (không dải markdown), chứa các trường:
{
  "power": true|false|null (bật/tắt nguồn),
  "temp": number|null (nhiệt độ từ $minTemp đến 30),
  "mode": "cool"|"heat"|"dry"|"fan"|"auto"|null,
  "fan": "low"|"medium"|"high"|"auto"|null,
  "swing": true|false|null,
  "sleep": true|false|null,
  "turbo": true|false|null,
  "light": true|false|null,
  "device": string|null (tên thiết bị nếu người dùng yêu cầu chuyển thiết bị),
  "reply": "câu trả lời thân thiện cho người dùng"
}
Trạng thái hiện tại: Nguồn ${currentPower ? "BẬT" : "TẮT"}, Nhiệt độ $currentTemp°C, Chế độ ${currentMode.name}, Quạt ${currentFan.name}, Thiết bị hiện tại: ${currentDeviceName ?? "Chưa rõ"}.
Danh sách thiết bị sẵn có: ${availableDevices.join(", ")}.
Thời tiết ngoài trời: ${weatherSummary ?? "Không có"}.
''';

    final model = (openRouterModel != null && openRouterModel.trim().isNotEmpty)
        ? openRouterModel.trim()
        : openRouterFreeModels.first;

    final url = Uri.parse('https://openrouter.ai/api/v1/chat/completions');

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${apiKey.trim()}',
        'HTTP-Referer': 'https://com.example.test2',
        'X-Title': 'AC Remote App',
      },
      body: jsonEncode({
        'model': model,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': 'Lệnh của người dùng: "$query"'}
        ],
      }),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final jsonBody = jsonDecode(response.body);
      final text = jsonBody['choices']?[0]?['message']?['content'] as String?;
      if (text != null) {
        return _parseJsonResponse(text, query: query, minTemp: minTemp);
      }
    }
    return null;
  }

  /// Kiểm tra OpenRouter API Key
  static Future<bool> testOpenRouterApiKey(String apiKey, {String? model}) async {
    final key = apiKey.trim().isEmpty ? defaultOpenRouterApiKey : apiKey.trim();
    if (key.isEmpty) return false;
    try {
      final targetModel = (model != null && model.trim().isNotEmpty)
          ? model.trim()
          : openRouterFreeModels.first;

      final url = Uri.parse('https://openrouter.ai/api/v1/chat/completions');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $key',
          'HTTP-Referer': 'https://com.example.test2',
          'X-Title': 'AC Remote App',
        },
        body: jsonEncode({
          'model': targetModel,
          'messages': [
            {'role': 'user', 'content': 'Hello'}
          ]
        }),
      ).timeout(const Duration(seconds: 8));

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Hàm hỗ trợ giải mã chuỗi JSON phản hồi từ AI thành AiResult
  static AiResult? _parseJsonResponse(String text, {required String query, required int minTemp}) {
    try {
      final jsonStr = text.replaceAll('```json', '').replaceAll('```', '').trim();
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;

      AcMode? parsedMode;
      if (map['mode'] == 'cool') parsedMode = AcMode.cool;
      if (map['mode'] == 'heat') parsedMode = AcMode.heat;
      if (map['mode'] == 'dry') parsedMode = AcMode.dry;
      if (map['mode'] == 'fan') parsedMode = AcMode.fan;
      if (map['mode'] == 'auto') parsedMode = AcMode.auto;

      AcFan? parsedFan;
      if (map['fan'] == 'low') parsedFan = AcFan.low;
      if (map['fan'] == 'medium') parsedFan = AcFan.medium;
      if (map['fan'] == 'high') parsedFan = AcFan.high;
      if (map['fan'] == 'auto') parsedFan = AcFan.auto;

      final featChanges = <Feat, bool>{};
      if (map['swing'] != null) featChanges[Feat.swing] = map['swing'] == true;
      if (map['sleep'] != null) featChanges[Feat.sleep] = map['sleep'] == true;
      if (map['turbo'] != null) featChanges[Feat.turbo] = map['turbo'] == true;
      if (map['light'] != null) featChanges[Feat.light] = map['light'] == true;

      final targetDev = map['device'] as String?;
      final bool action = map['power'] != null ||
          map['temp'] != null ||
          parsedMode != null ||
          parsedFan != null ||
          featChanges.isNotEmpty ||
          targetDev != null;

      return AiResult(
        query: query,
        response: map['reply'] as String? ?? 'Đã xử lý xong.',
        power: map['power'] as bool?,
        temp: (map['temp'] as num?)?.toInt().clamp(minTemp, 30),
        mode: parsedMode,
        fan: parsedFan,
        featChanges: featChanges,
        targetDeviceName: targetDev,
        actionTaken: action,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Modal Bottom Sheet giao diện Trợ lý Giọng nói AI.
class AiAssistantSheet extends StatefulWidget {
  final bool currentPower;
  final int currentTemp;
  final AcMode currentMode;
  final AcFan currentFan;
  final Map<Feat, bool> currentFeat;
  final List<String> availableDevices;
  final String? currentDeviceName;
  final int minTemp;
  final String aiProvider;
  final String? apiKey;
  final String? openRouterModel;
  final String? weatherSummary;
  final Function(AiResult result) onResultApplied;

  const AiAssistantSheet({
    super.key,
    required this.currentPower,
    required this.currentTemp,
    required this.currentMode,
    required this.currentFan,
    required this.currentFeat,
    required this.availableDevices,
    this.currentDeviceName,
    this.minTemp = 16,
    this.aiProvider = 'gemini',
    this.apiKey,
    this.openRouterModel,
    this.weatherSummary,
    required this.onResultApplied,
  });

  @override
  State<AiAssistantSheet> createState() => _AiAssistantSheetState();
}

class _AiAssistantSheetState extends State<AiAssistantSheet>
    with SingleTickerProviderStateMixin {
  static const _ch = MethodChannel('ir');

  bool _isListening = false;
  bool _isProcessing = false;
  String _speechText = '';
  String _statusMessage = 'Bấm micro để bắt đầu nói hoặc nhập văn bản';
  AiResult? _latestResult;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _ch.setMethodCallHandler(_handleNativeSpeechEvent);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _textController.dispose();
    _stopListeningNative();
    super.dispose();
  }

  Future<dynamic> _handleNativeSpeechEvent(MethodCall call) async {
    if (call.method == 'onSpeechEvent') {
      final map = Map<String, dynamic>.from(call.arguments as Map);
      final type = map['type'] as String;

      if (!mounted) return;

      if (type == 'start' || type == 'ready') {
        setState(() {
          _isListening = true;
          _statusMessage = 'Đang lắng nghe... Hãy nói lệnh của bạn';
        });
      } else if (type == 'partial') {
        final text = map['text'] as String? ?? '';
        if (text.isNotEmpty) {
          setState(() {
            _speechText = text;
          });
        }
      } else if (type == 'final') {
        final text = (map['text'] as String? ?? '').trim();
        final textToUse = text.isNotEmpty ? text : _speechText.trim();
        if (textToUse.isNotEmpty && _isListening) {
          _processQuery(textToUse);
        } else if (textToUse.isEmpty) {
          setState(() {
            _isListening = false;
            _statusMessage = 'Không nghe rõ câu lệnh, vui lòng bấm micro nói lại.';
          });
        }
      } else if (type == 'error') {
        final capturedText = _speechText.trim();
        if (capturedText.isNotEmpty && _isListening) {
          // Đã thu được văn bản từ giọng nói trước khi bị hết giờ -> dùng luôn!
          _processQuery(capturedText);
        } else {
          setState(() {
            _isListening = false;
            _statusMessage = map['message'] as String? ?? 'Lỗi nhận diện giọng nói.';
          });
        }
      } else if (type == 'end') {
        if (_isListening && _speechText.trim().isNotEmpty) {
          _processQuery(_speechText.trim());
        } else {
          setState(() {
            _isListening = false;
          });
        }
      }
    }
  }

  Future<void> _startListeningNative() async {
    setState(() {
      _speechText = '';
      _latestResult = null;
      _statusMessage = 'Đang khởi động micro...';
    });

    try {
      await _ch.invokeMethod('startSpeech');
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _isListening = false;
        _statusMessage = 'Lỗi: ${e.message ?? "Không khởi động được micro"}';
      });
    }
  }

  Future<void> _stopListeningNative() async {
    try {
      await _ch.invokeMethod('stopSpeech');
    } catch (_) {}
  }

  Future<void> _userStopListening() async {
    await _stopListeningNative();
    if (!mounted) return;

    final capturedText = _speechText.trim();
    if (capturedText.isNotEmpty) {
      // Đã có câu chữ thu được -> xử lý ngay câu lệnh
      _processQuery(capturedText);
    } else {
      setState(() {
        _isListening = false;
        _statusMessage = 'Đã dừng nghe. Bấm micro để thử lại.';
      });
    }
  }

  Future<void> _processQuery(String q) async {
    final text = q.trim();
    if (text.isEmpty) return;

    _stopListeningNative();

    setState(() {
      _isListening = false;
      _isProcessing = true;
      _speechText = text;
      _statusMessage = 'AI đang suy nghĩ & xử lý...';
    });

    final res = await AiAssistantEngine.processQuery(
      text,
      currentPower: widget.currentPower,
      currentTemp: widget.currentTemp,
      currentMode: widget.currentMode,
      currentFan: widget.currentFan,
      currentFeat: widget.currentFeat,
      availableDevices: widget.availableDevices,
      currentDeviceName: widget.currentDeviceName,
      minTemp: widget.minTemp,
      aiProvider: widget.aiProvider,
      apiKey: widget.apiKey,
      openRouterModel: widget.openRouterModel,
      weatherSummary: widget.weatherSummary,
    );

    if (!mounted) return;

    setState(() {
      _isProcessing = false;
      _latestResult = res;
      _statusMessage = res.response;
    });

    // Áp dụng thay đổi cho màn chính
    widget.onResultApplied(res);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Thanh kéo nhỏ ở trên
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // Tiêu đề modal
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_awesome, color: cs.primary),
                  const SizedBox(width: 8),
                  const Text(
                    'Trợ lý Giọng nói AI',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Trạng thái giọng nói / Văn bản nghe được
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.indigo.shade100),
                ),
                child: Column(
                  children: [
                    Text(
                      _speechText.isNotEmpty ? '"$_speechText"' : _statusMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: _speechText.isNotEmpty ? 16 : 14,
                        fontWeight: _speechText.isNotEmpty ? FontWeight.w600 : FontWeight.normal,
                        color: _speechText.isNotEmpty ? Colors.indigo.shade900 : Colors.black87,
                      ),
                    ),
                    if (_speechText.isNotEmpty && _isListening)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'Đang lắng nghe...',
                          style: TextStyle(fontSize: 12, color: Colors.indigo),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Nút Micro hiển thị hiệu ứng xung nhịp khi đang nghe
              ScaleTransition(
                scale: _isListening ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
                child: Material(
                  color: _isListening
                      ? Colors.red.shade600
                      : (_isProcessing ? Colors.orange : cs.primary),
                  shape: const CircleBorder(),
                  elevation: 4,
                  shadowColor: Colors.black38,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _isProcessing
                        ? null
                        : (_isListening ? _userStopListening : _startListeningNative),
                    child: SizedBox(
                      width: 80,
                      height: 80,
                      child: Center(
                        child: _isProcessing
                            ? const CircularProgressIndicator(color: Colors.white)
                            : Icon(
                                _isListening ? Icons.mic : Icons.mic_none,
                                size: 40,
                                color: Colors.white,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isListening
                    ? 'Bấm để dừng nghe'
                    : (_isProcessing ? 'Đang xử lý...' : 'Bấm micro để nói'),
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 20),

              // Thẻ kết quả xử lý từ AI (nếu có)
              if (_latestResult != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _latestResult!.actionTaken ? Colors.green.shade50 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _latestResult!.actionTaken ? Colors.green.shade300 : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _latestResult!.actionTaken ? Icons.check_circle_outline : Icons.info_outline,
                        color: _latestResult!.actionTaken ? Colors.green.shade700 : Colors.black54,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _latestResult!.response,
                          style: TextStyle(
                            fontSize: 14,
                            color: _latestResult!.actionTaken ? Colors.green.shade900 : Colors.black87,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Các gợi ý câu lệnh nhanh (Prompt Chips)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Gợi ý câu lệnh mẫu:',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip('❄️ Bật 24°C làm lạnh', 'Bật 24 độ chế độ làm lạnh'),
                  _chip('☀️ Nóng quá hạ 2°C', 'Nóng quá hạ 2 độ'),
                  _chip('🔥 Bật sưởi 28°C', 'Bật sưởi 28 độ quạt mạnh'),
                  _chip('🌙 Bật chế độ ngủ', 'Bật chế độ ngủ'),
                  _chip('🌀 Bật đảo gió', 'Bật đảo gió'),
                  _chip('🌤️ Thời tiết hôm nay?', 'Thời tiết hôm nay thế nào'),
                  _chip('🛑 Tắt điều hòa', 'Tắt điều hòa đi'),
                ],
              ),
              const SizedBox(height: 16),

              // Ô nhập liệu văn bản tự do
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        hintText: 'Hoặc gõ câu lệnh ở đây...',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                      ),
                      onSubmitted: (val) {
                        _textController.clear();
                        _processQuery(val);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () {
                      final text = _textController.text;
                      _textController.clear();
                      _processQuery(text);
                    },
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, String query) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: () => _processQuery(query),
    );
  }
}

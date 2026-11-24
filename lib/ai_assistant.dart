import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'protocols.dart';
import 'secrets.dart';
import 'tv.dart';

/// Kết quả xử lý câu lệnh tự nhiên của AI.
class AiResult {
  final String query;
  final String response;
  // Điều hòa:
  final bool? power;
  final int? temp;
  final AcMode? mode;
  final AcFan? fan;
  final Map<Feat, bool> featChanges;
  // TV:
  final TvKey? tvKey;
  final int tvRepeat;
  // Chung:
  final String? targetDeviceName;
  final String? targetDeviceKind; // 'ac' hoặc 'tv'
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
    this.tvKey,
    this.tvRepeat = 1,
    this.targetDeviceName,
    this.targetDeviceKind,
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
  /// Xử lý câu lệnh ngôn ngữ tự nhiên tiếng Việt cho toàn bộ thiết bị hỗ trợ (Điều hòa & TV).
  static Future<AiResult> processQuery(
    String query, {
    bool currentPower = false,
    int currentTemp = 26,
    AcMode currentMode = AcMode.cool,
    AcFan currentFan = AcFan.auto,
    Map<Feat, bool> currentFeat = const {},
    List<String> availableDevices = const [],
    List<Map<String, Object?>>? deviceList,
    String? currentDeviceName,
    String? currentDeviceKind, // 'ac' hoặc 'tv'
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

    // Đồng bộ danh sách tên thiết bị nếu có deviceList
    final effectiveDevices = availableDevices.isNotEmpty
        ? availableDevices
        : (deviceList != null
            ? deviceList
                .map((d) => (d['name'] as String?) ?? '')
                .where((s) => s.isNotEmpty)
                .toList()
            : <String>[]);

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
            availableDevices: effectiveDevices,
            deviceList: deviceList,
            currentDeviceName: currentDeviceName,
            currentDeviceKind: currentDeviceKind,
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
            availableDevices: effectiveDevices,
            deviceList: deviceList,
            currentDeviceName: currentDeviceName,
            currentDeviceKind: currentDeviceKind,
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
      availableDevices: effectiveDevices,
      deviceList: deviceList,
      currentDeviceName: currentDeviceName,
      currentDeviceKind: currentDeviceKind,
      minTemp: minTemp,
      weatherSummary: weatherSummary,
    );
  }

  /// Kiểm tra API Key xem có kết nối tốt với Gemini hay không.
  static Future<bool> testApiKey(String apiKey) async {
    final key = apiKey.trim().isEmpty ? defaultGeminiApiKey : apiKey.trim();
    if (key.isEmpty) return false;
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

  /// Bộ xử lý ngôn ngữ tự nhiên Local (Vietnamese Smart Parser cho Điều hòa & TV).
  static AiResult _processLocally(
    String query, {
    required bool currentPower,
    required int currentTemp,
    required AcMode currentMode,
    required AcFan currentFan,
    required Map<Feat, bool> currentFeat,
    required List<String> availableDevices,
    List<Map<String, Object?>>? deviceList,
    String? currentDeviceName,
    String? currentDeviceKind,
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
    TvKey? targetTvKey;
    int tvRepeat = 1;
    String? targetDevice;
    String? targetKind = currentDeviceKind;
    bool isWeather = false;

    // 1. Kiểm tra hỏi thời tiết
    if (q.contains('thời tiết') ||
        q.contains('dự báo') ||
        q.contains('trời hôm nay') ||
        q.contains('ngoài trời') ||
        q.contains('mưa không')) {
      isWeather = true;
    }

    // 2. Nhận diện thiết bị đích
    // A) Tìm theo tên thiết bị có trong danh sách
    if (deviceList != null && deviceList.isNotEmpty) {
      for (final dev in deviceList) {
        final name = (dev['name'] as String? ?? '').toLowerCase();
        if (name.isNotEmpty && q.contains(name)) {
          targetDevice = dev['name'] as String;
          targetKind = dev['kind'] as String? ?? 'ac';
          changes.add('Chuyển sang $targetDevice');
          break;
        }
      }
    }
    if (targetDevice == null) {
      for (final dev in availableDevices) {
        if (dev.isNotEmpty && q.contains(dev.toLowerCase())) {
          targetDevice = dev;
          changes.add('Chuyển sang $dev');
          break;
        }
      }
    }

    // B) Phân loại thiết bị nếu câu lệnh chỉ định rõ loại thiết bị
    final hasTvKeyword = q.contains('tv') || q.contains('tivi') || q.contains('ti vi');
    final hasAcKeyword = q.contains('điều hòa') || q.contains('máy lạnh') || q.contains('may lanh');

    if (hasTvKeyword && !hasAcKeyword) {
      targetKind = 'tv';
      if (targetDevice == null && deviceList != null) {
        final tvs = deviceList.where((d) => d['kind'] == 'tv');
        if (tvs.isNotEmpty) targetDevice = tvs.first['name'] as String?;
      }
    } else if (hasAcKeyword && !hasTvKeyword) {
      targetKind = 'ac';
      if (targetDevice == null && deviceList != null) {
        final acs = deviceList.where((d) => d['kind'] != 'tv');
        if (acs.isNotEmpty) targetDevice = acs.first['name'] as String?;
      }
    }

    // 3. Phân biệt ngữ cảnh: Lệnh cho TV hay Điều hòa?
    final isTvCommand = targetKind == 'tv' ||
        hasTvKeyword ||
        q.contains('âm lượng') ||
        q.contains('kênh') ||
        q.contains('mute') ||
        q.contains('tắt tiếng') ||
        q.contains('bật tiếng') ||
        q.contains('câm tiếng') ||
        q.contains('nguồn vào') ||
        q.contains('cổng hdmi') ||
        q.contains('đầu vào') ||
        (q.contains('menu') && !q.contains('nhiệt')) ||
        ((q.contains('to lên') || q.contains('nhỏ lại') || q.contains('to tiếng') || q.contains('nhỏ tiếng')) &&
            !q.contains('quạt') && !q.contains('gió'));

    if (isTvCommand) {
      targetKind = 'tv';

      // Kiểm tra các từ khóa âm lượng
      final hasVolWord = q.contains('âm lượng') ||
          q.contains('âm thanh') ||
          q.contains('tiếng') ||
          q.contains('volume') ||
          q.contains('vol');

      final isVolUp = (q.contains('tăng') ||
              q.contains('to') ||
              q.contains('lớn') ||
              q.contains('cộng') ||
              q.contains('thêm')) &&
          hasVolWord;

      final isVolDown = (q.contains('giảm') ||
              q.contains('nhỏ') ||
              q.contains('hạ') ||
              q.contains('bớt') ||
              q.contains('trừ')) &&
          hasVolWord;

      // 3.1. Âm lượng TV (Volume Up / Down)
      if (isVolUp) {
        targetTvKey = TvKey.volUp;
        tvRepeat = _extractRepeatCount(q);
        changes.add('Tăng âm lượng TV${tvRepeat > 1 ? " ($tvRepeat nấc)" : ""}');
      } else if (isVolDown) {
        targetTvKey = TvKey.volDown;
        tvRepeat = _extractRepeatCount(q);
        changes.add('Giảm âm lượng TV${tvRepeat > 1 ? " ($tvRepeat nấc)" : ""}');
      }
      // 3.2. Tắt tiếng / Bật tiếng (Mute)
      else if (q.contains('tắt tiếng') ||
          q.contains('tắt âm') ||
          q.contains('mute') ||
          q.contains('im lặng') ||
          q.contains('bật tiếng') ||
          q.contains('mở tiếng') ||
          q.contains('câm tiếng')) {
        targetTvKey = TvKey.mute;
        changes.add('Tắt/Bật tiếng TV (Mute)');
      }
      // 3.3. Kênh (Channel Up / Down)
      else if (q.contains('kênh trước') ||
          q.contains('lùi kênh') ||
          q.contains('xuống kênh') ||
          q.contains('về kênh trước') ||
          q.contains('ch down') ||
          q.contains('channel down')) {
        targetTvKey = TvKey.chDown;
        tvRepeat = _extractRepeatCount(q);
        changes.add('Về kênh trước');
      } else if (q.contains('chuyển kênh') ||
          q.contains('kênh tiếp theo') ||
          q.contains('kênh sau') ||
          q.contains('kênh tới') ||
          q.contains('kênh kế tiếp') ||
          q.contains('tăng kênh') ||
          q.contains('lên kênh') ||
          q.contains('ch up') ||
          q.contains('channel up') ||
          q.contains('đổi kênh')) {
        targetTvKey = TvKey.chUp;
        tvRepeat = _extractRepeatCount(q);
        changes.add('Chuyển kênh tiếp theo');
      }
      // 3.4. Nguồn vào / Đầu vào (Input)
      else if (q.contains('nguồn vào') ||
          q.contains('đầu vào') ||
          q.contains('cổng hdmi') ||
          q.contains('chọn hdmi') ||
          q.contains('chuyển cổng') ||
          q.contains('input') ||
          q.contains('cổng av')) {
        targetTvKey = TvKey.input;
        changes.add('Chuyển nguồn vào TV (Input)');
      }
      // 3.5. Menu
      else if (q.contains('menu') || q.contains('cài đặt tv') || q.contains('danh mục tv')) {
        targetTvKey = TvKey.menu;
        changes.add('Mở Menu TV');
      }
      // 3.6. Điều hướng và OK, Back
      else if (q.contains('bấm ok') ||
          q.contains('chọn ok') ||
          q.contains('enter') ||
          q == 'ok' ||
          q.contains('ok tv') ||
          q.contains('chọn')) {
        targetTvKey = TvKey.ok;
        changes.add('Bấm OK');
      } else if (q.contains('quay lại') || q.contains('trở về') || q.contains('back') || q.contains('thoát')) {
        targetTvKey = TvKey.back;
        changes.add('Quay lại (Back)');
      } else if (q.contains('mũi tên lên') ||
          q.contains('hướng lên') ||
          q.contains('lên trên') ||
          q.contains('đi lên') ||
          q.contains('nút lên') ||
          q == 'lên' ||
          q.contains('bấm lên')) {
        targetTvKey = TvKey.up;
        changes.add('Lên trên');
      } else if (q.contains('mũi tên xuống') ||
          q.contains('hướng xuống') ||
          q.contains('xuống dưới') ||
          q.contains('đi xuống') ||
          q.contains('nút xuống') ||
          q == 'xuống' ||
          q.contains('bấm xuống')) {
        targetTvKey = TvKey.down;
        changes.add('Xuống dưới');
      } else if (q.contains('sang trái') ||
          q.contains('mũi tên trái') ||
          q.contains('qua trái') ||
          q.contains('hướng trái') ||
          q.contains('nút trái') ||
          q == 'trái' ||
          q.contains('bấm trái')) {
        targetTvKey = TvKey.left;
        changes.add('Sang trái');
      } else if (q.contains('sang phải') ||
          q.contains('mũi tên phải') ||
          q.contains('qua phải') ||
          q.contains('hướng phải') ||
          q.contains('nút phải') ||
          q == 'phải' ||
          q.contains('bấm phải')) {
        targetTvKey = TvKey.right;
        changes.add('Sang phải');
      }
      // 3.7. Nguồn TV (Bật / Tắt)
      else if (q.contains('tắt') || q.contains('dừng') || q.contains('nghỉ') || q.contains('off')) {
        targetTvKey = TvKey.power;
        newPower = false;
        changes.add('Tắt TV');
      } else if (q.contains('bật') ||
          q.contains('mở') ||
          q.contains('khởi động') ||
          q.contains('chạy') ||
          q.contains('on')) {
        targetTvKey = TvKey.power;
        newPower = true;
        changes.add('Bật TV');
      }
    } else {
      // 4. Lệnh cho Điều hòa (AC)
      targetKind = 'ac';

      // 4.1. Nguồn (On / Off)
      final isOnKeyword = q.contains('bật') ||
          q.contains('mở') ||
          q.contains('khởi động') ||
          q.contains('chạy') ||
          q.contains('on');
      final isOffKeyword = q.contains('tắt') ||
          q.contains('dừng') ||
          q.contains('nghỉ') ||
          q.contains('tắt đi') ||
          q.contains('off');

      if (isOffKeyword && !isOnKeyword) {
        newPower = false;
        changes.add('Tắt điều hòa');
      } else if (isOnKeyword && !isOffKeyword) {
        newPower = true;
        changes.add('Bật điều hòa');
      }

      // 4.2. Chế độ (Mode)
      if (q.contains('làm lạnh') ||
          q.contains('làm mát') ||
          q.contains('mát') ||
          q.contains('cool') ||
          q.contains('chế độ lạnh')) {
        newMode = AcMode.cool;
        newPower = true;
        changes.add('Chế độ Làm lạnh');
      } else if (q.contains('sưởi') ||
          q.contains('làm ấm') ||
          q.contains('ấm') ||
          q.contains('heat') ||
          q.contains('chế độ sưởi')) {
        newMode = AcMode.heat;
        newPower = true;
        changes.add('Chế độ Sưởi');
      } else if (q.contains('hút ẩm') ||
          q.contains('chống nồm') ||
          q.contains('khô') ||
          q.contains('dry') ||
          q.contains('chế độ khô')) {
        newMode = AcMode.dry;
        newPower = true;
        changes.add('Chế độ Hút ẩm');
      } else if (q.contains('chỉ quạt') ||
          q.contains('chế độ quạt') ||
          (q.contains('quạt') &&
              !q.contains('quạt nhẹ') &&
              !q.contains('quạt mạnh') &&
              !q.contains('quạt vừa') &&
              !q.contains('quạt tự động'))) {
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

      // 4.3. Tốc độ quạt (Fan speed)
      if (q.contains('quạt nhẹ') ||
          q.contains('quạt nhỏ') ||
          q.contains('quạt yếu') ||
          q.contains('hiu hiu') ||
          q.contains('mức 1') ||
          q.contains('quạt 1')) {
        newFan = AcFan.low;
        newPower = true;
        changes.add('Quạt nhẹ');
      } else if (q.contains('quạt vừa') ||
          q.contains('quạt trung bình') ||
          q.contains('mức 2') ||
          q.contains('quạt 2')) {
        newFan = AcFan.medium;
        newPower = true;
        changes.add('Quạt vừa');
      } else if (q.contains('quạt mạnh') ||
          q.contains('quạt lớn') ||
          q.contains('tối đa') ||
          q.contains('mức 3') ||
          q.contains('quạt 3') ||
          q.contains('quạt to')) {
        newFan = AcFan.high;
        newPower = true;
        changes.add('Quạt mạnh');
      } else if (q.contains('quạt tự động') || q.contains('fan auto') || q.contains('quạt auto')) {
        newFan = AcFan.auto;
        newPower = true;
        changes.add('Quạt tự động');
      }

      // 4.4. Nhiệt độ (Trực tiếp hoặc Tương đối)
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

      // 4.5. Tính năng thêm (Feat)
      if (q.contains('đảo gió') ||
          q.contains('cánh gió') ||
          q.contains('xoay cánh') ||
          q.contains('quay quạt') ||
          q.contains('swing')) {
        featChanges[Feat.swing] = true;
        changes.add('Bật đảo gió');
      }
      if (q.contains('ngủ') || q.contains('ban đêm') || q.contains('sleep')) {
        featChanges[Feat.sleep] = true;
        changes.add('Bật chế độ ngủ');
      }
      if (q.contains('turbo') ||
          q.contains('mát nhanh') ||
          q.contains('làm lạnh nhanh') ||
          q.contains('siêu tốc')) {
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
    }

    // Dựng câu trả lời phản hồi
    final String responseMsg;
    final bool hasAction = changes.isNotEmpty || targetTvKey != null;

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
      responseMsg =
          'Chưa nhận diện được lệnh điều khiển cụ thể. Bạn thử nói:\n• Điều hòa: "Bật 24 độ làm lạnh", "Nóng quá hạ 2 độ", "Tắt điều hòa"\n• TV: "Bật TV", "Tăng âm lượng", "Tắt tiếng TV", "Chuyển kênh"';
    }

    return AiResult(
      query: query,
      response: responseMsg,
      power: newPower,
      temp: newTemp,
      mode: newMode,
      fan: newFan,
      featChanges: featChanges,
      tvKey: targetTvKey,
      tvRepeat: tvRepeat,
      targetDeviceName: targetDevice,
      targetDeviceKind: targetKind,
      isWeatherQuery: isWeather,
      actionTaken: hasAction,
    );
  }

  /// Trích xuất số lần lặp cho phím TV (ví dụ: "tăng 3 nấc" -> 3)
  static int _extractRepeatCount(String q) {
    // 1. Dạng: "3 nấc", "2 lần", "3 mức", "2 kênh"
    final unitMatch = RegExp(r'(\d+)\s*(nấc|lần|mức|kênh|bước)').firstMatch(q);
    if (unitMatch != null) {
      final count = int.tryParse(unitMatch.group(1)!);
      if (count != null && count >= 1 && count <= 10) return count;
    }

    // 2. Dạng liền kề: "tăng 3", "giảm 2"
    final match = RegExp(r'(tăng|giảm|to|nhỏ|lên|xuống|chuyển|thêm|bớt)\s*(\d+)').firstMatch(q);
    if (match != null) {
      final count = int.tryParse(match.group(2)!);
      if (count != null && count >= 1 && count <= 10) return count;
    }

    // 3. Chữ số tiếng Việt: "hai nấc", "ba nấc", "hai lần", "ba lần"
    final wordNumbers = {
      'một': 1, 'hai': 2, 'ba': 3, 'bốn': 4, 'tư': 4, 'năm': 5,
    };
    for (final e in wordNumbers.entries) {
      if (q.contains('${e.key} nấc') ||
          q.contains('${e.key} lần') ||
          q.contains('${e.key} mức') ||
          q.contains('${e.key} kênh')) {
        return e.value;
      }
    }
    return 1;
  }

  /// Trích xuất nhiệt độ cụ thể từ câu (VD: "24 độ", "set 25°C", "hai mươi tư độ")
  static int? _extractTempFromQuery(String q, int minTemp) {
    final numMatch = RegExp(r'(\d+)\s*(độ|c|°)?').firstMatch(q);
    if (numMatch != null) {
      final val = int.tryParse(numMatch.group(1)!);
      if (val != null && val >= 16 && val <= 30) {
        return val.clamp(minTemp, 30);
      }
    }

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

  static String _buildSystemPrompt({
    required bool currentPower,
    required int currentTemp,
    required AcMode currentMode,
    required AcFan currentFan,
    required Map<Feat, bool> currentFeat,
    required List<String> availableDevices,
    List<Map<String, Object?>>? deviceList,
    String? currentDeviceName,
    String? currentDeviceKind,
    int minTemp = 16,
    String? weatherSummary,
  }) {
    final devListStr = deviceList != null
        ? deviceList.map((d) => '${d['name']} (${d['kind'] == 'tv' ? 'TV' : 'Điều hòa'})').join(', ')
        : availableDevices.join(', ');

    return '''
Bạn là trợ lý điều khiển nhà thông minh (Smart Home), hỗ trợ điều khiển toàn bộ thiết bị gồm Điều hòa (Gree, Coolix, LG, Midea, TCL, Samsung, Daikin, Panasonic) và TV (LG, Toshiba).
Hãy phân tích yêu cầu tiếng Việt của người dùng và trả về kết quả định dạng JSON thuần túy (không dải markdown), chứa các trường:
{
  "device": string|null (tên thiết bị người dùng muốn chọn hoặc chuyển sang),
  "device_kind": "ac"|"tv"|null,
  "power": true|false|null (nguồn bật/tắt),
  "temp": number|null (nhiệt độ điều hòa từ $minTemp đến 30),
  "mode": "cool"|"heat"|"dry"|"fan"|"auto"|null,
  "fan": "low"|"medium"|"high"|"auto"|null,
  "swing": true|false|null,
  "sleep": true|false|null,
  "turbo": true|false|null,
  "light": true|false|null,
  "tv_key": "power"|"mute"|"volUp"|"volDown"|"chUp"|"chDown"|"input"|"up"|"down"|"left"|"right"|"ok"|"back"|"menu"|null,
  "tv_repeat": number|null (số lần bấm phím TV nếu tăng/giảm nhiều nấc, ví dụ 1 đến 5),
  "reply": "câu trả lời thân thiện cho người dùng"
}
Trạng thái thiết bị hiện tại: Loại ${currentDeviceKind ?? 'ac'}, Tên: ${currentDeviceName ?? 'Chưa rõ'}, Nguồn: ${currentPower ? 'BẬT' : 'TẮT'}, Nhiệt độ: $currentTemp°C, Chế độ: ${currentMode.name}, Quạt: ${currentFan.name}.
Danh sách thiết bị sẵn có trong nhà: $devListStr.
Thời tiết ngoài trời: ${weatherSummary ?? 'Không có'}.
''';
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
    List<Map<String, Object?>>? deviceList,
    String? currentDeviceName,
    String? currentDeviceKind,
    int minTemp = 16,
    required String apiKey,
    String? weatherSummary,
  }) async {
    final systemPrompt = _buildSystemPrompt(
      currentPower: currentPower,
      currentTemp: currentTemp,
      currentMode: currentMode,
      currentFan: currentFan,
      currentFeat: currentFeat,
      availableDevices: availableDevices,
      deviceList: deviceList,
      currentDeviceName: currentDeviceName,
      currentDeviceKind: currentDeviceKind,
      minTemp: minTemp,
      weatherSummary: weatherSummary,
    );

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
    List<Map<String, Object?>>? deviceList,
    String? currentDeviceName,
    String? currentDeviceKind,
    int minTemp = 16,
    required String apiKey,
    String? openRouterModel,
    String? weatherSummary,
  }) async {
    final systemPrompt = _buildSystemPrompt(
      currentPower: currentPower,
      currentTemp: currentTemp,
      currentMode: currentMode,
      currentFan: currentFan,
      currentFeat: currentFeat,
      availableDevices: availableDevices,
      deviceList: deviceList,
      currentDeviceName: currentDeviceName,
      currentDeviceKind: currentDeviceKind,
      minTemp: minTemp,
      weatherSummary: weatherSummary,
    );

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
        'X-Title': 'Smart Home Remote App',
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
          'X-Title': 'Smart Home Remote App',
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

      // Phím TV
      TvKey? parsedTvKey;
      final rawTvKey = map['tv_key'] as String?;
      if (rawTvKey != null) {
        for (final k in TvKey.values) {
          if (k.name.toLowerCase() == rawTvKey.toLowerCase()) {
            parsedTvKey = k;
            break;
          }
        }
      }
      final int tvRepeat = (map['tv_repeat'] as num?)?.toInt().clamp(1, 10) ?? 1;

      final targetDev = map['device'] as String?;
      final targetKind = map['device_kind'] as String?;

      final bool action = map['power'] != null ||
          map['temp'] != null ||
          parsedMode != null ||
          parsedFan != null ||
          featChanges.isNotEmpty ||
          parsedTvKey != null ||
          targetDev != null;

      return AiResult(
        query: query,
        response: map['reply'] as String? ?? 'Đã xử lý xong.',
        power: map['power'] as bool?,
        temp: (map['temp'] as num?)?.toInt().clamp(minTemp, 30),
        mode: parsedMode,
        fan: parsedFan,
        featChanges: featChanges,
        tvKey: parsedTvKey,
        tvRepeat: tvRepeat,
        targetDeviceName: targetDev,
        targetDeviceKind: targetKind,
        actionTaken: action,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Modal Bottom Sheet giao diện Trợ lý Giọng nói AI (cho toàn bộ thiết bị).
class AiAssistantSheet extends StatefulWidget {
  final bool currentPower;
  final int currentTemp;
  final AcMode currentMode;
  final AcFan currentFan;
  final Map<Feat, bool> currentFeat;
  final List<String> availableDevices;
  final List<Map<String, Object?>>? deviceList;
  final String? currentDeviceName;
  final String? currentDeviceKind; // 'ac' hoặc 'tv'
  final int minTemp;
  final String aiProvider;
  final String? apiKey;
  final String? openRouterModel;
  final String? weatherSummary;
  final Function(AiResult result) onResultApplied;

  const AiAssistantSheet({
    super.key,
    this.currentPower = false,
    this.currentTemp = 26,
    this.currentMode = AcMode.cool,
    this.currentFan = AcFan.auto,
    this.currentFeat = const {},
    this.availableDevices = const [],
    this.deviceList,
    this.currentDeviceName,
    this.currentDeviceKind,
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
      deviceList: widget.deviceList,
      currentDeviceName: widget.currentDeviceName,
      currentDeviceKind: widget.currentDeviceKind,
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

    // Áp dụng thay đổi cho giao diện gọi nó
    widget.onResultApplied(res);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isTv = widget.currentDeviceKind == 'tv';

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
                  Text(
                    widget.currentDeviceName != null
                        ? 'Trợ lý AI · ${widget.currentDeviceName}'
                        : 'Trợ lý Giọng nói AI',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                children: isTv
                    ? [
                        _chip('📺 Bật / Tắt TV', 'Bật TV'),
                        _chip('🔊 Tăng âm lượng', 'Tăng âm lượng TV'),
                        _chip('🔉 Giảm 3 nấc', 'Giảm 3 nấc âm lượng'),
                        _chip('🔇 Tắt tiếng', 'Tắt tiếng TV'),
                        _chip('⏭️ Chuyển kênh', 'Chuyển kênh tiếp theo'),
                        _chip('⏮️ Kênh trước', 'Về kênh trước'),
                        _chip('📋 Menu', 'Mở menu TV'),
                        _chip('🔌 Nguồn vào HDMI', 'Chuyển nguồn vào TV'),
                        _chip('❄️ Bật điều hòa', 'Bật điều hòa 24 độ'),
                      ]
                    : [
                        _chip('❄️ Bật 24°C làm lạnh', 'Bật 24 độ chế độ làm lạnh'),
                        _chip('☀️ Nóng quá hạ 2°C', 'Nóng quá hạ 2 độ'),
                        _chip('🔥 Bật sưởi 28°C', 'Bật sưởi 28 độ quạt mạnh'),
                        _chip('🌙 Chế độ ngủ', 'Bật chế độ ngủ'),
                        _chip('🌀 Đảo gió', 'Bật đảo gió'),
                        _chip('📺 Bật TV', 'Bật TV'),
                        _chip('🔊 Tăng âm lượng TV', 'Tăng âm lượng TV'),
                        _chip('🌤️ Thời tiết?', 'Thời tiết hôm nay thế nào'),
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

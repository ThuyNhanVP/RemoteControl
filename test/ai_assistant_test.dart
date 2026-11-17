import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:test2/ai_assistant.dart';
import 'package:test2/protocols.dart';

void main() {
  group('AiAssistantEngine Natural Language Tests', () {
    test('Bật 24 độ chế độ làm lạnh', () async {
      final res = await AiAssistantEngine.processQuery(
        'Bật 24 độ chế độ làm lạnh',
        currentPower: false,
        currentTemp: 26,
        currentMode: AcMode.auto,
        currentFan: AcFan.auto,
        currentFeat: {Feat.swing: false, Feat.sleep: false, Feat.turbo: false, Feat.light: true},
        availableDevices: ['Điều hòa 1', 'LG'],
      );

      expect(res.power, isTrue);
      expect(res.temp, equals(24));
      expect(res.mode, equals(AcMode.cool));
      expect(res.actionTaken, isTrue);
    });

    test('Tắt điều hòa đi', () async {
      final res = await AiAssistantEngine.processQuery(
        'Tắt điều hòa đi',
        currentPower: true,
        currentTemp: 24,
        currentMode: AcMode.cool,
        currentFan: AcFan.auto,
        currentFeat: {Feat.swing: false, Feat.sleep: false, Feat.turbo: false, Feat.light: true},
        availableDevices: ['Điều hòa 1'],
      );

      expect(res.power, isFalse);
      expect(res.actionTaken, isTrue);
    });

    test('Nóng quá', () async {
      final res = await AiAssistantEngine.processQuery(
        'Nóng quá',
        currentPower: true,
        currentTemp: 26,
        currentMode: AcMode.cool,
        currentFan: AcFan.auto,
        currentFeat: {Feat.swing: false, Feat.sleep: false, Feat.turbo: false, Feat.light: true},
        availableDevices: ['Điều hòa 1'],
      );

      expect(res.power, isTrue);
      expect(res.temp, equals(24)); // 26 - 2 = 24
      expect(res.mode, equals(AcMode.cool));
      expect(res.actionTaken, isTrue);
    });

    test('Bật sưởi 28 độ quạt mạnh', () async {
      final res = await AiAssistantEngine.processQuery(
        'Bật sưởi 28 độ quạt mạnh',
        currentPower: false,
        currentTemp: 25,
        currentMode: AcMode.cool,
        currentFan: AcFan.low,
        currentFeat: {Feat.swing: false, Feat.sleep: false, Feat.turbo: false, Feat.light: true},
        availableDevices: ['Điều hòa 1'],
      );

      expect(res.power, isTrue);
      expect(res.temp, equals(28));
      expect(res.mode, equals(AcMode.heat));
      expect(res.fan, equals(AcFan.high));
      expect(res.actionTaken, isTrue);
    });

    test('Bật đảo gió và chế độ ngủ', () async {
      final res = await AiAssistantEngine.processQuery(
        'Bật đảo gió và chế độ ngủ',
        currentPower: true,
        currentTemp: 25,
        currentMode: AcMode.cool,
        currentFan: AcFan.auto,
        currentFeat: {Feat.swing: false, Feat.sleep: false, Feat.turbo: false, Feat.light: true},
        availableDevices: ['Điều hòa 1'],
      );

      expect(res.featChanges[Feat.swing], isTrue);
      expect(res.featChanges[Feat.sleep], isTrue);
      expect(res.actionTaken, isTrue);
    });

    test('Chuyển sang LG', () async {
      final res = await AiAssistantEngine.processQuery(
        'Chuyển sang máy LG',
        currentPower: true,
        currentTemp: 25,
        currentMode: AcMode.cool,
        currentFan: AcFan.auto,
        currentFeat: {Feat.swing: false, Feat.sleep: false, Feat.turbo: false, Feat.light: true},
        availableDevices: ['Điều hòa 1', 'LG'],
      );

      expect(res.targetDeviceName, equals('LG'));
      expect(res.actionTaken, isTrue);
    });

    test('Hỏi thời tiết', () async {
      final res = await AiAssistantEngine.processQuery(
        'Thời tiết hôm nay thế nào',
        currentPower: true,
        currentTemp: 25,
        currentMode: AcMode.cool,
        currentFan: AcFan.auto,
        currentFeat: {Feat.swing: false, Feat.sleep: false, Feat.turbo: false, Feat.light: true},
        availableDevices: ['Điều hòa 1'],
        weatherSummary: 'Hà Nội hiện tại: 22°C, Có mây.',
      );

      expect(res.isWeatherQuery, isTrue);
      expect(res.response, contains('Hà Nội hiện tại: 22°C'));
    });

    test('Kiểm tra OpenRouter API thành công với openrouter/auto', () async {
      final isValid = await AiAssistantEngine.testOpenRouterApiKey(
        defaultOpenRouterApiKey,
        model: 'openrouter/auto',
      );
      expect(isValid, isTrue);
    });
  });
}

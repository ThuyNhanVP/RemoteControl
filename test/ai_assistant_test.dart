import 'package:flutter_test/flutter_test.dart';
import 'package:test2/ai_assistant.dart';
import 'package:test2/protocols.dart';
import 'package:test2/secrets.dart';
import 'package:test2/tv.dart';

void main() {
  group('AiAssistantEngine Natural Language Tests (Điều hòa)', () {
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

    // Gọi mạng thật bằng khóa thật: bỏ qua khi không có khóa (ví dụ trên CI)
    test('Kiểm tra OpenRouter API thành công với openrouter/auto', () async {
      final isValid = await AiAssistantEngine.testOpenRouterApiKey(
        defaultOpenRouterApiKey,
        model: 'openrouter/auto',
      );
      expect(isValid, isTrue);
    }, skip: defaultOpenRouterApiKey.isEmpty ? 'Cần khóa OpenRouter thật và mạng' : false);
  });

  group('AiAssistantEngine Natural Language Tests (TV & Toàn bộ thiết bị)', () {
    final mockDevices = [
      {'id': 1, 'name': 'Điều hòa Phòng Khách', 'kind': 'ac', 'proto': 'gree'},
      {'id': 2, 'name': 'TV LG', 'kind': 'tv', 'proto': 'lg'},
      {'id': 3, 'name': 'TV Toshiba', 'kind': 'tv', 'proto': 'toshiba'},
    ];

    test('Bật TV', () async {
      final res = await AiAssistantEngine.processQuery(
        'Bật TV lên',
        deviceList: mockDevices,
      );

      expect(res.tvKey, equals(TvKey.power));
      expect(res.targetDeviceKind, equals('tv'));
      expect(res.actionTaken, isTrue);
    });

    test('Tắt tivi', () async {
      final res = await AiAssistantEngine.processQuery(
        'Tắt tivi đi',
        deviceList: mockDevices,
      );

      expect(res.tvKey, equals(TvKey.power));
      expect(res.targetDeviceKind, equals('tv'));
      expect(res.actionTaken, isTrue);
    });

    test('Tăng âm lượng TV (1 nấc mặc định)', () async {
      final res = await AiAssistantEngine.processQuery(
        'Tăng âm lượng TV',
        deviceList: mockDevices,
      );

      expect(res.tvKey, equals(TvKey.volUp));
      expect(res.tvRepeat, equals(1));
      expect(res.actionTaken, isTrue);
    });

    test('Tăng 3 nấc âm lượng', () async {
      final res = await AiAssistantEngine.processQuery(
        'Tăng 3 nấc âm lượng',
        currentDeviceKind: 'tv',
        deviceList: mockDevices,
      );

      expect(res.tvKey, equals(TvKey.volUp));
      expect(res.tvRepeat, equals(3));
      expect(res.actionTaken, isTrue);
    });

    test('Giảm âm lượng TV / Nhỏ tiếng lại', () async {
      final res = await AiAssistantEngine.processQuery(
        'Cho nhỏ tiếng TV lại 2 nấc',
        deviceList: mockDevices,
      );

      expect(res.tvKey, equals(TvKey.volDown));
      expect(res.tvRepeat, equals(2));
      expect(res.actionTaken, isTrue);
    });

    test('Tắt tiếng TV (Mute)', () async {
      final res = await AiAssistantEngine.processQuery(
        'Tắt tiếng TV',
        deviceList: mockDevices,
      );

      expect(res.tvKey, equals(TvKey.mute));
      expect(res.actionTaken, isTrue);
    });

    test('Chuyển kênh tiếp theo', () async {
      final res = await AiAssistantEngine.processQuery(
        'Chuyển kênh tiếp theo',
        deviceList: mockDevices,
      );

      expect(res.tvKey, equals(TvKey.chUp));
      expect(res.actionTaken, isTrue);
    });

    test('Về kênh trước', () async {
      final res = await AiAssistantEngine.processQuery(
        'Về kênh trước trên TV',
        deviceList: mockDevices,
      );

      expect(res.tvKey, equals(TvKey.chDown));
      expect(res.actionTaken, isTrue);
    });

    test('Chuyển cổng nguồn vào TV (Input)', () async {
      final res = await AiAssistantEngine.processQuery(
        'Chuyển nguồn vào TV',
        deviceList: mockDevices,
      );

      expect(res.tvKey, equals(TvKey.input));
      expect(res.actionTaken, isTrue);
    });

    test('Mở Menu TV', () async {
      final res = await AiAssistantEngine.processQuery(
        'Mở menu TV',
        deviceList: mockDevices,
      );

      expect(res.tvKey, equals(TvKey.menu));
      expect(res.actionTaken, isTrue);
    });

    test('Điều hướng: Bấm OK', () async {
      final res = await AiAssistantEngine.processQuery(
        'Bấm OK',
        currentDeviceKind: 'tv',
        deviceList: mockDevices,
      );

      expect(res.tvKey, equals(TvKey.ok));
      expect(res.actionTaken, isTrue);
    });

    test('Chuyển sang TV Toshiba cụ thể', () async {
      final res = await AiAssistantEngine.processQuery(
        'Tăng âm lượng TV Toshiba',
        deviceList: mockDevices,
      );

      expect(res.targetDeviceName, equals('TV Toshiba'));
      expect(res.targetDeviceKind, equals('tv'));
      expect(res.tvKey, equals(TvKey.volUp));
      expect(res.actionTaken, isTrue);
    });
  });
}

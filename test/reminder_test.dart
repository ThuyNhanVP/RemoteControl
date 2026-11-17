// Chạy: flutter test
import 'package:flutter_test/flutter_test.dart';
import 'package:test2/reminder.dart';

Map<String, dynamic> fc(List<num> feels) => {
      'hourly': {
        'time': ['2026-11-15T05:00', '2026-11-15T06:00', '2026-11-15T07:00'],
        'apparent_temperature': feels,
      }
    };

void main() {
  final alarm = DateTime(2026, 11, 15, 6, 10).millisecondsSinceEpoch;
  final now = DateTime(2026, 11, 14, 22).millisecondsSinceEpoch;

  test('lạnh: nhắc trước báo thức 20 phút, Sưởi 26°C khi <= 17°C', () {
    final p = planReminder(fc([20, 16.5, 18]), alarm, now)!;
    expect(p.at, alarm - 20 * 60000);
    expect(p.temp, 26);
    expect(p.hhmm, '06:10');
  });

  test('báo thức 6:40 lấy dự báo giờ 7:00', () {
    final a = DateTime(2026, 11, 15, 6, 40).millisecondsSinceEpoch;
    expect(planReminder(fc([25, 25, 19]), a, now)!.temp, 24);
  });

  test('không nhắc khi trời không lạnh, thiếu dự báo hoặc đã quá giờ nhắc', () {
    expect(planReminder(fc([25, 24, 23]), alarm, now), isNull);
    expect(planReminder({}, alarm, now), isNull);
    expect(planReminder(fc([15, 15, 15]), alarm, alarm - 10 * 60000), isNull);
    final a = DateTime(2026, 11, 16, 6).millisecondsSinceEpoch; // ngày không có trong dự báo
    expect(planReminder(fc([15, 15, 15]), a, now), isNull);
  });

  test('heatTempFor', () {
    expect(heatTempFor(17), 26);
    expect(heatTempFor(21), 24);
    expect(heatTempFor(21.1), isNull);
  });
}

// Chạy: flutter test
// Các giá trị mong đợi lấy từ bộ test của thư viện IRremoteESP8266 (đã đối chiếu).
// Nếu tên gói trong pubspec.yaml (dòng "name:") không phải test2 thì đổi dòng import dưới đây.
import 'package:flutter_test/flutter_test.dart';
import 'package:test2/protocols.dart';

int sum(List<int> b, int from, int to) =>
    b.sublist(from, to).fold<int>(0, (a, v) => a + v) & 0xFF;

void main() {
  test('Midea: 17°C và 30°C, Lạnh, quạt nhẹ', () {
    expect(mideaState(on: true, mode: AcMode.cool, temp: 17, fan: AcFan.low),
        [0xA1, 0x88, 0x40, 0xFF, 0xFF, 0x56]);
    expect(mideaState(on: true, mode: AcMode.cool, temp: 30, fan: AcFan.low),
        [0xA1, 0x88, 0x4D, 0xFF, 0xFF, 0x5D]);
  });

  test('TCL: 16°C và 31°C, Lạnh, quạt tự động', () {
    expect(tclState(on: true, mode: AcMode.cool, temp: 16, fan: AcFan.auto),
        [0x23, 0xCB, 0x26, 0x01, 0x00, 0x24, 0x03, 0x0F, 0, 0, 0, 0, 0x80, 0xCB]);
    expect(tclState(on: true, mode: AcMode.cool, temp: 31, fan: AcFan.auto),
        [0x23, 0xCB, 0x26, 0x01, 0x00, 0x24, 0x03, 0x00, 0, 0, 0, 0, 0x80, 0xBC]);
  });

  test('Samsung: 24°C Lạnh tự động, tắt đảo gió và bật đảo gió', () {
    expect(samsungState(on: true, mode: AcMode.cool, temp: 24, fan: AcFan.auto),
        [0x02, 0x92, 0x0F, 0, 0, 0, 0xF0, 0x01, 0xE2, 0xFE, 0x71, 0x80, 0x11, 0xF0]);
    expect(
        samsungState(on: true, mode: AcMode.cool, temp: 24, fan: AcFan.auto, swing: true),
        [0x02, 0x92, 0x0F, 0, 0, 0, 0xF0, 0x01, 0x02, 0xAF, 0x71, 0x80, 0x11, 0xF0]);
  });

  test('Daikin: tiêu đề, tổng kiểm các khối, nhiệt độ', () {
    final b = daikinState(on: false, mode: AcMode.heat, temp: 21, fan: AcFan.auto);
    expect(b.length, 35);
    expect(b.sublist(0, 5), [0x11, 0xDA, 0x27, 0x00, 0xC5]);
    expect(b[7], 0xD7);
    expect(b[15], 0x54);
    expect(b[21], 0x48); // tắt, Sưởi
    expect(b[22], 0x2A); // 21°C x 2
    expect(b[34], sum(b, 16, 34));
  });

  test('Panasonic: tổng kiểm và độ dài chuỗi xung', () {
    final b = panasonicState(on: true, mode: AcMode.cool, temp: 25, fan: AcFan.auto);
    expect(b.length, 27);
    expect(b[26], (0xF4 + sum(b, 0, 26)) & 0xFF);
    expect(panasonicPattern(b).length, 439);
  });

  test('LG: lệnh tắt là 0x88C0051', () {
    expect(lgFrame(on: false, mode: AcMode.cool, temp: 24, fan: AcFan.auto), 0x88C0051);
  });

  test('Coolix: lệnh tắt là 0xB27BE0', () {
    expect(coolixFrame(on: false, mode: AcMode.cool, temp: 24, fan: AcFan.auto), coolixOff);
  });

  test('Gree: khung 8 byte và 139 giá trị xung', () {
    final b = greeState(
        on: true, mode: AcMode.cool, temp: 25, fan: AcFan.auto, swing: false, modelA: true);
    expect(b.length, 8);
    expect(greePattern(b).length, 139);
  });
}

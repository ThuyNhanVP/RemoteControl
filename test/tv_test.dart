// Chạy: flutter test
import 'package:flutter_test/flutter_test.dart';
import 'package:test2/tv.dart';

/// Giải mã ngược chuỗi xung NEC thành 4 byte (bit thấp trước).
List<int> decode(List<int> p) => [
  for (var b = 0; b < 4; b++)
    [for (var i = 0; i < 8; i++) p[3 + 2 * (b * 8 + i)] > 1000 ? 1 << i : 0]
        .fold(0, (a, c) => a | c),
];

void main() {
  test('NEC: LG nguồn = 04 FB 08 F7 (tức 0x20DF10EF kiểu IRremote)', () {
    final p = tvPattern(TvBrand.lg, TvKey.power);
    expect(p.length, 67);
    expect(p.sublist(0, 2), [9000, 4500]);
    expect(decode(p), [0x04, 0xFB, 0x08, 0xF7]);
  });

  test('NEC: Toshiba tăng âm = địa chỉ 64, lệnh 26', () {
    expect(decode(tvPattern(TvBrand.toshiba, TvKey.volUp)), [64, ~64 & 0xFF, 26, ~26 & 0xFF]);
  });

  test('mọi hãng đều có mã cho mọi phím', () {
    for (final b in TvBrand.values) {
      for (final k in TvKey.values) {
        expect(() => tvPattern(b, k), returnsNormally, reason: '$b $k');
      }
    }
  });

  test('tvBrandOf: nhận tên hãng, lạ thì về LG', () {
    expect(tvBrandOf('toshiba'), TvBrand.toshiba);
    expect(tvBrandOf('gree'), TvBrand.lg);
  });
}
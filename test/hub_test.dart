// Chạy: flutter test
import 'package:flutter_test/flutter_test.dart';
import 'package:test2/hub.dart';

void main() {
  test('defaultSpot: nằm trong màn hình, các thiết bị không trùng nhau', () {
    for (final n in [1, 2, 3, 5, 8]) {
      final pts = [for (var i = 0; i < n; i++) defaultSpot(i, n)];
      for (final p in pts) {
        expect(p.dx, inInclusiveRange(0.1, 0.9));
        expect(p.dy, inInclusiveRange(0.1, 0.9));
      }
      expect(pts.toSet().length, n);
    }
  });

  test('defaultSpot: thiết bị đầu tiên nằm ngay phía dưới nút trung tâm', () {
    final p = defaultSpot(0, 4);
    expect(p.dx, closeTo(0.5, 1e-9));
    expect(p.dy, greaterThan(0.4));
  });

  test('kindIcon: tv khác điều hòa', () {
    expect(kindIcon('tv'), isNot(kindIcon('ac')));
    expect(kindIcon(null), kindIcon('ac'));
  });

  test('wavePush: mạnh khi vòng sóng đi qua, gần 0 khi ở xa', () {
    // t = 0: vòng 0 có bán kính 44, vòng 1 ở 44+150*(2/3)... tìm cự ly có sóng và cự ly không
    final near = wavePush(0, 56);
    final far = wavePush(0, 1000);
    expect(near, greaterThan(0.3));
    expect(far, lessThan(1e-6));
  });

  test('heartBeat: có nhịp mạnh rồi nghỉ, nằm trong 0 đến 1,6', () {
    expect(heartBeat(0.04 / 3), greaterThan(0.9));
    expect(heartBeat(0.2 / 3), greaterThan(0.5));
    expect(heartBeat(0.2), lessThan(0.05)); // giữa hai chu kỳ là lúc nghỉ
  });
}
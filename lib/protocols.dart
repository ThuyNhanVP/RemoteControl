// Các giao thức IR điều hòa: hàm thuần (chỉ số và byte), không phụ thuộc Flutter.
// Tách riêng để kiểm tra bằng test/protocols_test.dart.

// ====== Kiểu dữ liệu dùng chung ======
enum AcMode { cool, dry, fan, auto, heat }

enum AcFan { low, medium, high, auto }

/// Các tính năng bật/tắt thêm (không phải chế độ, quạt, nhiệt độ).
enum Feat { swing, sleep, turbo, light }

/// Các giao thức điều hòa app hỗ trợ.
/// Casper: thử lần lượt gree, greeB, coolix.
/// Chỉ được THÊM vào cuối (tên đã lưu trong SQLite theo tên enum).
enum Proto { gree, greeB, coolix, lg1, lg2, midea, tcl, samsung, daikin, panasonic }

int clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

String hexInt(int f) => '0x${f.toRadixString(16).toUpperCase()}';

/// Lệnh sẵn sàng phát: dãy xung (micro giây) + mô tả để hiện lên màn hình.
class IrCmd {
  final List<int> pattern;
  final String desc;
  final int freq; // tần số sóng mang (Hz)
  const IrCmd(this.pattern, this.desc, {this.freq = 38000});
}

String hexBytes(List<int> b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');

int _rev8(int v) {
  var r = 0;
  for (var i = 0; i < 8; i++) {
    r = (r << 1) | ((v >> i) & 1);
  }
  return r;
}

int _popCount(int v) {
  var c = 0;
  for (var x = v; x != 0; x >>= 1) {
    c += x & 1;
  }
  return c;
}

int _sumBytes(List<int> b, int from, int to) {
  var s = 0;
  for (var i = from; i < to; i++) {
    s += b[i];
  }
  return s & 0xFF;
}

/// Phát một dãy byte theo kiểu chung: tiêu đề, các bit (bit thấp trước), dấu kết.
void _addBytesLsb(List<int> p, List<int> bytes, int mark, int one, int zero) {
  for (final v in bytes) {
    for (var i = 0; i < 8; i++) {
      p.add(mark);
      p.add(((v >> i) & 1) == 1 ? one : zero);
    }
  }
}

// ====== GREE (dùng cho nhiều hãng, thử cho Casper) ======
// Khung 8 byte, gửi theo 2 khối 4 byte, mỗi byte gửi bit thấp trước.
const _greeMode = {
  AcMode.auto: 0,
  AcMode.cool: 1,
  AcMode.dry: 2,
  AcMode.fan: 3,
  AcMode.heat: 4,
};
const _greeFan = {AcFan.auto: 0, AcFan.low: 1, AcFan.medium: 2, AcFan.high: 3};

List<int> greeState({
  required bool on,
  required AcMode mode,
  required int temp,
  required AcFan fan,
  required bool swing,
  required bool modelA, // true: kiểu YAW1F (Gree A), false: YBOFB (Gree B)
  bool sleep = false,
  bool turbo = false,
  bool light = true,
}) {
  var t = temp;
  var f = _greeFan[fan]!;
  if (mode == AcMode.auto) t = 25; // chế độ Auto khóa 25°C
  if (mode == AcMode.dry) f = 1; // chế độ Khô khóa quạt nhẹ
  final b = List<int>.filled(8, 0);
  b[0] = _greeMode[mode]! |
      ((on ? 1 : 0) << 3) |
      (f << 4) |
      ((swing ? 1 : 0) << 6) |
      ((sleep ? 1 : 0) << 7);
  b[1] = clampInt(t, 16, 30) - 16;
  b[2] = (turbo ? 0x10 : 0) | (light ? 0x20 : 0) | ((modelA && on) ? 0x40 : 0);
  b[3] = 0x50;
  b[4] = swing ? 1 : 0; // đảo gió dọc tự động
  b[5] = 0x20;
  b[6] = 0;
  var s = 10;
  for (var i = 0; i < 4; i++) {
    s += b[i] & 0xF;
  }
  for (var i = 4; i < 7; i++) {
    s += b[i] >> 4;
  }
  b[7] = (s & 0xF) << 4;
  return b;
}

List<int> greePattern(List<int> b) {
  const mark = 620, one = 1600, zero = 540, gap = 19980;
  final p = <int>[9000, 4500];
  _addBytesLsb(p, b.sublist(0, 4), mark, one, zero);
  // 3 bit đệm giữa hai khối: 0, 1, 0
  for (final bit in const [0, 1, 0]) {
    p.add(mark);
    p.add(bit == 1 ? one : zero);
  }
  p.add(mark);
  p.add(gap);
  _addBytesLsb(p, b.sublist(4, 8), mark, one, zero);
  p.add(mark);
  return p;
}

// ====== COOLIX (cũng là kiểu rất phổ biến ở máy giá rẻ) ======
// Khung 24 bit, mỗi byte gửi kèm byte đảo, bit cao trước, gửi 2 lần.
const _coolixTemp = [0, 1, 3, 2, 6, 7, 5, 4, 12, 13, 9, 8, 10, 11]; // 17..30°C
const _coolixMode = {
  AcMode.cool: 0,
  AcMode.dry: 1,
  AcMode.auto: 2,
  AcMode.heat: 3,
  AcMode.fan: 1, // chế độ Quạt = Khô + mã nhiệt độ đặc biệt 0xE
};
const _coolixFan = {AcFan.auto: 5, AcFan.low: 4, AcFan.medium: 2, AcFan.high: 1};
const coolixOff = 0xB27BE0;

/// Với Coolix, các tính năng này là lệnh riêng (bấm một lần đổi trạng thái).
const coolixFeat = {
  Feat.swing: 0xB26BE0,
  Feat.sleep: 0xB2E003,
  Feat.turbo: 0xB5F5A2,
  Feat.light: 0xB5F5A5,
};

int coolixFrame({
  required bool on,
  required AcMode mode,
  required int temp,
  required AcFan fan,
}) {
  if (!on) return coolixOff;
  final tc = mode == AcMode.fan ? 0xE : _coolixTemp[clampInt(temp, 17, 30) - 17];
  var f = _coolixFan[fan]!;
  if (mode == AcMode.dry || mode == AcMode.auto) f = 0; // 2 chế độ này không chọn quạt
  return (0xB2 << 16) | ((0x1F | (f << 5)) << 8) | (tc << 4) | (_coolixMode[mode]! << 2);
}

List<int> coolixPattern(int frame) {
  const mark = 552, one = 1656, zero = 552, gap = 5244;
  final bytes = [(frame >> 16) & 0xFF, (frame >> 8) & 0xFF, frame & 0xFF];
  final p = <int>[];
  for (var rep = 0; rep < 2; rep++) {
    p.add(4692);
    p.add(4416);
    for (final v in bytes) {
      for (final x in [v, v ^ 0xFF]) {
        for (var i = 7; i >= 0; i--) {
          p.add(mark);
          p.add(((x >> i) & 1) == 1 ? one : zero);
        }
      }
    }
    p.add(mark);
    if (rep == 0) p.add(gap);
  }
  return p;
}

// ====== LG (giao thức 28 bit) ======
const _lgMode = {
  AcMode.cool: 0,
  AcMode.dry: 1,
  AcMode.fan: 2,
  AcMode.auto: 3,
  AcMode.heat: 0, // LG đời cũ không có sưởi, quy về Lạnh
};
const _lgFan = {AcFan.low: 0, AcFan.medium: 2, AcFan.high: 4, AcFan.auto: 5};

int lgFrame({
  required bool on,
  required AcMode mode,
  required int temp,
  required AcFan fan,
}) {
  int data;
  if (!on) {
    data = (3 << 14) | 5; // lệnh tắt => 0x88C0051
  } else {
    final t = (clampInt(temp, 16, 30) - 15) & 0xF;
    data = (_lgMode[mode]! << 8) | (t << 4) | _lgFan[fan]!;
  }
  final chk = ((data >> 12) & 0xF) +
      ((data >> 8) & 0xF) +
      ((data >> 4) & 0xF) +
      (data & 0xF);
  return (0x88 << 20) | (data << 4) | (chk & 0xF);
}

List<int> lgPattern(int frame, {required bool lg2}) {
  final hdrMark = lg2 ? 3200 : 8500;
  final hdrSpace = lg2 ? 9900 : 4250;
  final bitMark = lg2 ? 480 : 550;
  const one = 1600, zero = 550;
  final p = <int>[hdrMark, hdrSpace];
  for (var i = 27; i >= 0; i--) {
    p.add(bitMark);
    p.add(((frame >> i) & 1) == 1 ? one : zero);
  }
  p.add(bitMark);
  return p;
}

// ====== MIDEA (Midea, Carrier, Comfee, Pioneer, Kaysun...) ======
// 6 byte: A1, chế độ/quạt/nguồn, nhiệt độ, FF, FF, checksum.
// Gửi bit CAO trước; sau đó gửi lại toàn bộ khung với mọi bit đảo.
const _mideaMode = {
  AcMode.cool: 0,
  AcMode.dry: 1,
  AcMode.auto: 2,
  AcMode.heat: 3,
  AcMode.fan: 4,
};
const _mideaFan = {AcFan.auto: 0, AcFan.low: 1, AcFan.medium: 2, AcFan.high: 3};

List<int> mideaState({
  required bool on,
  required AcMode mode,
  required int temp,
  required AcFan fan,
  bool sleep = false,
}) {
  final b4 = _mideaMode[mode]! |
      (_mideaFan[fan]! << 3) |
      ((sleep ? 1 : 0) << 6) |
      ((on ? 1 : 0) << 7);
  final b3 = 0x40 | (clampInt(temp, 17, 30) - 17);
  final sum = _rev8(0xA1) + _rev8(b4) + _rev8(b3) + 0xFF + 0xFF;
  final chk = _rev8((256 - sum) & 0xFF);
  return [0xA1, b4, b3, 0xFF, 0xFF, chk];
}

List<int> mideaPattern(List<int> bytes) {
  final p = <int>[];
  for (var rep = 0; rep < 2; rep++) {
    p.add(4480);
    p.add(4480);
    for (final b in bytes) {
      final v = rep == 0 ? b : (b ^ 0xFF);
      for (var i = 7; i >= 0; i--) {
        p.add(560);
        p.add(((v >> i) & 1) == 1 ? 1680 : 560);
      }
    }
    p.add(560);
    if (rep == 0) p.add(5600);
  }
  return p;
}

// ====== TCL (TCL, Hisense, Leberg...: giao thức TCL112AC) ======
const _tclMode = {
  AcMode.heat: 1,
  AcMode.dry: 2,
  AcMode.cool: 3,
  AcMode.fan: 7,
  AcMode.auto: 8,
};
const _tclFan = {AcFan.auto: 0, AcFan.low: 2, AcFan.medium: 3, AcFan.high: 5};

List<int> tclState({
  required bool on,
  required AcMode mode,
  required int temp,
  required AcFan fan,
  bool swing = false,
  bool turbo = false,
  bool light = true,
}) {
  final b = <int>[0x23, 0xCB, 0x26, 0x01, 0x00, 0, 0, 0, 0, 0, 0, 0, 0x80, 0];
  b[5] = 0x20 | (on ? 0x04 : 0) | (light ? 0 : 0x40);
  b[6] = _tclMode[mode]! | (turbo ? 0x20 : 0);
  b[7] = 31 - clampInt(temp, 16, 31);
  var f = _tclFan[fan]!;
  var sv = swing ? 7 : 0;
  if (turbo) {
    f = 5;
    sv = 7;
  }
  b[8] = f | (sv << 3);
  b[13] = _sumBytes(b, 0, 13);
  return b;
}

List<int> tclPattern(List<int> b) {
  final p = <int>[3000, 1650];
  _addBytesLsb(p, b, 500, 1050, 325);
  p.add(500);
  return p;
}

// ====== SAMSUNG (điều hòa Samsung) ======
// 14 byte chia 2 khối 7 byte. Đổi trạng thái nguồn phải gửi khung "mở rộng" 21 byte.
const _samMode = {
  AcMode.auto: 0,
  AcMode.cool: 1,
  AcMode.dry: 2,
  AcMode.fan: 3,
  AcMode.heat: 4,
};
const _samFan = {AcFan.auto: 0, AcFan.low: 2, AcFan.medium: 4, AcFan.high: 5};

int _samSectionSum(List<int> b, int o) {
  final s = _popCount(b[o]) +
      _popCount(b[o + 1] & 0x0F) +
      _popCount(b[o + 2] >> 4) +
      _popCount(b[o + 3]) +
      _popCount(b[o + 4]) +
      _popCount(b[o + 5]) +
      _popCount(b[o + 6]);
  return (s ^ 0xFF) & 0xFF;
}

List<int> _samFix(List<int> b) {
  for (var o = 0; o + 7 <= b.length; o += 7) {
    final c = _samSectionSum(b, o);
    b[o + 1] = (b[o + 1] & 0x0F) | ((c & 0xF) << 4);
    b[o + 2] = (b[o + 2] & 0xF0) | (c >> 4);
  }
  return b;
}

List<int> samsungState({
  required bool on,
  required AcMode mode,
  required int temp,
  required AcFan fan,
  bool swing = false,
}) {
  final b = <int>[
    0x02, 0x02, 0x0F, 0x00, 0x00, 0x00, 0xF0, //
    0x01, 0x02, 0xAE, 0x71, 0x00, 0x15, 0xF0,
  ];
  b[6] = on ? 0xF0 : 0xC0;
  b[13] = on ? 0xF0 : 0xC0;
  b[11] = (b[11] & 0x0F) | ((clampInt(temp, 16, 30) - 16) << 4);
  final f = mode == AcMode.auto ? 6 : _samFan[fan]!; // 6 = quạt tự động riêng của chế độ Auto
  b[12] = (b[12] & 0x81) | (f << 1) | (_samMode[mode]! << 4);
  b[9] = (b[9] & 0x8F) | ((swing ? 2 : 7) << 4);
  return _samFix(b);
}

List<int> samsungExtended(List<int> b14) => [
      ...b14.sublist(0, 7),
      0x01, 0xD2, 0x0F, 0x00, 0x00, 0x00, 0x00, //
      ...b14.sublist(7, 14),
    ];

/// Khung TẮT nguyên bản của thư viện (khung mở rộng 21 byte).
const samsungOff = <int>[
  0x02, 0xB2, 0x0F, 0x00, 0x00, 0x00, 0xC0, //
  0x01, 0xD2, 0x0F, 0x00, 0x00, 0x00, 0x00,
  0x01, 0x02, 0xFF, 0x71, 0x80, 0x11, 0xC0,
];

List<int> samsungPattern(List<int> b) {
  final p = <int>[690, 17844];
  final n = b.length ~/ 7;
  for (var s = 0; s < n; s++) {
    p.add(3086);
    p.add(8864);
    _addBytesLsb(p, b.sublist(s * 7, s * 7 + 7), 586, 1432, 436);
    p.add(586);
    if (s < n - 1) p.add(2886);
  }
  return p;
}

// ====== DAIKIN (35 byte, 3 khối) ======
const _dkMode = {
  AcMode.auto: 0,
  AcMode.dry: 2,
  AcMode.cool: 3,
  AcMode.heat: 4,
  AcMode.fan: 6,
};
const _dkFan = {AcFan.low: 3, AcFan.medium: 5, AcFan.high: 7, AcFan.auto: 0xA};

List<int> daikinState({
  required bool on,
  required AcMode mode,
  required int temp,
  required AcFan fan,
  bool swing = false,
  bool powerful = false,
}) {
  final b = List<int>.filled(35, 0);
  b.setRange(0, 5, [0x11, 0xDA, 0x27, 0x00, 0xC5]);
  b.setRange(8, 13, [0x11, 0xDA, 0x27, 0x00, 0x42]);
  b.setRange(16, 19, [0x11, 0xDA, 0x27]);
  b[21] = (on ? 1 : 0) | 0x08 | (_dkMode[mode]! << 4);
  b[22] = clampInt(temp, 10, 32) * 2;
  b[24] = (_dkFan[fan]! << 4) | (swing ? 0xF : 0);
  b[27] = 0x06;
  b[28] = 0x60;
  b[29] = powerful ? 1 : 0;
  b[31] = 0xC0;
  b[7] = _sumBytes(b, 0, 7);
  b[15] = _sumBytes(b, 8, 15);
  b[34] = _sumBytes(b, 16, 34);
  return b;
}

List<int> daikinPattern(List<int> b) {
  const mark = 428, one = 1280, zero = 428, gap = 29000;
  final p = <int>[];
  for (var i = 0; i < 5; i++) {
    p.add(mark);
    p.add(zero);
  }
  p.add(mark);
  p.add(zero + gap);
  const parts = [
    [0, 8],
    [8, 16],
    [16, 35],
  ];
  for (var k = 0; k < parts.length; k++) {
    p.add(3650);
    p.add(1623);
    _addBytesLsb(p, b.sublist(parts[k][0], parts[k][1]), mark, one, zero);
    p.add(mark);
    if (k < parts.length - 1) p.add(zero + gap);
  }
  return p;
}

// ====== PANASONIC (27 byte, sóng mang 36,7 kHz) ======
const _paMode = {
  AcMode.auto: 0,
  AcMode.dry: 2,
  AcMode.cool: 3,
  AcMode.heat: 4,
  AcMode.fan: 6,
};
const _paFan = {AcFan.low: 1, AcFan.medium: 2, AcFan.high: 3, AcFan.auto: 7};

List<int> panasonicState({
  required bool on,
  required AcMode mode,
  required int temp,
  required AcFan fan,
  bool swing = false,
  bool powerful = false,
}) {
  final b = <int>[
    0x02, 0x20, 0xE0, 0x04, 0x00, 0x00, 0x00, 0x06, 0x02, //
    0x20, 0xE0, 0x04, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00,
    0x00, 0x0E, 0xE0, 0x00, 0x00, 0x81, 0x00, 0x00, 0x00,
  ];
  final t = mode == AcMode.fan ? 27 : clampInt(temp, 16, 30);
  b[13] = (_paMode[mode]! << 4) | (on ? 1 : 0);
  b[14] = t << 1;
  b[16] = ((_paFan[fan]! + 3) << 4) | (swing ? 0xF : 0x3);
  if (powerful) b[21] |= 0x20;
  b[26] = (0xF4 + _sumBytes(b, 0, 26)) & 0xFF;
  return b;
}

List<int> panasonicPattern(List<int> b) {
  final p = <int>[];
  for (var k = 0; k < 2; k++) {
    final from = k == 0 ? 0 : 8;
    final to = k == 0 ? 8 : 27;
    p.add(3456);
    p.add(1728);
    _addBytesLsb(p, b.sublist(from, to), 432, 1296, 432);
    p.add(432);
    if (k == 0) p.add(10000);
  }
  return p;
}

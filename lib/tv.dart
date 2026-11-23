import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'db.dart';
import 'main.dart' show sendIr;

enum TvBrand { lg, toshiba }

const tvBrandLabel = {TvBrand.lg: 'LG', TvBrand.toshiba: 'Toshiba'};

enum TvKey { power, mute, volUp, volDown, chUp, chDown, input, up, down, left, right, ok, back, menu }

/// Mã NEC1 của từng hãng: địa chỉ 8 bit và lệnh 8 bit, lấy từ IRDB (probonopd/irdb).
/// Chưa thử trên TV thật: các đời TV khác nhau có thể khác mã.
class _Nec {
  final int addr;
  final Map<TvKey, int> cmd;
  const _Nec(this.addr, this.cmd);
}

const _codes = {
  TvBrand.lg: _Nec(4, {
    TvKey.power: 8, TvKey.mute: 9, TvKey.volUp: 2, TvKey.volDown: 3,
    TvKey.chUp: 0, TvKey.chDown: 1, TvKey.input: 11,
    TvKey.up: 64, TvKey.down: 65, TvKey.left: 7, TvKey.right: 6, TvKey.ok: 68,
    TvKey.back: 40, TvKey.menu: 67,
  }),
  // Remote Toshiba đời mới (CT-90326, CT-8560): mũi tên, OK, Back, Menu có phím riêng.
  // Đã thử trên TV thật: Nguồn, Tắt tiếng, Vol chạy đúng. Kênh chỉ có tác dụng khi TV đang xem truyền hình
  // (không phải HDMI hay ứng dụng). Nếu Nguồn vào không ăn, thử lệnh 20 thay cho 15.
  TvBrand.toshiba: _Nec(64, {
    TvKey.power: 18, TvKey.mute: 16, TvKey.volUp: 26, TvKey.volDown: 30,
    TvKey.chUp: 27, TvKey.chDown: 31, TvKey.input: 15,
    TvKey.up: 25, TvKey.down: 29, TvKey.left: 66, TvKey.right: 64, TvKey.ok: 33,
    TvKey.back: 100, TvKey.menu: 91,
  }),
};

/// Chuỗi xung (micro giây, bắt đầu bằng xung bật) của một khung NEC1, sóng mang 38 kHz.
/// Mỗi byte gửi bit thấp trước: địa chỉ, đảo địa chỉ, lệnh, đảo lệnh.
List<int> necPattern(int addr, int cmd) {
  final p = <int>[9000, 4500];
  for (final b in [addr, ~addr & 0xFF, cmd, ~cmd & 0xFF]) {
    for (var i = 0; i < 8; i++) {
      p.add(560);
      p.add(((b >> i) & 1) == 1 ? 1690 : 560);
    }
  }
  p.add(560);
  return p;
}

List<int> tvPattern(TvBrand brand, TvKey key) {
  final n = _codes[brand]!;
  return necPattern(n.addr, n.cmd[key]!);
}

TvBrand tvBrandOf(Object? proto) =>
    TvBrand.values.firstWhere((b) => b.name == proto, orElse: () => TvBrand.lg);

/// Màn hình điều khiển TV: các phím gửi mã NEC bằng cổng hồng ngoại của điện thoại.
class TvPage extends StatefulWidget {
  final int deviceId;
  const TvPage({super.key, required this.deviceId});

  @override
  State<TvPage> createState() => _TvPageState();
}

class _TvPageState extends State<TvPage> {
  String name = 'TV';
  TvBrand brand = TvBrand.lg;
  String status = '';
  bool muted = false; // shortcut: app đoán theo số lần bấm, không đọc được trạng thái thật của TV; lệch thì bấm thêm một lần

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await Db.devices();
    final d = list.where((e) => e['id'] == widget.deviceId);
    if (d.isEmpty || !mounted) return;
    final hasIr = await const MethodChannel('ir').invokeMethod<bool>('hasIr') ?? false;
    setState(() {
      name = d.first['name'] as String;
      brand = tvBrandOf(d.first['proto']);
      status = hasIr ? '' : 'Máy này không có cổng hồng ngoại';
    });
  }

  Future<void> _press(TvKey k) async {
    HapticFeedback.lightImpact();
    try {
      await sendIr(tvPattern(brand, k));
      Db.setMeta('last_ctrl', '${widget.deviceId}'); // hub nối đường tới thiết bị này
      if (!mounted) return;
      setState(() {
        status = '';
        if (k == TvKey.mute) {
          muted = !muted;
        } else if (k == TvKey.volUp || k == TvKey.volDown) {
          muted = false; // chỉnh âm lượng thì TV tự bỏ tắt tiếng
        }
      });
    } catch (e) {
      if (mounted) setState(() => status = 'Không gửi được: $e');
    }
  }

  static const _glass = Color(0x26FFFFFF);
  static const _glassDown = Color(0x59FFFFFF);

  Widget _btn(IconData icon, TvKey k, {double size = 64, Color? color, Color? down}) => _Tap(
    onTap: () => _press(k),
    builder: (p) => AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: p ? (down ?? _glassDown) : (color ?? _glass),
        border: Border.all(color: Colors.white12),
        boxShadow: p ? [BoxShadow(color: Colors.white.withValues(alpha: 0.25), blurRadius: 14)] : null,
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.42),
    ),
  );

  /// Vùng bấm không nền; khi nhấn hiện một vầng sáng tròn quanh biểu tượng.
  Widget _zone(IconData icon, TvKey k, {double glow = 52, double iconSize = 30}) => _Tap(
    onTap: () => _press(k),
    builder: (p) => Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        width: glow,
        height: glow,
        decoration: BoxDecoration(shape: BoxShape.circle, color: p ? _glassDown : Colors.transparent),
        child: Icon(icon, color: Colors.white, size: iconSize),
      ),
    ),
  );

  /// Thanh dạng viên thuốc có hai phím trên dưới (âm lượng, kênh).
  Widget _rocker(IconData up, TvKey ku, IconData down, TvKey kd, String label, double w, double h) => Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: _glass,
      borderRadius: BorderRadius.circular(w / 2),
      border: Border.all(color: Colors.white12),
    ),
    child: Column(
      children: [
        Expanded(child: _zone(up, ku, glow: w - 16)),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        Expanded(child: _zone(down, kd, glow: w - 16)),
      ],
    ),
  );

  /// Vòng mũi tên: bốn hướng ở rìa, OK ở giữa.
  Widget _dpad(double d) {
    final a = d * 0.3; // cạnh vùng bấm mỗi hướng
    Widget arrow(IconData i, TvKey k, Alignment al) => Align(
      alignment: al,
      child: SizedBox(width: a, height: a, child: _zone(i, k, glow: a - 6, iconSize: 30)),
    );
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(shape: BoxShape.circle, color: _glass, border: Border.all(color: Colors.white12)),
      child: Stack(
        children: [
          arrow(Icons.keyboard_arrow_up, TvKey.up, Alignment.topCenter),
          arrow(Icons.keyboard_arrow_down, TvKey.down, Alignment.bottomCenter),
          arrow(Icons.keyboard_arrow_left, TvKey.left, Alignment.centerLeft),
          arrow(Icons.keyboard_arrow_right, TvKey.right, Alignment.centerRight),
          Center(
            child: _Tap(
              onTap: () => _press(TvKey.ok),
              builder: (p) => AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                width: d * 0.36,
                height: d * 0.36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p ? const Color(0xFF3A4158) : const Color(0xFF171B26),
                ),
                child: const Center(
                  child: Text('OK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = tvBrandLabel[brand]!;
    final w = MediaQuery.sizeOf(context).width - 40; // bề rộng hàng giữa
    final rockerW = w * 0.2, dpad = w * 0.5; // phần còn lại là khe hở giữa ba khối
    final title = name.toLowerCase().contains(label.toLowerCase()) ? name : '$name · $label';
    return Scaffold(
      backgroundColor: const Color(0xFF1B2030),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF9B9BA3), Color(0xFF3A3F52), Color(0xFF1B2030), Color(0xFF29303D)],
            stops: [0, 0.3, 0.6, 1],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    Expanded(
                      child: Text(title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 16)),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _btn(Icons.input, TvKey.input),
                    _btn(Icons.power_settings_new, TvKey.power,
                        size: 72, color: const Color(0xCCC0392B), down: const Color(0xFFE5533F)),
                    _btn(muted ? Icons.volume_off : Icons.volume_up, TvKey.mute,
                        color: muted ? _glassDown : null),
                  ],
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _rocker(Icons.add, TvKey.volUp, Icons.remove, TvKey.volDown, 'VOL', rockerW, dpad),
                    _dpad(dpad),
                    _rocker(Icons.keyboard_arrow_up, TvKey.chUp, Icons.keyboard_arrow_down, TvKey.chDown, 'CH', rockerW, dpad),
                  ],
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 64),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _btn(Icons.arrow_back, TvKey.back),
                    _btn(Icons.menu, TvKey.menu),
                  ],
                ),
              ),
              const Spacer(flex: 2),
              if (status.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(status, style: const TextStyle(color: Colors.white70)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bọc một phím: thu nhỏ nhẹ và báo trạng thái đang nhấn cho [builder] để đổi màu.
class _Tap extends StatefulWidget {
  final VoidCallback onTap;
  final Widget Function(bool pressed) builder;
  const _Tap({required this.onTap, required this.builder});

  @override
  State<_Tap> createState() => _TapState();
}

class _TapState extends State<_Tap> {
  bool down = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: widget.onTap,
    onTapDown: (_) => setState(() => down = true),
    onTapUp: (_) => setState(() => down = false),
    onTapCancel: () => setState(() => down = false),
    child: AnimatedScale(
      scale: down ? 0.9 : 1,
      duration: const Duration(milliseconds: 90),
      child: widget.builder(down),
    ),
  );
}
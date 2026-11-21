import 'dart:math';

import 'package:flutter/material.dart';

import 'db.dart';
import 'firebase_sync.dart';
import 'main.dart';
import 'tv.dart';

const _copper = Color(0xFFC9803F);
const _nodeY = 0.40; // nút điện thoại nằm hơi cao hơn giữa màn hình


/// Vị trí mặc định (tỉ lệ 0 đến 1) của thiết bị thứ [i] trong [n] thiết bị: xếp quanh nút
/// trung tâm, thiết bị đầu tiên ở ngay phía dưới.
Offset defaultSpot(int i, int n) {
  final a = pi / 2 + 2 * pi * i / max(n, 1);
  return Offset(0.5 + 0.30 * cos(a), _nodeY + 0.17 * sin(a));
}

const _wave0 = 56.0; // bán kính vòng sóng lúc phát ra
const _waveSpan = 210.0; // vòng sóng nở thêm bấy nhiêu rồi tan
const _push = 10.0; // thiết bị bị sóng đẩy ra tối đa bấy nhiêu dp

/// Độ mạnh (0 đến khoảng 1) sóng đẩy lên vật cách tâm [dist] dp ở thời điểm [t] của chu kỳ (0 đến 1).
/// Ba vòng sóng lệch pha nở dần ra; vòng đi qua vật thì vật bị đẩy ra rồi trở về.
double wavePush(double t, double dist) {
  var p = 0.0;
  for (var i = 0; i < 3; i++) {
    final k = (t + i / 3) % 1;
    final x = (_wave0 + _waveSpan * k - dist) / 28;
    p += exp(-x * x) * (1 - 0.5 * k);
  }
  return p;
}

/// Nhịp tim của nút giữa (0 đến 1): hai nhịp "thịch thịch" liên tiếp rồi nghỉ, mỗi chu kỳ trùng lúc một vòng sóng phát ra.
double heartBeat(double t) {
  final u = (t * 3) % 1;
  double bump(double c) => exp(-pow((u - c) / 0.05, 2).toDouble());
  return bump(0.04) + 0.6 * bump(0.2);
}

IconData kindIcon(Object? kind) => kind == 'tv' ? Icons.tv : Icons.ac_unit;

/// Màn hình chính: các thiết bị là những hình tròn kéo thả quanh nút trung tâm.
class HubPage extends StatefulWidget {
  const HubPage({super.key});

  @override
  State<HubPage> createState() => _HubPageState();
}

class _HubPageState extends State<HubPage> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  List<Map<String, Object?>> devices = [];
  final Map<int, Offset> spots = {}; // vị trí đang hiển thị (tỉ lệ 0 đến 1)
  Set<int> on = {}; // thiết bị app nhớ là đang bật
  int? linked; // thiết bị điện thoại điều khiển lần cuối: chỉ thiết bị này có đường nối
  bool loaded = false;
  late final AnimationController _pulse =
  AnimationController(vsync: this, duration: const Duration(seconds: 9))..repeat();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Cloud.onRemoteChanged = _load;
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulse.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Cloud.syncNow(); // kéo dữ liệu mới từ máy khác (trước đây chỉ AcPage làm việc này)
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final list = await Db.devices();
      final sp = <int, Offset>{};
      final onSet = <int>{};
      final lc = int.tryParse(await Db.getMeta('last_ctrl') ?? '');
      for (var i = 0; i < list.length; i++) {
        final id = list[i]['id'] as int;
        final x = list[i]['px'], y = list[i]['py'];
        sp[id] = (x is num && y is num)
            ? Offset(x.toDouble(), y.toDouble())
            : defaultSpot(i, list.length);
        if (await Db.getMeta('powered_$id') == '1') onSet.add(id);
      }
      if (!mounted) return;
      setState(() {
        devices = list;
        spots
          ..clear()
          ..addAll(sp);
        on = onSet;
        linked = list.any((d) => d['id'] == lc) ? lc : null;
        loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => loaded = true);
    }
  }

  Future<void> _open(Map<String, Object?> d) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => d['kind'] == 'tv'
            ? TvPage(deviceId: d['id'] as int)
            : AcPage(deviceId: d['id'] as int),
      ),
    );
    Cloud.onRemoteChanged = _load; // AcPage đã gỡ khi đóng
    _load();
  }

  Future<String?> _askText(String title, String initial) async {
    final c = TextEditingController(text: initial);
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('OK')),
        ],
      ),
    );
    return (r == null || r.isEmpty) ? null : r;
  }

  Future<void> _add() async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.ac_unit),
              title: const Text('Điều hòa'),
              onTap: () => Navigator.pop(ctx, 'ac'),
            ),
            for (final b in TvBrand.values)
              ListTile(
                leading: const Icon(Icons.tv),
                title: Text('TV ${tvBrandLabel[b]}'),
                onTap: () => Navigator.pop(ctx, b.name),
              ),
          ],
        ),
      ),
    );
    if (kind == null) return;
    final isAc = kind == 'ac';
    final name = await _askText(
        'Tên thiết bị', isAc ? 'Điều hòa ${devices.length + 1}' : 'TV ${tvBrandLabel[tvBrandOf(kind)]}');
    if (name == null) return;
    await Db.addDevice(isAc ? newAcDevice(name) : newTvDevice(name, kind));
    await _load();
  }

  void _menu(Map<String, Object?> d) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Đổi tên'),
              onTap: () async {
                Navigator.pop(ctx);
                final name = await _askText('Đổi tên', d['name'] as String);
                if (name == null) return;
                await Db.updateDevice(d['id'] as int, {'name': name});
                _load();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Xóa'),
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: Text('Xóa "${d['name']}" và các cài sẵn của nó?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('Hủy')),
                      TextButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('Xóa')),
                    ],
                  ),
                );
                if (ok != true) return;
                await Db.deleteDevice(d['id'] as int);
                _load();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Vị trí đang hiển thị: vị trí gốc cộng độ đẩy của sóng theo hướng ra xa tâm.
  Offset _pos(Offset spot, double w, double h, Offset center, double t) {
    final base = Offset(spot.dx * w, spot.dy * h);
    final v = base - center;
    if (v.distance < 1) return base;
    return base + v / v.distance * (_push * wavePush(t, v.distance));
  }

  Widget _bubble(Map<String, Object?> d, double w, double h, Offset center, double t) {
    final id = d['id'] as int;
    final s = spots[id]!;
    final isOn = on.contains(id);
    final p = _pos(s, w, h, center, t);
    final push = wavePush(t, (Offset(s.dx * w, s.dy * h) - center).distance);
    return Positioned(
      left: p.dx - 48,
      top: p.dy - 32,
      width: 96,
      child: GestureDetector(
        onTap: () => _open(d),
        onLongPress: () => _menu(d),
        onPanUpdate: (u) => setState(() {
          spots[id] = Offset(
            ((s.dx * w + u.delta.dx) / w).clamp(0.12, 0.88).toDouble(),
            ((s.dy * h + u.delta.dy) / h).clamp(0.14, 0.86).toDouble(),
          );
        }),
        onPanEnd: (_) {
          final p = spots[id]!;
          Db.setPos(id, p.dx, p.dy);
        },
        child: Column(
          children: [
            Transform.scale(
              scale: 1 + 0.10 * push, // nhịp chậm, chỉ khi sóng tới nơi
              child: _Orb(
                  size: 64,
                  lit: isOn,
                  rim: id == linked ? atan2(center.dy - p.dy, center.dx - p.dx) : null,
                  child: Icon(kindIcon(d['kind']), color: Colors.white, size: 28)),
            ),
            const SizedBox(height: 6),
            Text(
              d['name'] as String,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleBtn(Widget child) => Container(
    width: 36,
    height: 36,
    decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x33FFFFFF)),
    child: child,
  );

  @override
  Widget build(BuildContext context) => Scaffold(
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
        child: LayoutBuilder(builder: (ctx, c) {
          final w = c.maxWidth, h = c.maxHeight;
          final center = Offset(w / 2, h * _nodeY);
          return AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) {
              final t = _pulse.value;
              Offset? lp; // vị trí đang hiển thị của thiết bị được nối
              for (final d in devices) {
                if (d['id'] == linked) lp = _pos(spots[linked]!, w, h, center, t);
              }
              return Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _LinkPainter(center, t, [
                        for (final d in devices)
                          if (d['id'] == linked) _pos(spots[d['id']]!, w, h, center, t),
                      ]),
                    ),
                  ),
                  Positioned(
                    left: center.dx - 48,
                    top: center.dy - 48,
                    child: Transform.scale(
                      scale: 1 + 0.09 * heartBeat(t), // nhịp tim riêng, trùng lúc sóng phát ra
                      child: _Orb(
                        size: 96,
                        lit: true,
                        rim: lp == null ? null : atan2(lp.dy - center.dy, lp.dx - center.dx),
                        child: Container(
                          width: 22,
                          height: 36,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xFFE4E6EA), Color(0xFF9EA3AB)],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  for (final d in devices) _bubble(d, w, h, center, t),
                  Positioned(
                    top: 8,
                    left: 20,
                    right: 12,
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('Smart Home',
                              style: TextStyle(color: Colors.white, fontSize: 16)),
                        ),
                        PopupMenuButton<int>(
                          tooltip: 'Thêm thiết bị',
                          onSelected: (_) => _add(),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 0, child: Text('Thêm thiết bị')),
                          ],
                          child: _circleBtn(const Icon(Icons.more_vert, color: Colors.white, size: 20)),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 46,
                    left: 20,
                    right: 20,
                    child: ValueListenableBuilder<String>(
                      valueListenable: Cloud.status,
                      builder: (_, v, __) => v.isEmpty
                          ? const SizedBox.shrink()
                          : GestureDetector(
                        onTap: Cloud.syncNow, // chạm để đồng bộ ngay
                        child: Text(v,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white54, fontSize: 11)),
                      ),
                    ),
                  ),
                  if (loaded && devices.isEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: center.dy + 110,
                      child: const Text(
                        'Chưa có thiết bị. Bấm dấu ba chấm để thêm.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                ],
              );
            },
          );
        }),
      ),
    ),
  );
}

/// Hình tròn tối có viền đồng phát sáng ở đáy (nút điện thoại và thiết bị).
class _Orb extends StatelessWidget {
  final double size;
  final bool lit;
  final double? rim; // hướng (radian) của cung đồng; null thì không có cung
  final Widget child;
  const _Orb({required this.size, required this.lit, required this.child, this.rim});

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _RimPainter(lit, rim),
    size: Size.square(size),
    child: SizedBox(width: size, height: size, child: Center(child: child)),
  );
}

class _RimPainter extends CustomPainter {
  final bool lit;
  final double? rim;
  _RimPainter(this.lit, this.rim);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero), r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF171B26));
    canvas.drawCircle(
        c, r - 0.5, Paint()..style = PaintingStyle.stroke..color = Colors.white.withValues(alpha: 0.08));
    if (rim == null) return;
    final rect = Rect.fromCircle(center: c, radius: r - 1);
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = lit ? 3 : 2
      ..color = _copper.withValues(alpha: lit ? 0.95 : 0.55)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, lit ? 2.5 : 1.5);
    canvas.drawArc(rect, rim! - pi * 0.35, pi * 0.7, false, glow); // cung đồng hướng về phía thiết bị kia
  }

  @override
  bool shouldRepaint(_RimPainter old) => old.lit != lit || old.rim != rim;
}

/// Vẽ các vòng sóng mờ quanh tâm và đường nối mảnh tới thiết bị đang được điều khiển.
class _LinkPainter extends CustomPainter {
  final Offset center;
  final double t;
  final List<Offset> points;
  _LinkPainter(this.center, this.t, this.points);

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 3; i++) {
      final k = (t + i / 3) % 1; // ba vòng lệch pha, nở dần rồi tan
      canvas.drawCircle(
        center,
        _wave0 + _waveSpan * k,
        Paint()..color = Colors.white.withValues(alpha: 0.10 * (1 - k)),
      );
    }
    final line = Paint()
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: 0.35);
    for (final p in points) {
      canvas.drawLine(center, p, line);
    }
  }

  @override
  bool shouldRepaint(_LinkPainter old) => true; // shortcut: vẽ lại mỗi khung hình, đủ nhẹ cho vài thiết bị
}
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'db.dart';
import 'firebase_sync.dart';
import 'protocols.dart';
import 'weather.dart';

// ====== Giao tiếp hồng ngoại (gọi sang Kotlin) ======
const _ch = MethodChannel('ir');

Future<bool> hasIr() async {
  try {
    return await _ch.invokeMethod<bool>('hasIr') ?? false;
  } catch (_) {
    return false;
  }
}

Future<void> sendIr(List<int> pattern, {int freq = 38000}) =>
    _ch.invokeMethod('transmit', {'freq': freq, 'pattern': pattern});

const protoLabel = {
  Proto.gree: 'Gree A',
  Proto.greeB: 'Gree B',
  Proto.coolix: 'Coolix',
  Proto.lg1: 'LG1',
  Proto.lg2: 'LG2',
  Proto.midea: 'Midea',
  Proto.tcl: 'TCL',
  Proto.samsung: 'Samsung',
  Proto.daikin: 'Daikin',
  Proto.panasonic: 'Panasonic',
};

const modeLabel = {
  AcMode.cool: 'Lạnh',
  AcMode.dry: 'Khô',
  AcMode.fan: 'Quạt',
  AcMode.auto: 'Tự động',
  AcMode.heat: 'Sưởi',
};

const modeIcon = {
  AcMode.cool: Icons.ac_unit,
  AcMode.dry: Icons.water_drop_outlined,
  AcMode.fan: Icons.air,
  AcMode.auto: Icons.autorenew,
  AcMode.heat: Icons.wb_sunny_outlined,
};

const fanLabel = {
  AcFan.low: 'Quạt nhẹ',
  AcFan.medium: 'Quạt vừa',
  AcFan.high: 'Quạt mạnh',
  AcFan.auto: 'Quạt tự động',
};

const featLabel = {
  Feat.swing: 'Đảo gió',
  Feat.sleep: 'Ngủ',
  Feat.turbo: 'Turbo',
  Feat.light: 'Đèn',
};

/// Đọc giá trị enum từ tên đã lưu trong CSDL, sai tên thì dùng giá trị mặc định.
T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

// ====== Giao diện ======
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Cloud.init(); // không làm app lỗi nếu Firebase chưa cấu hình
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Remote',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFF4F4F6),
        ),
        home: const AcPage(),
      );
}

/// Icon cánh quạt tự vẽ (bộ icon có sẵn của Flutter không có hình quạt).
class FanIcon extends StatelessWidget {
  final Color color;
  final double size;

  const FanIcon({super.key, required this.color, this.size = 24});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _FanPainter(color));
}

class _FanPainter extends CustomPainter {
  final Color color;

  const _FanPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.075
      ..strokeJoin = StrokeJoin.round;
    canvas.translate(r, r);
    // 4 cánh, mỗi cánh là một hình bầu dục hơi nghiêng
    for (var k = 0; k < 4; k++) {
      canvas.save();
      canvas.rotate(k * 3.14159265 / 2);
      canvas.translate(0, -r * 0.5);
      canvas.rotate(0.35);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: r * 0.55, height: r * 0.95),
        paint,
      );
      canvas.restore();
    }
    canvas.drawCircle(Offset.zero, r * 0.12, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _FanPainter old) => old.color != color;
}

/// Nút tròn trắng có nhãn nhỏ bên dưới, giống app remote.
class RoundBtn extends StatelessWidget {
  final IconData? icon;
  final Widget Function(Color color)? iconBuilder;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  final Color? iconColor;

  const RoundBtn({
    super.key,
    this.icon,
    this.iconBuilder,
    required this.label,
    required this.onTap,
    this.active = false,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color color = onTap == null
        ? Colors.black26
        : (iconColor ?? (active ? cs.primary : Colors.black87));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: active ? cs.primaryContainer : Colors.white,
          shape: const CircleBorder(),
          elevation: 1.5,
          shadowColor: Colors.black38,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 72,
              height: 72,
              child: iconBuilder != null
                  ? Center(child: iconBuilder!(color))
                  : Icon(icon, size: 28, color: color),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ],
    );
  }
}

class AcPage extends StatefulWidget {
  const AcPage({super.key});

  @override
  State<AcPage> createState() => _AcPageState();
}

class _AcPageState extends State<AcPage> with WidgetsBindingObserver {
  bool? ir;
  Proto proto = Proto.gree;
  AcMode mode = AcMode.cool;
  AcFan fan = AcFan.auto;
  int temp = 26;
  bool powered = false; // app tự nhớ đã gửi BẬT hay TẮT lần gần nhất
  final Map<Feat, bool> feat = {
    Feat.swing: false,
    Feat.sleep: false,
    Feat.turbo: false,
    Feat.light: true,
  };
  bool probing = false;
  bool showSettings = false;
  String status = '';
  final hex = TextEditingController(text: 'B27BE0');
  int? deviceId; // thiết bị đang dùng (khóa trong bảng devices)
  String deviceName = 'Điều hòa';
  List<Map<String, Object?>> devices = [];
  List<Map<String, Object?>> presets = [];

  bool get _isLg => proto == Proto.lg1 || proto == Proto.lg2;
  bool get _isCoolix => proto == Proto.coolix;

  /// Giao thức gửi cả trạng thái trong một khung (tính năng là các bit trong khung).
  /// Coolix dùng lệnh riêng cho từng tính năng; LG không có tính năng thêm.
  bool get _inFrame => !_isLg && !_isCoolix;

  /// Tính năng mỗi giao thức hỗ trợ (nút không hỗ trợ sẽ bị làm mờ).
  Set<Feat> get _feats {
    switch (proto) {
      case Proto.gree:
      case Proto.greeB:
      case Proto.coolix:
        return Feat.values.toSet();
      case Proto.lg1:
      case Proto.lg2:
        return <Feat>{};
      case Proto.midea:
        return {Feat.sleep};
      case Proto.tcl:
        return {Feat.swing, Feat.turbo, Feat.light};
      case Proto.samsung:
        return {Feat.swing};
      case Proto.daikin:
      case Proto.panasonic:
        return {Feat.swing, Feat.turbo};
    }
  }

  int get _minTemp {
    switch (proto) {
      case Proto.coolix:
      case Proto.midea:
        return 17;
      case Proto.lg1:
      case Proto.lg2:
        return 18;
      default:
        return 16;
    }
  }

  List<AcMode> get _modes =>
      _isLg ? AcMode.values.where((m) => m != AcMode.heat).toList() : AcMode.values;

  @override
  void initState() {
    super.initState();
    hasIr().then((v) {
      if (mounted) setState(() => ir = v);
    });
    WidgetsBinding.instance.addObserver(this);
    Cloud.onRemoteChanged = _reloadFromCloud;
    _loadDb();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Cloud.onRemoteChanged = null;
    hex.dispose();
    super.dispose();
  }

  // Quay lại app thì kéo dữ liệu mới từ máy khác trước khi người dùng bấm nút.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) Cloud.syncNow();
  }

  // ---------- Tạo và phát lệnh ----------

  IrCmd _cmd(Proto p, bool on, {bool powerChange = true}) {
    switch (p) {
      case Proto.midea:
        final b = mideaState(
            on: on, mode: mode, temp: temp, fan: fan, sleep: feat[Feat.sleep]!);
        return IrCmd(mideaPattern(b), hexBytes(b));
      case Proto.tcl:
        final b = tclState(
          on: on,
          mode: mode,
          temp: temp,
          fan: fan,
          swing: feat[Feat.swing]!,
          turbo: feat[Feat.turbo]!,
          light: feat[Feat.light]!,
        );
        return IrCmd(tclPattern(b), hexBytes(b));
      case Proto.samsung:
        if (!on) return IrCmd(samsungPattern(samsungOff), hexBytes(samsungOff));
        final b = samsungState(
            on: true, mode: mode, temp: temp, fan: fan, swing: feat[Feat.swing]!);
        final out = powerChange ? samsungExtended(b) : b;
        return IrCmd(samsungPattern(out), hexBytes(out));
      case Proto.daikin:
        final b = daikinState(
          on: on,
          mode: mode,
          temp: temp,
          fan: fan,
          swing: feat[Feat.swing]!,
          powerful: feat[Feat.turbo]!,
        );
        return IrCmd(daikinPattern(b), hexBytes(b));
      case Proto.panasonic:
        final b = panasonicState(
          on: on,
          mode: mode,
          temp: temp,
          fan: fan,
          swing: feat[Feat.swing]!,
          powerful: feat[Feat.turbo]!,
        );
        return IrCmd(panasonicPattern(b), hexBytes(b), freq: 36700);
      default:
        break;
    }
    if (p == Proto.gree || p == Proto.greeB) {
      final b = greeState(
        on: on,
        mode: mode,
        temp: temp,
        fan: fan,
        swing: feat[Feat.swing]!,
        modelA: p == Proto.gree,
        sleep: feat[Feat.sleep]!,
        turbo: feat[Feat.turbo]!,
        light: feat[Feat.light]!,
      );
      return IrCmd(greePattern(b), hexBytes(b));
    }
    if (p == Proto.coolix) {
      final c = coolixFrame(on: on, mode: mode, temp: temp, fan: fan);
      return IrCmd(coolixPattern(c), hexInt(c));
    }
    final c = lgFrame(on: on, mode: mode, temp: temp, fan: fan);
    return IrCmd(lgPattern(c, lg2: p == Proto.lg2), hexInt(c));
  }

  Future<void> _transmit(IrCmd c, String what) async {
    try {
      await sendIr(c.pattern, freq: c.freq);
      if (mounted) setState(() => status = 'Đã gửi $what [${protoLabel[proto]}] ${c.desc}');
    } catch (e) {
      if (mounted) setState(() => status = 'Lỗi: $e');
    }
  }

  Future<void> _send(bool on) {
    final powerChange = on != powered; // Samsung cần khung riêng khi đổi nguồn
    setState(() => powered = on);
    final id = deviceId;
    if (id != null) Db.setMeta('powered_$id', on ? '1' : '0');
    if (powerChange) {
      Cloud.log(on ? 'on' : 'off',
          device: deviceName, proto: proto.name, mode: mode.name, temp: temp);
    }
    return _transmit(_cmd(proto, on, powerChange: powerChange), on ? 'BẬT' : 'TẮT');
  }

  void _togglePower() => _send(!powered);

  // Áp dụng gợi ý từ thẻ thời tiết (LG không có chế độ Sưởi)
  void _applyAdvice(AcMode m, int t) {
    if (_isLg && m == AcMode.heat) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Giao thức LG không có chế độ Sưởi')));
      return;
    }
    _change(() {
      mode = m;
      temp = t < _minTemp ? _minTemp : t;
    });
  }

  // Đổi giá trị rồi phát ngay (kèm lệnh BẬT), giống bấm nút trên remote thật
  void _change(VoidCallback fn) {
    setState(fn);
    _persist();
    if (ir == true) _send(true);
  }

  void _nextMode() {
    final list = _modes;
    final next = list[(list.indexOf(mode) + 1) % list.length];
    _change(() => mode = next);
  }

  void _nextFan() {
    const order = [AcFan.auto, AcFan.low, AcFan.medium, AcFan.high];
    final next = order[(order.indexOf(fan) + 1) % order.length];
    _change(() => fan = next);
  }

  Future<void> _toggleFeat(Feat f) async {
    if (ir != true || !_feats.contains(f)) return;
    setState(() => feat[f] = !feat[f]!);
    _persist();
    if (_inFrame) {
      await _send(true); // là các bit trong khung lệnh
    } else {
      // Coolix: lệnh riêng, bấm một lần đổi trạng thái
      final frame = coolixFeat[f]!;
      await _transmit(IrCmd(coolixPattern(frame), hexInt(frame)), featLabel[f]!.toUpperCase());
    }
  }

  void _setProto(Proto p) {
    setState(() {
      proto = p;
      if (_isLg && mode == AcMode.heat) mode = AcMode.cool;
      if (temp < _minTemp) temp = _minTemp;
      hex.text = p == Proto.coolix ? 'B27BE0' : '88C0051';
    });
    _persist();
  }

  // ---------- Cơ sở dữ liệu SQLite ----------

  /// Trạng thái hiện tại dưới dạng Map để ghi vào CSDL.
  Map<String, Object?> _snapshot() => {
        'proto': proto.name,
        'mode': mode.name,
        'temp': temp,
        'fan': fan.name,
        'swing': feat[Feat.swing]! ? 1 : 0,
        'sleep': feat[Feat.sleep]! ? 1 : 0,
        'turbo': feat[Feat.turbo]! ? 1 : 0,
        'light': feat[Feat.light]! ? 1 : 0,
      };

  Map<String, Object?> _newDeviceMap(String name) => {
        'name': name,
        'proto': 'gree',
        'mode': 'cool',
        'temp': 26,
        'fan': 'auto',
        'swing': 0,
        'sleep': 0,
        'turbo': 0,
        'light': 1,
      };

  /// Nạp giá trị từ một dòng CSDL vào trạng thái của app (gọi trong setState).
  void _applyMap(Map<String, Object?> m, {bool withProto = true, bool withFeat = true}) {
    if (withProto) proto = _enumByName(Proto.values, m['proto'], Proto.gree);
    mode = _enumByName(AcMode.values, m['mode'], AcMode.cool);
    fan = _enumByName(AcFan.values, m['fan'], AcFan.auto);
    temp = clampInt((m['temp'] as int?) ?? 26, 16, 30);
    if (withFeat) {
      feat[Feat.swing] = m['swing'] == 1;
      feat[Feat.sleep] = m['sleep'] == 1;
      feat[Feat.turbo] = m['turbo'] == 1;
      feat[Feat.light] = (m['light'] ?? 1) == 1;
    }
    if (_isLg && mode == AcMode.heat) mode = AcMode.cool;
    if (temp < _minTemp) temp = _minTemp;
    hex.text = proto == Proto.coolix ? 'B27BE0' : '88C0051';
  }

  /// Ghi trạng thái hiện tại vào thiết bị đang dùng (không chờ kết quả).
  Future<void> _persist() async {
    final id = deviceId;
    if (id == null) return;
    try {
      await Db.updateDevice(id, _snapshot());
    } catch (_) {
      // Lưu thất bại không được làm hỏng việc điều khiển.
    }
  }

  /// Dữ liệu từ máy khác vừa về: nạp lại danh sách thiết bị và cài sẵn.
  Future<void> _reloadFromCloud() async {
    try {
      final id = deviceId;
      if (id == null) {
        await _loadDb();
        return;
      }
      var list = await Db.devices();
      if (list.isEmpty) {
        await Db.addDevice(_newDeviceMap('Điều hòa'));
        list = await Db.devices();
      }
      final cur = list.where((d) => d['id'] == id).toList();
      if (cur.isEmpty) {
        await _useDevice(list.first, list: list);
        return;
      }
      final ps = await Db.presets(id);
      if (!mounted) return;
      setState(() {
        devices = list;
        presets = ps;
        deviceName = cur.first['name'] as String;
        _applyMap(cur.first); // nạp lại giao thức/nhiệt độ vừa đổi ở máy khác
      });
    } catch (_) {}
  }

  Future<void> _loadDb() async {
    try {
      var list = await Db.devices();
      if (list.isEmpty) {
        await Db.addDevice(_newDeviceMap('Điều hòa'));
        list = await Db.devices();
      }
      final lastId = int.tryParse(await Db.getMeta('last_device') ?? '');
      final cur = list.firstWhere((d) => d['id'] == lastId, orElse: () => list.first);
      await _useDevice(cur, list: list);
    } catch (e) {
      if (mounted) setState(() => status = 'Lỗi CSDL: $e');
    }
  }

  /// Chuyển sang một thiết bị: nạp trạng thái đã lưu và danh sách cài sẵn.
  Future<void> _useDevice(Map<String, Object?> d, {List<Map<String, Object?>>? list}) async {
    final id = d['id'] as int;
    final ps = await Db.presets(id);
    await Db.setMeta('last_device', '$id');
    final wasOn = await Db.getMeta('powered_$id') == '1';
    if (!mounted) return;
    setState(() {
      deviceId = id;
      deviceName = d['name'] as String;
      if (list != null) devices = list;
      presets = ps;
      powered = wasOn;
      _applyMap(d);
    });
  }

  Future<String?> _askText(String title, String initial) async {
    final c = TextEditingController(text: initial);
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    return (r == null || r.isEmpty) ? null : r;
  }

  Future<bool> _confirm(String msg) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xóa')),
        ],
      ),
    );
    return r ?? false;
  }

  // ---------- Thiết bị ----------

  Future<void> _addDevice() async {
    final name = await _askText('Tên thiết bị', 'Điều hòa ${devices.length + 1}');
    if (name == null) return;
    try {
      final id = await Db.addDevice(_newDeviceMap(name));
      final list = await Db.devices();
      final d = list.firstWhere((x) => x['id'] == id);
      await _useDevice(d, list: list);
    } catch (e) {
      if (mounted) setState(() => status = 'Lỗi CSDL: $e');
    }
  }

  Future<void> _renameDevice(Map<String, Object?> d) async {
    final name = await _askText('Đổi tên', d['name'] as String);
    if (name == null) return;
    await Db.updateDevice(d['id'] as int, {'name': name});
    final list = await Db.devices();
    if (!mounted) return;
    setState(() {
      devices = list;
      if (d['id'] == deviceId) deviceName = name;
    });
  }

  Future<void> _deleteDevice(Map<String, Object?> d) async {
    if (devices.length <= 1) {
      setState(() => status = 'Cần giữ lại ít nhất một thiết bị.');
      return;
    }
    if (!await _confirm('Xóa "${d['name']}" và các cài sẵn của nó?')) return;
    await Db.deleteDevice(d['id'] as int);
    final list = await Db.devices();
    if (d['id'] == deviceId) {
      await _useDevice(list.first, list: list);
    } else if (mounted) {
      setState(() => devices = list);
    }
  }

  void _openDevices() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final d in devices)
              ListTile(
                leading: Icon(d['id'] == deviceId
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked),
                title: Text(d['name'] as String),
                subtitle: Text(
                    protoLabel[_enumByName(Proto.values, d['proto'], Proto.gree)]!),
                onTap: () {
                  Navigator.pop(ctx);
                  _useDevice(d);
                },
                trailing: PopupMenuButton<String>(
                  onSelected: (v) {
                    Navigator.pop(ctx);
                    if (v == 'rename') {
                      _renameDevice(d);
                    } else {
                      _deleteDevice(d);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Đổi tên')),
                    PopupMenuItem(value: 'delete', child: Text('Xóa')),
                  ],
                ),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Thêm thiết bị'),
              onTap: () {
                Navigator.pop(ctx);
                _addDevice();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Cài sẵn ----------

  Future<void> _savePreset() async {
    final id = deviceId;
    if (id == null) return;
    final name = await _askText('Tên cài sẵn', '${modeLabel[mode]} $temp°C');
    if (name == null) return;
    final m = _snapshot()..remove('proto');
    await Db.addPreset({...m, 'device_id': id, 'name': name});
    final ps = await Db.presets(id);
    if (mounted) setState(() => presets = ps);
  }

  Future<void> _applyPreset(Map<String, Object?> p) async {
    // Coolix: tính năng Ngủ, Turbo, Đèn, Đảo gió là lệnh bấm-đổi-trạng-thái,
    // không gửi lại theo cài sẵn được, nên chỉ áp dụng chế độ, nhiệt độ, quạt.
    setState(() => _applyMap(p, withProto: false, withFeat: _inFrame));
    _persist();
    if (ir == true) await _send(true);
  }

  Future<void> _deletePreset(Map<String, Object?> p) async {
    if (!await _confirm('Xóa cài sẵn "${p['name']}"?')) return;
    await Db.deletePreset(p['id'] as int);
    final id = deviceId;
    if (id == null) return;
    final ps = await Db.presets(id);
    if (mounted) setState(() => presets = ps);
  }

  // ---------- Dò giao thức ----------

  // Gửi lệnh BẬT lần lượt theo từng giao thức, cách nhau 3 giây.
  // Điều hòa "bíp" ở lần nào thì bấm DỪNG: ô giao thức sẽ dừng đúng ở đó.
  Future<void> _probe() async {
    final order = Proto.values;
    final start = proto; // dò xong không có kết quả thì trả về giao thức ban đầu
    setState(() => probing = true);
    for (var i = 0; i < order.length; i++) {
      if (!probing || !mounted) return;
      _setProto(order[i]);
      final c = _cmd(order[i], true);
      setState(() => status =
          'Dò ${i + 1}/${order.length}: ${protoLabel[order[i]]}. Nghe thấy "bíp" thì bấm DỪNG');
      try {
        await sendIr(c.pattern, freq: c.freq);
      } catch (e) {
        if (mounted) {
          _setProto(start);
          setState(() {
            status = 'Lỗi: $e';
            probing = false;
          });
        }
        return;
      }
      await Future.delayed(const Duration(seconds: 3));
    }
    if (mounted) {
      _setProto(start);
      setState(() {
        probing = false;
        status = 'Dò xong, không có phản hồi nào được xác nhận.';
      });
    }
  }

  void _stopProbe() {
    setState(() {
      probing = false;
      status = 'Đã dừng ở giao thức: ${protoLabel[proto]}. Dùng giao thức này để điều khiển.';
    });
  }

  Future<void> _sendRaw() async {
    try {
      final f = int.parse(hex.text.trim().replaceAll('0x', ''), radix: 16);
      final p = _isCoolix
          ? coolixPattern(f)
          : lgPattern(f, lg2: proto == Proto.lg2);
      await sendIr(p);
      setState(() => status = 'Đã gửi mã thô ${hexInt(f)} [${protoLabel[proto]}]');
    } catch (e) {
      setState(() => status = 'Lỗi: $e');
    }
  }

  // ---------- Giao diện ----------

  Widget _circle(IconData icon, VoidCallback? onTap) => Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 1,
        shadowColor: Colors.black38,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, color: Colors.black87),
          ),
        ),
      );

  Widget _topBar() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(
          children: [
            _circle(
              showSettings ? Icons.arrow_back : Icons.ac_unit,
              showSettings ? () => setState(() => showSettings = false) : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: showSettings
                  ? const Text(
                      'Cài đặt',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                    )
                  : InkWell(
                      onTap: _openDevices,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                '$deviceName · ${protoLabel[proto]}',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 17, fontWeight: FontWeight.w600),
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down),
                          ],
                        ),
                      ),
                    ),
            ),
            _circle(Icons.info_outline,
                () => setState(() => showSettings = !showSettings)),
          ],
        ),
      );

  Widget _infoItem(IconData i, String t) =>
      _infoItemW(Icon(i, size: 20, color: Colors.black54), t);

  Widget _infoItemW(Widget icon, String t) => Padding(
        padding: const EdgeInsets.only(right: 18, top: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(width: 6),
            Text(t, style: const TextStyle(fontSize: 13, color: Colors.black54)),
          ],
        ),
      );

  Widget _display() {
    final numColor = powered ? Colors.black : Colors.black26;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$temp',
                style: TextStyle(
                  fontSize: 108,
                  height: 1.05,
                  fontWeight: FontWeight.w800,
                  color: numColor,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 14, left: 4),
                child: Text('°C', style: TextStyle(fontSize: 22, color: numColor)),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: Text(
                  powered ? 'ĐANG BẬT' : 'ĐÃ TẮT',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: powered ? Colors.red : Colors.black38,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            children: [
              _infoItem(modeIcon[mode]!, modeLabel[mode]!),
              _infoItemW(const FanIcon(color: Colors.black54, size: 20), fanLabel[fan]!),
              if (feat[Feat.swing]!) _infoItem(Icons.swap_vert, 'Đảo gió'),
              if (feat[Feat.sleep]!) _infoItem(Icons.bedtime_outlined, 'Ngủ'),
              if (feat[Feat.turbo]!) _infoItem(Icons.bolt, 'Turbo'),
            ],
          ),
        ],
      ),
    );
  }

  // Mỗi ô của lưới 3 cột đều nhau, nút nằm giữa ô
  Widget _cell(Widget child, {int flex = 1}) =>
      Expanded(flex: flex, child: Center(child: child));

  Widget _tempPill() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(36),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1)),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  onPressed: temp > _minTemp ? () => _change(() => temp--) : null,
                  icon: const Icon(Icons.remove),
                ),
                const Text('°C', style: TextStyle(fontSize: 18, color: Colors.black54)),
                IconButton(
                  onPressed: temp < 30 ? () => _change(() => temp++) : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Nhiệt độ',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      );

  Widget _remote() {
    final enabled = ir == true;
    bool can(Feat f) => enabled && _feats.contains(f);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        children: [
          WeatherCard(onApply: _applyAdvice),
          const SizedBox(height: 12),
          _display(),
          const SizedBox(height: 24),
          Row(
            children: [
              _cell(RoundBtn(
                icon: Icons.apps,
                label: 'Chế độ',
                onTap: enabled ? _nextMode : null,
              )),
              _cell(RoundBtn(
                icon: Icons.power_settings_new,
                label: 'Nguồn',
                onTap: enabled ? _togglePower : null,
                iconColor: enabled && powered ? Colors.red : null,
              )),
              _cell(RoundBtn(
                icon: Icons.bedtime_outlined,
                label: 'Ngủ',
                active: feat[Feat.sleep]!,
                onTap: can(Feat.sleep) ? () => _toggleFeat(Feat.sleep) : null,
              )),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _cell(RoundBtn(
                icon: Icons.swap_vert,
                label: 'Đảo gió',
                active: feat[Feat.swing]!,
                onTap: can(Feat.swing) ? () => _toggleFeat(Feat.swing) : null,
              )),
              _cell(RoundBtn(
                icon: Icons.lightbulb_outline,
                label: 'Đèn',
                active: feat[Feat.light]!,
                onTap: can(Feat.light) ? () => _toggleFeat(Feat.light) : null,
              )),
              _cell(RoundBtn(
                iconBuilder: (c) => FanIcon(color: c, size: 28),
                label: 'Quạt',
                onTap: enabled ? _nextFan : null,
              )),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Turbo thẳng cột 1; thanh nhiệt độ chiếm cột 2 và 3
              _cell(RoundBtn(
                icon: Icons.bolt,
                label: 'Turbo',
                active: feat[Feat.turbo]!,
                onTap: can(Feat.turbo) ? () => _toggleFeat(Feat.turbo) : null,
              )),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _tempPill(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Cài sẵn',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in presets)
                  InputChip(
                    label: Text(p['name'] as String),
                    onPressed: enabled ? () => _applyPreset(p) : null,
                    onDeleted: () => _deletePreset(p),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('Lưu cài đặt này'),
                  onPressed: _savePreset,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            ir == false
                ? 'Điện thoại này không có đèn hồng ngoại.'
                : (status.isEmpty ? 'Hướng đèn IR (cạnh trên máy) vào điều hòa.' : status),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.black45),
          ),
        ],
      ),
    );
  }

  Widget _settings() {
    final enabled = ir == true;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('IR: ${ir == null ? "đang kiểm tra..." : (ir! ? "CÓ" : "KHÔNG")}'),
        const SizedBox(height: 12),
        const SyncCard(),
        const SizedBox(height: 16),
        const Text('Giao thức (cùng một hãng có thể dùng giao thức khác nhau: cứ thử lần lượt)'),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            for (final p in Proto.values)
              ChoiceChip(
                label: Text(protoLabel[p]!),
                selected: proto == p,
                onSelected: probing ? null : (_) => _setProto(p),
              ),
          ],
        ),
        const SizedBox(height: 12),
        probing
            ? FilledButton.icon(
                onPressed: _stopProbe,
                icon: const Icon(Icons.stop),
                label: const Text('DỪNG (điều hòa vừa kêu)'),
              )
            : OutlinedButton.icon(
                onPressed: enabled ? _probe : null,
                icon: const Icon(Icons.search),
                label: const Text('Dò tự động giao thức'),
              ),
        if (_isCoolix || _isLg) ...[
          const SizedBox(height: 24),
          const Divider(),
          Text('Gửi mã thô hex (${proto == Proto.coolix ? "Coolix 24-bit" : "LG 28-bit"})'),
          const SizedBox(height: 8),
          TextField(
            controller: hex,
            decoration: const InputDecoration(
              labelText: 'Mã hex',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: enabled ? _sendRaw : null,
            child: const Text('Gửi mã thô'),
          ),
        ],
        const SizedBox(height: 16),
        Text(status),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(child: showSettings ? _settings() : _remote()),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'db.dart';
import 'firebase_options.dart';

// IR một chiều: nếu tắt bằng remote giấy thì app không biết, nên mỗi lần bật tính tối đa 8 giờ.
const _maxSession = Duration(hours: 8);
Duration _cap(Duration d) => d > _maxSession ? _maxSession : d;

String _two(int v) => v.toString().padLeft(2, '0');

String _fmtTime(DateTime t) =>
    '${_two(t.hour)}:${_two(t.minute)} ${_two(t.day)}/${_two(t.month)}';

const _modeVi = {
  'cool': 'Lạnh',
  'dry': 'Khô',
  'fan': 'Quạt',
  'auto': 'Tự động',
  'heat': 'Sưởi',
};

/// Đồng bộ Firestore + nhật ký sử dụng. Dữ liệu của mỗi người nằm dưới users/{uid}:
///   devices/{cid}, presets/{cid}, logs/{id}
/// SQLite vẫn là bản chính (app chạy được khi không có mạng hoặc chưa đăng nhập).
class Cloud {
  static bool ready = false;
  static Timer? _debounce;
  static bool _syncing = false;
  static bool _again = false;

  /// main.dart gán hàm này để nạp lại giao diện khi dữ liệu từ máy khác về.
  static VoidCallback? onRemoteChanged;

  /// Dòng trạng thái đồng bộ hiện ở màn Cài đặt.
  static final ValueNotifier<String> status = ValueNotifier<String>('');

  static Future<void> init() async {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      ready = true;
      Db.onChanged = scheduleSync;
      FirebaseAuth.instance.authStateChanges().listen((u) {
        if (u != null) syncNow();
      });
    } catch (e) {
      ready = false;
      status.value = 'Firebase chưa sẵn sàng: $e';
    }
  }

  static User? get user => ready ? FirebaseAuth.instance.currentUser : null;

  static DocumentReference<Map<String, dynamic>> get _root =>
      FirebaseFirestore.instance.collection('users').doc(user!.uid);

  static bool _googleInit = false;

  /// Đăng nhập Google bằng hộp chọn tài khoản của Android (không mở trình duyệt).
  static Future<void> signIn() async {
    if (!_googleInit) {
      await GoogleSignIn.instance.initialize();
      _googleInit = true;
    }
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    final cred = GoogleAuthProvider.credential(idToken: idToken);
    await FirebaseAuth.instance.signInWithCredential(cred);
  }

  static Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    await FirebaseAuth.instance.signOut();
  }

  /// Chờ 3 giây không có thay đổi mới rồi mới đồng bộ (tránh ghi liên tục).
  static void scheduleSync() {
    if (user == null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), syncNow);
  }

  static Future<void> syncNow() async {
    if (user == null) return;
    if (_syncing) {
      _again = true;
      return;
    }
    _syncing = true;
    try {
      status.value = 'Đang đồng bộ...';
      final changed = await _sync().timeout(const Duration(seconds: 25));
      final n = DateTime.now();
      status.value = 'Đã đồng bộ lúc ${_two(n.hour)}:${_two(n.minute)}';
      if (changed) onRemoteChanged?.call();
    } on TimeoutException {
      status.value = 'Chưa có mạng, sẽ tự đồng bộ khi có lại.';
    } catch (e) {
      status.value = 'Lỗi đồng bộ: $e';
    } finally {
      _syncing = false;
      if (_again) {
        _again = false;
        scheduleSync();
      }
    }
  }

  static Map<String, Object?> _devDoc(Map<String, Object?> l) => {
        'name': l['name'],
        'proto': l['proto'],
        'mode': l['mode'],
        'temp': l['temp'],
        'fan': l['fan'],
        'swing': l['swing'],
        'sleep': l['sleep'],
        'turbo': l['turbo'],
        'light': l['light'],
        'updated': l['updated'],
        'deleted': false,
      };

  static Map<String, Object?> _preDoc(Map<String, Object?> l) =>
      {..._devDoc(l), 'device_cid': l['device_cid']};

  /// Đồng bộ hai chiều. Bản nào có "updated" mới hơn thì thắng. Trả về true nếu
  /// dữ liệu trên máy này bị đổi bởi dữ liệu từ đám mây.
  static Future<bool> _sync() async {
    final root = _root;
    final fs = FirebaseFirestore.instance;
    var changed = false;

    // 1) Báo các mục đã xóa lên đám mây trước (để không bị "sống lại").
    final pend = await Db.pendingDeletes();
    if (pend.isNotEmpty) {
      final b = fs.batch();
      for (final p in pend) {
        b.set(root.collection(p['kind'] as String).doc(p['cid'] as String),
            {'deleted': true, 'updated': p['updated']});
      }
      await b.commit();
      await Db.clearPending([for (final p in pend) p['cid'] as String]);
    }

    // 2) Lấy dữ liệu đám mây và dữ liệu trên máy.
    final remoteDev = await root.collection('devices').get();
    final remotePre = await root.collection('presets').get();
    final localDev = await Db.devices();
    final devByCid = <String, Map<String, Object?>>{
      for (final d in localDev)
        if (d['cid'] != null) d['cid'] as String: d,
    };

    final batch = fs.batch();
    var writes = 0;

    // 3) Thiết bị.
    final seenDev = <String>{};
    for (final doc in remoteDev.docs) {
      final r = doc.data();
      final cid = doc.id;
      seenDev.add(cid);
      final rUpd = (r['updated'] as num?)?.toInt() ?? 0;
      final l = devByCid[cid];
      if (r['deleted'] == true) {
        if (l != null) {
          await Db.deleteByCid('devices', cid);
          changed = true;
        }
        continue;
      }
      if (l == null) {
        await Db.applyRemoteDevice(cid, r);
        changed = true;
      } else {
        final lUpd = l['updated'] as int;
        if (rUpd > lUpd) {
          await Db.applyRemoteDevice(cid, r);
          changed = true;
        } else if (lUpd > rUpd) {
          batch.set(root.collection('devices').doc(cid), _devDoc(l));
          writes++;
        }
      }
    }
    for (final l in localDev) {
      final cid = l['cid'] as String?;
      if (cid != null && !seenDev.contains(cid)) {
        batch.set(root.collection('devices').doc(cid), _devDoc(l));
        writes++;
      }
    }

    // 4) Cài sẵn (sau khi thiết bị đã khớp).
    final localPre = await Db.allPresets();
    final preByCid = <String, Map<String, Object?>>{
      for (final p in localPre)
        if (p['cid'] != null) p['cid'] as String: p,
    };
    final seenPre = <String>{};
    for (final doc in remotePre.docs) {
      final r = doc.data();
      final cid = doc.id;
      seenPre.add(cid);
      final rUpd = (r['updated'] as num?)?.toInt() ?? 0;
      final l = preByCid[cid];
      if (r['deleted'] == true) {
        if (l != null) {
          await Db.deleteByCid('presets', cid);
          changed = true;
        }
        continue;
      }
      if (l == null) {
        await Db.applyRemotePreset(cid, r);
        changed = true;
      } else {
        final lUpd = l['updated'] as int;
        if (rUpd > lUpd) {
          await Db.applyRemotePreset(cid, r);
          changed = true;
        } else if (lUpd > rUpd) {
          batch.set(root.collection('presets').doc(cid), _preDoc(l));
          writes++;
        }
      }
    }
    for (final l in localPre) {
      final cid = l['cid'] as String?;
      if (cid != null && !seenPre.contains(cid)) {
        batch.set(root.collection('presets').doc(cid), _preDoc(l));
        writes++;
      }
    }

    if (writes > 0) await batch.commit();
    return changed;
  }

  /// Ghi nhật ký bật/tắt vào Firestore. Không chặn việc điều khiển.
  static void log(
    String action, {
    required String device,
    required String proto,
    required String mode,
    required int temp,
  }) {
    if (!ready) return;
    unawaited(() async {
      try {
        if (user == null) return;
        await _root.collection('logs').add({
          'action': action,
          'device': device,
          'proto': proto,
          'mode': mode,
          'temp': temp,
          'ts': Timestamp.now(),
        });
      } catch (_) {
        // Ghi nhật ký lỗi cũng không được ảnh hưởng điều khiển.
      }
    }());
  }
}

/// Thẻ "Tài khoản & đồng bộ" đặt trong màn Cài đặt.
class SyncCard extends StatelessWidget {
  const SyncCard({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Cloud.ready) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ValueListenableBuilder<String>(
            valueListenable: Cloud.status,
            builder: (_, s, __) => Text(s.isEmpty ? 'Firebase chưa được cấu hình.' : s),
          ),
        ),
      );
    }
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        final u = snap.data;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tài khoản & đồng bộ',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                if (u == null) ...[
                  const Text('Đăng nhập để đồng bộ thiết bị, cài sẵn và lưu lịch sử sử dụng.'),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.login),
                    label: const Text('Đăng nhập bằng Google'),
                    onPressed: () async {
                      try {
                        await Cloud.signIn();
                      } catch (e) {
                        Cloud.status.value = 'Đăng nhập lỗi: $e';
                      }
                    },
                  ),
                ] else ...[
                  Text(u.email ?? u.uid),
                  const SizedBox(height: 4),
                  ValueListenableBuilder<String>(
                    valueListenable: Cloud.status,
                    builder: (_, s, __) => Text(s,
                        style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.sync),
                        label: const Text('Đồng bộ ngay'),
                        onPressed: Cloud.syncNow,
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.history),
                        label: const Text('Lịch sử'),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => const HistoryPage()),
                        ),
                      ),
                      TextButton(
                        onPressed: Cloud.signOut,
                        child: const Text('Đăng xuất'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Lịch sử bật/tắt 7 ngày gần nhất và tổng giờ bật của từng thiết bị.
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  Future<List<Map<String, dynamic>>> _load() async {
    final since = Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 7)));
    final q = await FirebaseFirestore.instance
        .collection('users')
        .doc(Cloud.user!.uid)
        .collection('logs')
        .where('ts', isGreaterThan: since)
        .orderBy('ts')
        .get();
    return q.docs.map((d) => d.data()).toList();
  }

  /// Cộng thời gian từ lần BẬT đến lần TẮT kế tiếp của từng thiết bị.
  Map<String, Duration> _totals(List<Map<String, dynamic>> logs) {
    final start = <String, DateTime>{};
    final total = <String, Duration>{};
    for (final m in logs) {
      final dev = (m['device'] ?? '?').toString();
      final t = (m['ts'] as Timestamp).toDate();
      if (m['action'] == 'on') {
        start.putIfAbsent(dev, () => t);
      } else {
        final s = start.remove(dev);
        if (s != null) total[dev] = (total[dev] ?? Duration.zero) + _cap(t.difference(s));
      }
    }
    final now = DateTime.now();
    start.forEach((dev, s) {
      total[dev] = (total[dev] ?? Duration.zero) + _cap(now.difference(s));
    });
    return total;
  }

  String _fmtDur(Duration d) => '${d.inHours} giờ ${d.inMinutes % 60} phút';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lịch sử sử dụng')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _load(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Lỗi: ${snap.error}'));
          }
          final logs = snap.data ?? [];
          if (logs.isEmpty) return const Center(child: Text('Chưa có lịch sử.'));
          final totals = _totals(logs);
          final recent = logs.reversed.take(100).toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Tổng thời gian bật (7 ngày, ước tính)',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              for (final e in totals.entries) Text('${e.key}: ${_fmtDur(e.value)}'),
              const Divider(height: 28),
              for (final m in recent)
                ListTile(
                  dense: true,
                  leading: Icon(
                    m['action'] == 'on' ? Icons.power_settings_new : Icons.power_off_outlined,
                    color: m['action'] == 'on' ? Colors.green : Colors.black45,
                  ),
                  title: Text(
                    '${m['action'] == 'on' ? 'Bật' : 'Tắt'} · ${m['device']}'
                    '${m['action'] == 'on' ? ' · ${_modeVi[m['mode']] ?? m['mode']} ${m['temp']}°C' : ''}',
                  ),
                  subtitle: Text(_fmtTime((m['ts'] as Timestamp).toDate())),
                ),
            ],
          );
        },
      ),
    );
  }
}

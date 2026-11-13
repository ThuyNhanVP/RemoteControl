import 'dart:math';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Mã định danh dùng chung giữa các điện thoại (khóa trong Firestore).
String newCid() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${Random().nextInt(1 << 30).toRadixString(36)}';

int _now() => DateTime.now().millisecondsSinceEpoch;

int _int(Object? v, int fallback) => v is num ? v.toInt() : fallback;

/// Lớp truy cập SQLite của app. Dữ liệu nằm trong file remote.db trên điện thoại.
///
/// Bảng:
///  - devices:     mỗi thiết bị (điều hòa) kèm giao thức và trạng thái dùng gần nhất.
///  - presets:     các cài sẵn của từng thiết bị.
///  - meta:        cặp khóa/giá trị nhỏ (ví dụ thiết bị dùng lần cuối).
///  - pending_del: các mục đã xóa nhưng chưa báo lên đám mây.
///
/// Phiên bản 2 thêm cột cid (mã dùng chung) và updated (thời điểm sửa, mili giây)
/// để đồng bộ Firebase. Mọi thay đổi do người dùng gọi [onChanged] để lên lịch đồng bộ.
class Db {
  static Database? _db;

  /// Được gọi sau mỗi thay đổi dữ liệu của người dùng (firebase_sync dùng để đồng bộ).
  static void Function()? onChanged;

  static Future<Database> get _database async => _db ??= await _open();

  static Future<Database> _open() async {
    return openDatabase(
      join(await getDatabasesPath(), 'remote.db'),
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE devices(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            proto TEXT NOT NULL,
            mode TEXT NOT NULL,
            temp INTEGER NOT NULL,
            fan TEXT NOT NULL,
            swing INTEGER NOT NULL DEFAULT 0,
            sleep INTEGER NOT NULL DEFAULT 0,
            turbo INTEGER NOT NULL DEFAULT 0,
            light INTEGER NOT NULL DEFAULT 1,
            cid TEXT,
            updated INTEGER NOT NULL DEFAULT 0
          )''');
        await db.execute('''
          CREATE TABLE presets(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            mode TEXT NOT NULL,
            temp INTEGER NOT NULL,
            fan TEXT NOT NULL,
            swing INTEGER NOT NULL DEFAULT 0,
            sleep INTEGER NOT NULL DEFAULT 0,
            turbo INTEGER NOT NULL DEFAULT 0,
            light INTEGER NOT NULL DEFAULT 1,
            cid TEXT,
            device_cid TEXT,
            updated INTEGER NOT NULL DEFAULT 0
          )''');
        await db.execute('''
          CREATE TABLE meta(
            k TEXT PRIMARY KEY,
            v TEXT NOT NULL
          )''');
        await _createPending(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE devices ADD COLUMN cid TEXT');
          await db.execute('ALTER TABLE devices ADD COLUMN updated INTEGER NOT NULL DEFAULT 0');
          await db.execute('ALTER TABLE presets ADD COLUMN cid TEXT');
          await db.execute('ALTER TABLE presets ADD COLUMN device_cid TEXT');
          await db.execute('ALTER TABLE presets ADD COLUMN updated INTEGER NOT NULL DEFAULT 0');
          await _createPending(db);
          // Gán mã dùng chung cho dữ liệu đã có.
          final cidOfDevice = <int, String>{};
          for (final d in await db.query('devices')) {
            final cid = newCid();
            cidOfDevice[d['id'] as int] = cid;
            await db.update('devices', {'cid': cid, 'updated': _now()},
                where: 'id = ?', whereArgs: [d['id']]);
          }
          for (final p in await db.query('presets')) {
            await db.update(
              'presets',
              {
                'cid': newCid(),
                'device_cid': cidOfDevice[p['device_id'] as int],
                'updated': _now(),
              },
              where: 'id = ?',
              whereArgs: [p['id']],
            );
          }
        }
      },
    );
  }

  static Future<void> _createPending(Database db) => db.execute('''
        CREATE TABLE IF NOT EXISTS pending_del(
          cid TEXT PRIMARY KEY,
          kind TEXT NOT NULL,
          updated INTEGER NOT NULL
        )''');

  // ---------- Thiết bị ----------

  static Future<List<Map<String, Object?>>> devices() async =>
      (await _database).query('devices', orderBy: 'id');

  static Future<int> addDevice(Map<String, Object?> values) async {
    final id = await (await _database)
        .insert('devices', {...values, 'cid': newCid(), 'updated': _now()});
    onChanged?.call();
    return id;
  }

  static Future<void> updateDevice(int id, Map<String, Object?> values) async {
    await (await _database).update('devices', {...values, 'updated': _now()},
        where: 'id = ?', whereArgs: [id]);
    onChanged?.call();
  }

  /// Xóa thiết bị cùng toàn bộ cài sẵn của nó.
  static Future<void> deleteDevice(int id) async {
    final db = await _database;
    final rows = await db.query('devices', where: 'id = ?', whereArgs: [id]);
    for (final p in await db.query('presets', where: 'device_id = ?', whereArgs: [id])) {
      await _markDeleted(db, 'presets', p['cid'] as String?);
    }
    if (rows.isNotEmpty) await _markDeleted(db, 'devices', rows.first['cid'] as String?);
    await db.delete('presets', where: 'device_id = ?', whereArgs: [id]);
    await db.delete('devices', where: 'id = ?', whereArgs: [id]);
    onChanged?.call();
  }

  static Future<void> _markDeleted(Database db, String kind, String? cid) async {
    if (cid == null) return;
    await db.insert(
      'pending_del',
      {'cid': cid, 'kind': kind, 'updated': _now()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---------- Cài sẵn ----------

  static Future<List<Map<String, Object?>>> presets(int deviceId) async =>
      (await _database).query('presets',
          where: 'device_id = ?', whereArgs: [deviceId], orderBy: 'id');

  static Future<int> addPreset(Map<String, Object?> values) async {
    final db = await _database;
    final dev = await db.query('devices', where: 'id = ?', whereArgs: [values['device_id']]);
    final id = await db.insert('presets', {
      ...values,
      'cid': newCid(),
      'device_cid': dev.isEmpty ? null : dev.first['cid'],
      'updated': _now(),
    });
    onChanged?.call();
    return id;
  }

  static Future<void> deletePreset(int id) async {
    final db = await _database;
    final rows = await db.query('presets', where: 'id = ?', whereArgs: [id]);
    if (rows.isNotEmpty) await _markDeleted(db, 'presets', rows.first['cid'] as String?);
    await db.delete('presets', where: 'id = ?', whereArgs: [id]);
    onChanged?.call();
  }

  // ---------- Meta ----------

  static Future<String?> getMeta(String key) async {
    final rows = await (await _database).query('meta', where: 'k = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['v'] as String?;
  }

  static Future<void> setMeta(String key, String value) async {
    await (await _database).insert(
      'meta',
      {'k': key, 'v': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---------- Dành cho đồng bộ (không gọi onChanged) ----------

  static Future<List<Map<String, Object?>>> allPresets() async =>
      (await _database).query('presets', orderBy: 'id');

  static Future<List<Map<String, Object?>>> pendingDeletes() async =>
      (await _database).query('pending_del');

  static Future<void> clearPending(List<String> cids) async {
    final db = await _database;
    for (final c in cids) {
      await db.delete('pending_del', where: 'cid = ?', whereArgs: [c]);
    }
  }

  static Future<int?> _deviceIdByCid(String cid) async {
    final r = await (await _database)
        .query('devices', where: 'cid = ?', whereArgs: [cid]);
    return r.isEmpty ? null : r.first['id'] as int;
  }

  /// Ghi (thêm hoặc cập nhật) một thiết bị lấy từ đám mây.
  static Future<void> applyRemoteDevice(String cid, Map<String, dynamic> r) async {
    final db = await _database;
    final v = <String, Object?>{
      'name': (r['name'] ?? 'Điều hòa').toString(),
      'proto': (r['proto'] ?? 'gree').toString(),
      'mode': (r['mode'] ?? 'cool').toString(),
      'temp': _int(r['temp'], 26),
      'fan': (r['fan'] ?? 'auto').toString(),
      'swing': _int(r['swing'], 0),
      'sleep': _int(r['sleep'], 0),
      'turbo': _int(r['turbo'], 0),
      'light': _int(r['light'], 1),
      'updated': _int(r['updated'], 0),
    };
    final n = await db.update('devices', v, where: 'cid = ?', whereArgs: [cid]);
    if (n == 0) await db.insert('devices', {...v, 'cid': cid});
  }

  /// Ghi một cài sẵn lấy từ đám mây (bỏ qua nếu thiết bị của nó chưa có).
  static Future<void> applyRemotePreset(String cid, Map<String, dynamic> r) async {
    final db = await _database;
    final devCid = r['device_cid']?.toString();
    if (devCid == null) return;
    final did = await _deviceIdByCid(devCid);
    if (did == null) return;
    final v = <String, Object?>{
      'device_id': did,
      'device_cid': devCid,
      'name': (r['name'] ?? 'Cài sẵn').toString(),
      'mode': (r['mode'] ?? 'cool').toString(),
      'temp': _int(r['temp'], 26),
      'fan': (r['fan'] ?? 'auto').toString(),
      'swing': _int(r['swing'], 0),
      'sleep': _int(r['sleep'], 0),
      'turbo': _int(r['turbo'], 0),
      'light': _int(r['light'], 1),
      'updated': _int(r['updated'], 0),
    };
    final n = await db.update('presets', v, where: 'cid = ?', whereArgs: [cid]);
    if (n == 0) await db.insert('presets', {...v, 'cid': cid});
  }

  /// Xóa theo lệnh từ đám mây (kind: 'devices' hoặc 'presets').
  static Future<void> deleteByCid(String kind, String cid) async {
    final db = await _database;
    if (kind == 'devices') {
      final id = await _deviceIdByCid(cid);
      if (id != null) await db.delete('presets', where: 'device_id = ?', whereArgs: [id]);
    }
    await db.delete(kind, where: 'cid = ?', whereArgs: [cid]);
  }
}
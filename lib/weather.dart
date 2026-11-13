import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'db.dart';

/// Một địa điểm (thành phố) để xem thời tiết.
class Place {
  final String name;
  final double lat;
  final double lon;
  const Place(this.name, this.lat, this.lon);

  String encode() => '${name.replaceAll('|', ' ')}|$lat|$lon';

  static Place? decode(String? s) {
    if (s == null) return null;
    final p = s.split('|');
    if (p.length != 3) return null;
    final la = double.tryParse(p[1]);
    final lo = double.tryParse(p[2]);
    if (la == null || lo == null) return null;
    return Place(p[0], la, lo);
  }
}

/// Gọi API Open-Meteo (miễn phí, không cần khóa API).
class WeatherApi {
  static const defaultPlace = Place('Hà Nội', 21.0285, 105.8542);

  /// Dự báo hiện tại + 5 ngày.
  static Future<Map<String, dynamic>> forecast(Place p) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': p.lat.toString(),
      'longitude': p.lon.toString(),
      'current': 'temperature_2m,relative_humidity_2m,apparent_temperature,weather_code',
      'daily': 'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max',
      'timezone': 'auto',
      'forecast_days': '5',
    });
    final r = await http.get(uri).timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// Tìm địa điểm theo tên.
  static Future<List<Place>> search(String query) async {
    final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': query,
      'count': '6',
      'language': 'vi',
      'format': 'json',
    });
    final r = await http.get(uri).timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final list = (j['results'] as List?) ?? const [];
    final out = <Place>[];
    for (final e in list) {
      final m = e as Map<String, dynamic>;
      final admin = m['admin1'];
      final country = m['country'];
      final label = [
        m['name'],
        if (admin != null) admin,
        if (country != null) country,
      ].join(', ');
      out.add(Place(label, (m['latitude'] as num).toDouble(), (m['longitude'] as num).toDouble()));
    }
    return out;
  }
}

// Mã thời tiết WMO -> chữ và biểu tượng.
String _textFor(int c) {
  if (c == 0) return 'Trời quang';
  if (c <= 2) return 'Ít mây';
  if (c == 3) return 'Nhiều mây';
  if (c == 45 || c == 48) return 'Sương mù';
  if (c >= 51 && c <= 57) return 'Mưa phùn';
  if (c >= 61 && c <= 67) return 'Mưa';
  if (c >= 71 && c <= 77) return 'Tuyết';
  if (c >= 80 && c <= 82) return 'Mưa rào';
  if (c == 85 || c == 86) return 'Tuyết rơi';
  if (c >= 95) return 'Dông';
  return 'Không rõ';
}

IconData _iconFor(int c) {
  if (c == 0) return Icons.wb_sunny_outlined;
  if (c <= 2) return Icons.wb_cloudy_outlined;
  if (c == 3) return Icons.cloud_outlined;
  if (c == 45 || c == 48) return Icons.foggy;
  if (c >= 51 && c <= 57) return Icons.grain;
  if ((c >= 61 && c <= 67) || (c >= 80 && c <= 82)) return Icons.umbrella_outlined;
  if ((c >= 71 && c <= 77) || c == 85 || c == 86) return Icons.ac_unit;
  if (c >= 95) return Icons.thunderstorm_outlined;
  return Icons.cloud_outlined;
}

/// Gợi ý cài điều hòa theo nhiệt độ cảm nhận và độ ẩm.
String _advice(double feels, int humidity) {
  if (feels >= 35) return 'Rất nóng: nên đặt Lạnh 24–25°C, quạt vừa hoặc tự động.';
  if (feels >= 30) {
    if (humidity >= 80) return 'Nóng ẩm: thử chế độ Khô hoặc Lạnh 26°C.';
    return 'Nóng: nên đặt Lạnh 25–26°C.';
  }
  if (feels >= 26) {
    if (humidity >= 80) return 'Hơi oi: chế độ Khô sẽ dễ chịu hơn.';
    return 'Khá dễ chịu: Lạnh 26–27°C hoặc quạt là đủ.';
  }
  return 'Trời mát, thường không cần bật điều hòa.';
}

String _dayLabel(String iso, int i) {
  if (i == 0) return 'Nay';
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  const n = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
  return n[d.weekday - 1];
}

/// Thẻ thời tiết đặt ở đầu màn điều khiển.
class WeatherCard extends StatefulWidget {
  const WeatherCard({super.key});

  @override
  State<WeatherCard> createState() => _WeatherCardState();
}

class _WeatherCardState extends State<WeatherCard> {
  Place place = WeatherApi.defaultPlace;
  Map<String, dynamic>? data;
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    var fresh = false;
    try {
      final saved = Place.decode(await Db.getMeta('weather_place'));
      if (saved != null) place = saved;
      final cache = await Db.getMeta('weather_cache');
      if (cache != null) data = jsonDecode(cache) as Map<String, dynamic>;
      final at = int.tryParse(await Db.getMeta('weather_at') ?? '') ?? 0;
      fresh = data != null &&
          DateTime.now().millisecondsSinceEpoch - at < const Duration(minutes: 30).inMilliseconds;
    } catch (_) {}
    if (mounted) setState(() {});
    if (!fresh) await _refresh();
  }

  Future<void> _refresh() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final d = await WeatherApi.forecast(place);
      await Db.setMeta('weather_cache', jsonEncode(d));
      await Db.setMeta('weather_at', DateTime.now().millisecondsSinceEpoch.toString());
      if (!mounted) return;
      setState(() => data = d);
    } catch (_) {
      if (mounted) {
        setState(() => error = data == null
            ? 'Không tải được thời tiết (kiểm tra mạng).'
            : 'Không cập nhật được, đang hiện dữ liệu cũ.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _pickPlace() async {
    final c = TextEditingController();
    var results = <Place>[];
    String? msg;
    final chosen = await showDialog<Place>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          Future<void> go() async {
            final q = c.text.trim();
            if (q.isEmpty) return;
            setD(() => msg = 'Đang tìm...');
            try {
              final r = await WeatherApi.search(q);
              setD(() {
                results = r;
                msg = r.isEmpty ? 'Không tìm thấy.' : null;
              });
            } catch (_) {
              setD(() => msg = 'Lỗi mạng, thử lại.');
            }
          }

          return AlertDialog(
            title: const Text('Chọn thành phố'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: c,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => go(),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: 'Ví dụ: Hà Nội, Đà Nẵng',
                      suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: go),
                    ),
                  ),
                  if (msg != null)
                    Padding(padding: const EdgeInsets.only(top: 8), child: Text(msg!)),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final p in results)
                          ListTile(title: Text(p.name), onTap: () => Navigator.pop(ctx, p)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            ],
          );
        },
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() {
      place = chosen;
      data = null;
    });
    await Db.setMeta('weather_place', chosen.encode());
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    Widget body;
    if (d == null) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: loading
              ? const CircularProgressIndicator()
              : Text(error ?? 'Đang tải thời tiết...'),
        ),
      );
    } else {
      try {
        body = _content(d);
      } catch (_) {
        body = const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('Dữ liệu thời tiết không đọc được.'),
        );
      }
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                    icon: const Icon(Icons.place_outlined, size: 18),
                    label: Text(place.name, overflow: TextOverflow.ellipsis),
                    onPressed: _pickPlace,
                  ),
                ),
                IconButton(
                  tooltip: 'Cập nhật',
                  icon: loading
                      ? const SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                  onPressed: loading ? null : _refresh,
                ),
              ],
            ),
            body,
            if (error != null && d != null)
              Text(error!, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _content(Map<String, dynamic> d) {
    final cur = d['current'] as Map<String, dynamic>;
    final temp = (cur['temperature_2m'] as num).toDouble();
    final feels = (cur['apparent_temperature'] as num).toDouble();
    final hum = (cur['relative_humidity_2m'] as num).round();
    final code = (cur['weather_code'] as num).toInt();
    final daily = d['daily'] as Map<String, dynamic>;
    final times = (daily['time'] as List).cast<String>();
    final codes = daily['weather_code'] as List;
    final maxs = daily['temperature_2m_max'] as List;
    final mins = daily['temperature_2m_min'] as List;
    final rain = daily['precipitation_probability_max'] as List;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(_iconFor(code), size: 44),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${temp.round()}°C',
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
                Text('${_textFor(code)} · cảm giác ${feels.round()}° · ẩm $hum%',
                    style: const TextStyle(fontSize: 13)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(_advice(feels, hum), style: const TextStyle(fontSize: 13)),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var i = 0; i < times.length && i < 5; i++)
              Expanded(
                child: Column(
                  children: [
                    Text(_dayLabel(times[i], i), style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 2),
                    Icon(_iconFor((codes[i] as num).toInt()), size: 22),
                    const SizedBox(height: 2),
                    Text('${(maxs[i] as num).round()}°/${(mins[i] as num).round()}°',
                        style: const TextStyle(fontSize: 12)),
                    Text(
                      rain[i] == null ? '' : '${(rain[i] as num).round()}%',
                      style: const TextStyle(fontSize: 11, color: Colors.blue),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

import 'package:flutter/services.dart';

/// Nhiệt độ Sưởi nên đặt theo nhiệt độ cảm nhận; null nghĩa là chưa lạnh.
int? heatTempFor(double feels) => feels <= 17 ? 26 : (feels <= 21 ? 24 : null);

/// Kế hoạch nhắc: giờ gửi thông báo (ms) và dự báo tại giờ báo thức.
class ReminderPlan {
  final int at;
  final double feels;
  final int temp;
  final String hhmm;
  const ReminderPlan(this.at, this.feels, this.temp, this.hhmm);
}

String _2(int n) => n.toString().padLeft(2, '0');

/// Thuần Dart: có cần nhắc không. Dự báo hourly có giờ theo múi giờ của địa điểm,
/// shortcut: coi như trùng múi giờ điện thoại; nâng cấp khi dùng ở nước khác.
ReminderPlan? planReminder(Map<String, dynamic> forecast, int alarmMs, int nowMs,
    {int leadMin = 20}) {
  final at = alarmMs - leadMin * 60000;
  if (at <= nowMs) return null;
  final hourly = forecast['hourly'];
  if (hourly is! Map) return null;
  final a = DateTime.fromMillisecondsSinceEpoch(alarmMs);
  var h = DateTime(a.year, a.month, a.day, a.hour);
  if (a.minute >= 30) h = h.add(const Duration(hours: 1));
  final key = '${h.year}-${_2(h.month)}-${_2(h.day)}T${_2(h.hour)}:00';
  final i = (hourly['time'] as List).indexOf(key);
  if (i < 0) return null;
  final feels = ((hourly['apparent_temperature'] as List)[i] as num?)?.toDouble();
  if (feels == null) return null;
  final temp = heatTempFor(feels);
  if (temp == null) return null;
  return ReminderPlan(at, feels, temp, '${_2(a.hour)}:${_2(a.minute)}');
}

/// Đặt hoặc hủy thông báo "sắp báo thức, trời lạnh" qua Kotlin (kênh 'ir').
class Reminder {
  static const _ch = MethodChannel('ir');

  static Future<void> sync(Map<String, dynamic> forecast) async {
    try {
      final alarm = await _ch.invokeMethod<int>('nextAlarm');
      final plan = alarm == null
          ? null
          : planReminder(forecast, alarm, DateTime.now().millisecondsSinceEpoch);
      if (plan == null) {
        await _ch.invokeMethod('cancelReminder');
        return;
      }
      await _ch.invokeMethod('scheduleReminder', {
        'at': plan.at,
        'title': 'Sắp báo thức ${plan.hhmm}: trời lạnh',
        'body': 'Dự báo cảm giác ${plan.feels.round()}°C. Mở app để bật Sưởi ${plan.temp}°C?',
      });
    } catch (_) {} // nhắc là tiện ích phụ: lỗi kênh hay máy không có thì bỏ qua
  }
}

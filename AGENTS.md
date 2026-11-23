# AGENTS.md — tài liệu cho AI tiếp tục dự án

> Đọc file này TRƯỚC. Nó đủ để làm việc mà không cần đọc lại toàn bộ code. Chỉ mở file nguồn khi sửa đúng chỗ đó.
> Nếu công cụ của bạn tự đọc `CLAUDE.md` thay vì `AGENTS.md`, hãy sao nội dung này sang đó và giữ hai bản giống nhau.

## 0. QUY TẮC BẮT BUỘC: luôn cập nhật file này

Ngay sau khi hoàn thành MỖI tính năng, sửa lỗi hoặc thay đổi nào (mã, cấu hình, cách cài, quyết định thiết kế), và TRƯỚC khi báo hoàn thành cho người dùng, phải sửa file này:

1. Thêm một dòng vào mục **11. Nhật ký thay đổi** (ngày, việc đã làm, file đụng tới).
2. Cập nhật các mục bị ảnh hưởng: bảng giao thức (mục 4), dữ liệu và Firebase (5, 6), bản đồ file (2), việc còn lại (10), bẫy đã biết (9).
3. Tính năng mới xong thì chuyển khỏi mục 10 (việc còn lại) sang mục 3 (đã có).
4. Nếu đổi cách cài hoặc cách dùng thì cập nhật luôn `README.md`. Quy chuẩn Git (nhánh, commit, PR) nằm trong README, mục "Quy chuẩn làm việc với GitHub"; sửa AGENTS.md cùng commit với mã.
5. Giữ file ngắn: sửa tại chỗ, không chép đoạn mã dài, không lặp ý. Con số dòng trong mã dễ lệch, nên chỉ ghi tên hàm.
6. **Không bao giờ ghi khóa API, mật khẩu hay token vào mã, README, AGENTS.md hay thông điệp commit.** Chỉ ghi tên file chứa chúng (ví dụ `lib/secrets.dart`). Trước khi commit chạy kiểm tra các chuỗi khóa trong phần sắp commit (xem README, mục "Quy chuẩn làm việc với GitHub").

Không cập nhật file này coi như chưa xong việc.

## 1. Dự án là gì

App Flutter (Android) điều khiển điều hòa bằng đèn IR của điện thoại, dùng cá nhân. Điều hòa cần điều khiển: LG đời cũ (remote Chunghop, mã 606, ghi trên máy "LG IDC18M2") và Casper. Điện thoại thử: TECNO Camon 40 (CM5), Android 16, có đèn IR.

- Package Android: `com.example.test2`. Tên gói Dart: `test2` (kiểm tra `name:` trong `pubspec.yaml` nếu import test lỗi).
- Thư mục dự án trên máy người dùng: `D:\New folder` (Windows, Android Studio).
- Toàn bộ giao diện và chú thích bằng tiếng Việt.

## 2. Bản đồ file

| File | Việc | Hàm/lớp chính |
|---|---|---|
| `lib/main.dart` | Giao diện và trạng thái màn hình, nhãn tiếng Việt, gọi Kotlin, nút Trợ lý AI | `MethodChannel('ir')`, `hasIr`, `sendIr(pattern, freq)`, `RoundBtn`, `FanIcon`, `_AcPageState`, `_openAiAssistant`, `_applyAiResult` |
| `lib/ai_assistant.dart` | Trợ lý Giọng nói AI & Xử lý ngôn ngữ tự nhiên | `AiAssistantEngine`, `AiResult`, `AiAssistantSheet`, parser Local Smart NLP & Gemini API Cloud |
| `lib/protocols.dart` | Enum `AcMode`, `AcFan`, `Feat`, `Proto`, lớp `IrCmd` và mã hóa 10 giao thức. Thuần Dart, không import Flutter | `greeState/greePattern`, `coolixFrame/coolixPattern`, `lgFrame/lgPattern`, `mideaState/Pattern`, `tclState/Pattern`, `samsungState/Extended/Pattern/Off`, `daikinState/Pattern`, `panasonicState/Pattern`, `clampInt`, `hexInt`, `hexBytes`, `coolixFeat` |
| `lib/tv.dart` | `TvBrand`, `TvKey`, bảng mã NEC1 (địa chỉ + lệnh) của LG và Toshiba lấy từ IRDB, `necPattern` (khung NEC 38 kHz, bit thấp trước), `tvPattern`, `TvPage` (gửi qua `sendIr` của main.dart, đặt meta `last_ctrl`). Giao diện: `_btn`, `_rocker` (thanh Vol/CH), `_dpad` (vòng mũi tên), `_Tap` (thu nhỏ và sáng khi nhấn), kích thước hàng giữa tính theo bề rộng màn hình. `muted` chỉ là trạng thái đoán (bấm mute thì đảo, bấm Vol thì về bật tiếng) vì hồng ngoại một chiều. Thêm hãng: thêm vào `TvBrand` và `_codes`, đủ mọi `TvKey` (test kiểm tra). Toshiba dùng bộ mã remote đời mới (mũi tên 25/29/66/64, OK 33, Back 100, Menu 91); bộ cũ dùng Vol/Ch làm mũi tên đã thử và sai trên TV thật | `necPattern`, `tvPattern`, `TvPage` |
| `lib/hub.dart` | Màn hình chính kéo thả (`HubPage`), gọi `Cloud.syncNow()` khi app mở lại và hiện dòng trạng thái đồng bộ (`Cloud.status`, chạm để đồng bộ), hoạt ảnh sóng và nhịp tim, `defaultSpot`, `wavePush`, `heartBeat`, `kindIcon`; chỉ thiết bị có meta `last_ctrl` (đặt trong `_send` của main.dart) được nối với nút giữa | `HubPage`, `_Orb`, `_LinkPainter` |
| `lib/db.dart` | SQLite (sqflite), bản 3 | `Db.devices/addDevice/updateDevice/deleteDevice`, `presets/addPreset/deletePreset`, `getMeta/setMeta`, `onChanged`, hàm dành cho đồng bộ (`allPresets`, `pendingDeletes`, `applyRemoteDevice/Preset`, `deleteByCid`) |
| `lib/firebase_sync.dart` | Firebase | `Cloud` (init, signIn, signOut, syncNow, `_sync`, log), `SyncCard`, `HistoryPage` |
| `lib/weather.dart` | Thời tiết, gợi ý + nút Áp dụng | `WeatherApi.forecast/search`, `WeatherCard(onApply)`, `Place`, `Advice`, `_advice` |
| `lib/reminder.dart` | Nhắc trước báo thức khi trời lạnh | `heatTempFor`, `planReminder` (thuần Dart, có test), `Reminder.sync` |
| `lib/firebase_options.dart` | do `flutterfire configure` tạo, không sửa tay, nằm trong `.gitignore` | |
| `lib/secrets.dart` | Hai hằng số `defaultGeminiApiKey`, `defaultOpenRouterApiKey`; **nằm trong `.gitignore`**; máy mới phải tự tạo (để chuỗi rỗng `''` nếu không có khóa) vì `main.dart` và `ai_assistant.dart` import file này | |
| `test/protocols_test.dart`, `test/reminder_test.dart`, `test/ai_assistant_test.dart` | Test mã hóa, kế hoạch nhắc và bộ xử lý giọng nói AI | |
| `android/.../MainActivity.kt` | Kênh `ir`: `hasIr`, `transmit(freq, pattern)`, `nextAlarm`, `scheduleReminder`, `cancelReminder`, `setTile`, `tileOn`, `startSpeech`, `stopSpeech` (SpeechRecognizer) | |
| `android/.../IrTileService.kt` | Ô cài đặt nhanh bật/tắt điều hòa đang dùng; đọc lệnh IR đã lưu trong SharedPreferences `tile` và phát bằng Kotlin | |
| `android/app/src/main/res/drawable/ic_tile.xml` | Biểu tượng ô cài đặt nhanh | |
| `android/.../ReminderReceiver.kt` | Hiện thông báo khi đến giờ nhắc (kênh `remind`) | |
| `android/app/src/main/AndroidManifest.xml` | Quyền `TRANSMIT_IR`, `INTERNET`, `POST_NOTIFICATIONS`, `RECORD_AUDIO`; `android:label` là tên app; `<receiver android:name=".ReminderReceiver" android:exported="false"/>` và `<service android:name=".IrTileService" ...BIND_QUICK_SETTINGS_TILE>` | |
| `.github/workflows/ci.yml` | CI: analyze (`--no-fatal-infos`), test, build APK debug; tự tạo bản giả của 3 file bị gitignore | |
| `assets/icon/` | `icon.png`, `icon_foreground.png` cho `flutter_launcher_icons` | |

Trong `_AcPageState` (main.dart): `_cmd(proto, on, {powerChange})` dựng lệnh theo giao thức; `_send(on)` gửi và ghi nhật ký; `_change(fn)` đổi giá trị rồi gửi ngay; `_toggleFeat`; `_setProto`; `_applyMap/_snapshot/_persist` (state <-> SQLite); `_useDevice`; `_reloadFromCloud`; `_probe/_stopProbe`; `_remote()` (màn chính), `_settings()`; getters theo giao thức: `_feats`, `_minTemp`, `_modes`, `_inFrame`, `_isLg`, `_isCoolix`.

## 3. Tính năng đã có

- Điều khiển: Nguồn, Chế độ, Nhiệt độ (16–30 trên giao diện, tối thiểu theo giao thức), Quạt, Đảo gió, Ngủ, Đèn, Turbo. Đổi bất kỳ giá trị nào là gửi ngay cả trạng thái kèm BẬT.
- Trợ lý Giọng nói AI: nhận diện giọng nói tiếng Việt tự nhiên (Android native SpeechRecognizer + micro), xử lý bằng AI Local Parser (100% offline) hoặc Gemini / OpenRouter (nếu có khóa trong `lib/secrets.dart` hoặc nhập trong Cài đặt), tự động phân tích câu lệnh (bật/tắt, chế độ, nhiệt độ tuyệt đối/tương đối 'nóng quá/lạnh quá', tốc độ quạt, đảo gió/ngủ/turbo, đổi thiết bị, hỏi thời tiết). Có giao diện sóng âm, gợi ý câu lệnh mẫu và ô nhập văn bản.
- Dò tự động 10 giao thức (3 giây mỗi cái, bấm DỪNG khi điều hòa bíp; dò xong không dừng thì trả về giao thức ban đầu).
- Nhiều thiết bị (mỗi cái có giao thức, trạng thái riêng), cài sẵn, trạng thái tự lưu. Gửi mã thô hex cho Coolix và LG.
- Đồng bộ Firebase hai chiều (thiết bị, cài sẵn), nhật ký bật/tắt, màn Lịch sử (giờ bật 7 ngày, mỗi lần bật tối đa 8 giờ vì IR một chiều).
- Thẻ thời tiết Open-Meteo (hiện tại, 5 ngày, gợi ý cài điều hòa kể cả Sưởi khi cảm giác <= 21°C, nút **Áp dụng** gửi lệnh, đổi thành phố, cache 30 phút). LG không có Sưởi nên báo thay vì áp dụng.
- Ô cài đặt nhanh "Điều hòa": bật/tắt thiết bị đang dùng không cần mở app. Dart (`_syncTile`, gọi trong `_persist`, `_send`, `_useDevice`) lưu sẵn mẫu xung BẬT và TẮT; Kotlin phát khi bấm. Quay lại app thì `_adoptTile` nhận trạng thái nguồn.
- Nhắc trước báo thức: mỗi lần có dự báo mới, app đọc báo thức kế tiếp (`AlarmManager.getNextAlarmClock`), lấy dự báo cảm giác của giờ đó, nếu <= 21°C thì hẹn thông báo trước 20 phút gợi ý bật Sưởi; không lạnh hoặc không có báo thức thì hủy.
- Test mã hóa, README, icon bông tuyết.

## 4. Giao thức

Thứ tự enum `Proto`: `gree, greeB, coolix, lg1, lg2, midea, tcl, samsung, daikin, panasonic`. **Chỉ được thêm vào cuối** vì tên enum được lưu trong SQLite và Firestore. Thứ tự dò = `Proto.values`.

| Proto | Tính năng trong khung | Min °C | Chế độ | Ghi chú |
|---|---|---|---|---|
| gree, greeB | swing, sleep, turbo, light | 16 | tất cả | 8 byte, 2 khối 35+32 bit, bit thấp trước. Auto khóa 25°C |
| coolix | swing, sleep, turbo, light là **lệnh riêng bấm-một-lần** (`coolixFeat`) | 17 | tất cả | 24 bit + byte đảo, gửi 2 lần, bit cao trước. Tắt = `0xB27BE0` |
| lg1, lg2 | không | 18 | không có Sưởi | 28 bit. Tắt = `0x88C0051` |
| midea | sleep | 17 | tất cả | 6 byte, gửi lại bản đảo bit; đảo gió là lệnh riêng (chưa làm) |
| tcl | swing, turbo, light | 16 | tất cả | TCL112AC 14 byte, bit thấp trước |
| samsung | swing | 16 | tất cả | 14 byte; đổi nguồn phải gửi khung mở rộng 21 byte (`samsungExtended`); tắt dùng `samsungOff`. `_cmd` nhận `powerChange` |
| daikin | swing, turbo (=powerful) | 16 | tất cả | 35 byte, 3 khối |
| panasonic | swing, turbo (=powerful) | 16 | tất cả | 27 byte, 2 khối, **sóng mang 36 700 Hz** (còn lại 38 000). `IrCmd.freq` |

Mẫu xung là danh sách microgiây xen kẽ mark/space, bắt đầu bằng mark, kết thúc bằng mark (bỏ khoảng trống cuối).

Mức kiểm chứng: Midea, TCL, Samsung khớp từng byte với mã mẫu của thư viện IRremoteESP8266 (có test). Daikin khớp phần tiêu đề, tổng kiểm hai khối đầu, nhiệt độ; bit Turbo/Đảo gió suy từ khai báo cấu trúc. Panasonic khớp tổng kiểm và độ dài chuỗi xung. Gree, Coolix, LG đối chiếu thư viện nhưng test chỉ kiểm cấu trúc. **Chưa giao thức nào được xác nhận trên điều hòa thật** ngoài lần gửi LG mã thô làm máy kêu bíp. LG: lệnh BẬT/TẮT từng không phản ứng; lỗi lệch nibble trong khung đã sửa, chưa xác nhận lại.

**Thêm một giao thức mới:**
1. Thêm tên vào cuối `enum Proto` và nhãn vào `protoLabel` (main.dart).
2. Viết `xxxState` và `xxxPattern` trong `protocols.dart`; nguồn đối chiếu: IRremoteESP8266 `ir_*.cpp/.h` và `ir_*_test.cpp`.
3. Thêm nhánh vào `_cmd`, và vào `_feats`, `_minTemp`, `_modes` (main.dart).
4. Thêm test có mã mẫu thật vào `test/protocols_test.dart`.
5. Cập nhật bảng này và README.

## 5. Dữ liệu cục bộ (SQLite `remote.db`, phiên bản 3)

- `devices(id, name, proto, mode, temp, fan, swing, sleep, turbo, light, cid, updated)`
- `presets(id, device_id, name, mode, temp, fan, swing, sleep, turbo, light, cid, device_cid, updated)`
- `meta(k, v)`; khóa dùng: `last_device`, `powered_<id>` (trạng thái bật/tắt cuối của từng thiết bị, chỉ trên máy), `weather_place`, `weather_cache`, `weather_at`.
- `pending_del(cid, kind, updated)`: các mục đã xóa nhưng chưa báo lên Firestore.
- `cid` là mã dùng chung giữa các máy; `updated` là mili giây. Sửa qua `Db.*` để `updated` và `onChanged` được cập nhật. Đổi cấu trúc bảng thì tăng `version` và viết `onUpgrade`, không phá dữ liệu cũ.

Bản 3: bảng `devices` thêm `kind` (mặc định `'ac'`, sau này `'tv'`), `px`, `py` (vị trí kéo thả trên hub, 0 đến 1). `px`/`py` chỉ ở máy, không đồng bộ (`Db.setPos` không đổi `updated`); thiết bị tạo từ máy khác có `px`/`py` null nên hub xếp theo `defaultSpot`. `kind` được đồng bộ (`_devDoc`, `applyRemoteDevice`; tài liệu cũ không có `kind` thì coi là `'ac'`). Thiết bị TV (`kind='tv'`) lưu hãng ở cột `proto` (`'lg'`, `'toshiba'`), các cột điều hòa giữ mặc định. `Db.devices(kind: 'ac')` lọc riêng điều hòa: mọi chỗ trong `AcPage` phải dùng bản lọc này, nếu không thiết bị TV lọt vào danh sách điều hòa.

## 6. Firebase

- Dữ liệu dưới `users/{uid}/`: `devices/{cid}`, `presets/{cid}`, `logs/{id}`. Xóa = ghi `{deleted: true, updated}` (không xóa tài liệu).
- Quy tắc Firestore: chỉ `request.auth.uid == uid` đọc/ghi.
- `Cloud.init()` gọi trong `main()`; Firebase lỗi thì app vẫn chạy (`Cloud.ready = false`).
- Đồng bộ (`_sync`): đẩy bản xóa, tải toàn bộ devices và presets, so `updated` (bản mới hơn thắng), đẩy phần khác bằng một batch. Chạy sau 3 giây kể từ thay đổi (`Db.onChanged`), khi đăng nhập, khi app trở lại từ nền (`didChangeAppLifecycleState`). Timeout 25 giây. Có dữ liệu mới về thì `_reloadFromCloud` nạp lại danh sách và trạng thái thiết bị hiện tại.
- Đăng nhập: `google_sign_in` bản 7 (`GoogleSignIn.instance.initialize()`, `authenticate()`, lấy `idToken`) rồi `FirebaseAuth.signInWithCredential`. **Không dùng `signInWithProvider`**: luồng qua trình duyệt báo "missing initial state" trên máy này.
- `Cloud.log` ghi `logs` khi trạng thái nguồn đổi (không ghi khi chỉnh nhiệt độ lúc đang bật). Đã bỏ Analytics.

## 7. Thời tiết

Open-Meteo, không cần khóa: `api.open-meteo.com/v1/forecast` (hiện tại + 5 ngày, `timezone=auto`) và `geocoding-api.open-meteo.com/v1/search`. Mặc định Hà Nội. Có thêm `hourly=apparent_temperature` cho phần nhắc. Lưu vị trí và cache JSON trong `meta`. Chưa gọi lại nếu cache dưới 30 phút (trừ nút làm mới và khi đổi thành phố).

## 8. Lệnh thường dùng

```
flutter pub get
flutter test
flutter run
dart run flutter_launcher_icons
dart pub global run flutterfire_cli:flutterfire configure   # flutterfire không có trong PATH
cd android; .\gradlew.bat signingReport                      # lấy SHA-1
```

Thư viện chính (có thể thiếu một số gói; xem `pubspec.yaml`): sqflite, path, firebase_core, firebase_auth, cloud_firestore, google_sign_in, http; dev: flutter_launcher_icons.

## 9. Bẫy đã gặp (đừng lặp lại)

- Windows cần bật **Developer Mode** (symlink) khi cài plugin.
- Project ở ổ D, cache pub ở ổ C: Kotlin báo `different roots` → thêm `kotlin.incremental=false` vào `android/gradle.properties`.
- Đăng nhập Google cần SHA-1 của khóa ký khai báo trong Firebase, tải lại `google-services.json`; thiếu thì log `INVALID_CERT_HASH` và nút không phản hồi.
- Cần plugin Gradle `com.google.gms.google-services` (settings.gradle.kts: `id("com.google.gms.google-services") version "4.4.2" apply false`; app/build.gradle.kts: `id("com.google.gms.google-services")`) và `minSdk = 23` nếu Gradle đòi.
- `AndroidManifest.xml` phải có `INTERNET` (bản release không tự có).
- Cảnh báo "plugins apply Kotlin Gradle Plugin" của Flutter là cảnh báo tương lai, bỏ qua được.
- Tên riêng tư (dấu `_`) chỉ dùng được trong cùng file: hàm dùng chung giữa `main.dart` và `protocols.dart` phải không có dấu gạch dưới.
- `google-services.json` và `firebase_options.dart` nằm trong `.gitignore` (GitHub báo lộ khóa API). Không commit lại; máy mới chạy `flutterfire configure`. Khóa Android đã giới hạn theo app và 4 API; đổi khóa ký phải thêm SHA-1.
- Nhắc báo thức chỉ cập nhật khi app mở (hoặc có dự báo mới): đổi báo thức mà không mở app thì thông báo cũ vẫn hẹn theo giờ cũ; khởi động lại máy làm mất hẹn. Dùng `setAndAllowWhileIdle` (không chính xác tuyệt đối). Giờ dự báo coi như cùng múi giờ điện thoại. Một số hãng (HiOS...) có thể không báo giờ báo thức qua `getNextAlarmClock`; chưa kiểm chứng trên TECNO.
- Ô cài đặt nhanh chỉ chạy được sau khi app đã mở ít nhất một lần (để lưu lệnh) và dùng thiết bị mở gần nhất; người dùng phải tự kéo ô vào bảng cài đặt nhanh. Ô và app có thể lệch trạng thái nguồn cho tới khi mở lại app.
- Đổi `MainActivity.kt` phải **dừng hẳn rồi chạy lại** app, hot reload không nạp Kotlin. Log `tile: MissingPluginException ... setTile` nghĩa là `MainActivity.kt` trên máy chưa có đoạn `setTile`. Ô cài đặt nhanh không bao giờ ở trạng thái mờ; chưa có lệnh đã lưu thì bấm ô sẽ mở app.
- IR một chiều: app không biết điều hòa thật đang bật hay tắt; `powered` chỉ là lệnh cuối app đã gửi.
- Khóa API AI **không được commit**. Khóa nằm trong `lib/secrets.dart` (đã gitignore) hoặc người dùng nhập trong Cài đặt (lưu SQLite `meta`: `gemini_api_key`, `openrouter_api_key`, chỉ trên máy, không đồng bộ Firebase). Máy mới clone về phải tạo `lib/secrets.dart` với hai hằng số rỗng, nếu không build lỗi. Một AI từng ghi nguyên khóa vào nhật ký này; đừng lặp lại.
- CI không có 3 file bị gitignore (`firebase_options.dart`, `google-services.json`, `secrets.dart`) nên tạo bản giả trong bước "Create stub config files" của `ci.yml`. Thêm hằng số mới vào `secrets.dart`, trường mới vào `DefaultFirebaseOptions`, hay thêm một file bí mật khác thì phải sửa bước này, nếu không CI đỏ. `flutter analyze --no-fatal-infos`: chỉ lỗi và cảnh báo làm CI đỏ.
- CI dùng **Flutter stable mới nhất** nên có thể đỏ khi Flutter ra bản mới (đã gặp: AGP tối thiểu tăng lên 9.1.1). Cách ổn định hơn: ghim `flutter-version` trong `ci.yml`. Bài test nào gọi mạng thật hoặc cần khóa thật phải có `skip` khi `lib/secrets.dart` rỗng.
- Nhận diện giọng nói SpeechRecognizer đòi hỏi quyền `RECORD_AUDIO` và dịch vụ Google Speech Services khả dụng trên máy; nếu máy không có Google Play Services hoặc lỗi micro thì app sẽ tự chuyển sang ô nhập chữ.
- Icon mặc định Flutter dùng tên `Icons.toys_outlined` trông như xe đồ chơi; quạt dùng `FanIcon` tự vẽ.
- Độ dài chuỗi xung tối đa mà bộ phát IR của máy chấp nhận chưa biết (Daikin khoảng 580 giá trị); nếu một giao thức dài không phát được, hãy nghi ngờ giới hạn này.

- Hub là màn hình chính nên việc đồng bộ khi mở lại app phải nằm trong `HubPage` (trước đây chỉ `AcPage` làm, nên mở app vào hub thì không kéo dữ liệu từ máy khác). Sửa lại ở 2026-11-21: nếu thêm màn gốc khác thì phải làm lại việc này.
- Dòng TV trong bảng `devices` và trên Firestore vẫn mang các cột điều hòa mặc định (`mode`, `temp`, `fan`, ...). Cố ý để vậy cho đơn giản, không ảnh hưởng điều khiển; bỏ đi thì phải sửa `_devDoc` và `applyRemoteDevice`.
- Phím trên màn TV dùng `_Tap` (GestureDetector + AnimatedScale), đừng đổi sang `InkWell` nếu không giữ hiệu ứng thu nhỏ.

## 10. Việc còn lại (theo thứ tự gợi ý)

1. Xác nhận giao thức của Casper và LG trên máy thật (kết quả dò của người dùng). Nếu không giao thức nào ăn: bắt tín hiệu remote thật bằng VS1838B + ESP32/Arduino (IRrecvDumpV2) rồi viết giao thức riêng.
2. TV: LG và Toshiba đã có (`tv.dart`). LG: tất cả phím chạy đúng trên TV thật (2026-11-23). Toshiba: Nguồn, Tắt tiếng, Vol đúng; mũi tên, OK, Back, Menu vừa đổi sang bộ mã đời mới, chưa xác nhận lại; Kênh chỉ chạy khi TV đang ở chế độ truyền hình; nếu một đời TV không ăn thì thử mã khác trong IRDB cùng hãng hoặc bắt mã bằng VS1838B. Còn lại: thêm hãng (Samsung, Sony, Panasonic cần giao thức khác NEC), nhấn giữ để lặp phím âm lượng, TV có Wi-Fi.
3. Hẹn giờ (phụ thuộc giao thức đã xác nhận).
4. Công tắc bật/tắt đồng bộ trong Cài đặt.
5. Thông báo đẩy từ xa (FCM cần Cloud Functions gói Blaze; thay thế không cần máy chủ: `flutter_local_notifications`).
6. Điều khiển từ xa qua internet bằng một điện thoại cũ làm "trạm" (lệnh qua Firestore).
7. Test thêm cho Gree, Coolix, LG bằng mã mẫu thật.

## 11. Nhật ký thay đổi

| Ngày | Thay đổi | File |
|---|---|---|
| 2026-11-21 | Giao diện TV thoáng hơn (vòng mũi tên, thanh Vol/CH, hiệu ứng nhấn), nút tắt tiếng đổi icon luân phiên; hub đồng bộ khi mở lại app và hiện trạng thái đồng bộ (sửa lỗi hub làm mất việc đồng bộ khi quay lại app) | lib/tv.dart, lib/hub.dart, README.md, AGENTS.md |
| 2026-11-23 | Toshiba: đổi mũi tên, OK, Back, Menu sang bộ mã remote đời mới sau khi thử TV thật (bộ cũ làm Trái/Phải thành Vol, Lên/Xuống không phản hồi) | lib/tv.dart, AGENTS.md |
| 2026-11-21 | Điều khiển TV LG và Toshiba (mã NEC1 từ IRDB), trang `TvPage`, thêm TV từ hub, đồng bộ `kind`, `Db.devices(kind:)`, test mã NEC | lib/tv.dart, lib/hub.dart, lib/db.dart, lib/firebase_sync.dart, lib/main.dart, test/tv_test.dart, README.md, AGENTS.md |
| 2026-11-19 | Màn hình chính kiểu smart home kéo thả (`HubPage`), `AcPage` nhận `deviceId`, SQLite lên bản 3 (`kind`, `px`, `py`), `Db.setPos`, `newAcDevice`, hoạt ảnh sóng/nhịp tim, đường nối tới thiết bị điều khiển gần nhất (meta `last_ctrl`), test `defaultSpot`/`wavePush`/`heartBeat` | lib/hub.dart, lib/db.dart, lib/main.dart, test/hub_test.dart, README.md, AGENTS.md |
| 2026-11-17 | CI chạy xanh: nâng Android Gradle Plugin 9.1.0 lên 9.1.1 (Flutter stable mới đòi tối thiểu 9.1.1); xóa 2 import thừa và bỏ qua bài test gọi OpenRouter thật khi không có khóa (`skip`) | android/settings.gradle.kts, test/ai_assistant_test.dart |
| 2026-11-17 | Thêm CI GitHub Actions (analyze, test, build APK debug, bản giả cho firebase_options, google-services, secrets) | .github/workflows/ci.yml, README.md, AGENTS.md |
| 2026-11-17 | Khóa API AI (Gemini, OpenRouter) chuyển ra `lib/secrets.dart` (nằm trong `.gitignore`, không commit); `main.dart` và `ai_assistant.dart` import file này; người dùng vẫn nhập khóa riêng trong Cài đặt | lib/secrets.dart, lib/ai_assistant.dart, lib/main.dart, .gitignore |
| 2026-11-17 | Thêm tùy chọn dịch vụ OpenRouter AI và danh sách mô hình miễn phí (Llama 3.3 70B, DeepSeek R1, Gemini 2.0 Flash Lite, Qwen 2.5 32B, Mistral 7B) trong Cài đặt + nút test OpenRouter API Key + unit test | lib/ai_assistant.dart, lib/main.dart, test/ai_assistant_test.dart |
| 2026-11-17 | Thêm tính năng & nút 'Kiểm tra Gemini API Key' trực tiếp trong màn hình Cài đặt (gửi test ping tới Gemini REST API) + unit test | lib/ai_assistant.dart, lib/main.dart, test/ai_assistant_test.dart |
| 2026-11-17 | Thêm Trợ lý Giọng nói AI: nhận diện giọng nói tiếng Việt (SpeechRecognizer Android native + RECORD_AUDIO), bộ xử lý ngôn ngữ tự nhiên Local Smart NLP (nhiệt độ tuyệt đối/tương đối 'nóng quá/lạnh quá', chế độ, quạt, tính năng, đổi thiết bị, thời tiết) & tích hợp Gemini AI Cloud tùy chọn, giao diện BottomSheet có sóng âm & nhập chữ, 8 unit test; sửa nút dừng thu âm chủ động xử lý ngay văn bản thu được và phát lệnh IR | lib/ai_assistant.dart, lib/main.dart, MainActivity.kt, AndroidManifest.xml, test/ai_assistant_test.dart |
| 2026-11-16 | Sửa ô cài đặt nhanh: không còn mờ, mở app nếu chưa có lệnh, in lỗi `tile:` ra log; đã chạy được trên máy thật (TECNO) | IrTileService.kt, main.dart |
| 2026-11-14 | Ô cài đặt nhanh bật/tắt điều hòa (`IrTileService`, `setTile`/`tileOn`, `_syncTile`/`_adoptTile`) | main.dart, MainActivity.kt, IrTileService.kt, res/drawable/ic_tile.xml, AndroidManifest.xml |
| 2026-11-14 | Gợi ý Sưởi khi lạnh + nút Áp dụng trên thẻ thời tiết; thông báo nhắc 20 phút trước báo thức khi trời lạnh (Kotlin `nextAlarm`/`scheduleReminder`/`ReminderReceiver`, `reminder.dart`, test) | weather.dart, main.dart, reminder.dart, MainActivity.kt, ReminderReceiver.kt, AndroidManifest.xml, test/reminder_test.dart |
| 2026-11-14 | Khóa API bị GitHub báo lộ: giới hạn khóa Android theo app + 4 API, gỡ 2 file Firebase khỏi repo, cập nhật quy chuẩn Git | .gitignore, README.md, AGENTS.md |
| 2026-11-13 | Tách mã hóa giao thức khỏi `main.dart` sang `protocols.dart`, thêm `test/protocols_test.dart`, viết README và AGENTS.md | main.dart, protocols.dart, test/, README.md, AGENTS.md |
| 2026-11-12 | Sửa theo review: đồng bộ khi quay lại app và nạp lại trạng thái từ cloud; dò giao thức trả về giao thức cũ; nhớ trạng thái nguồn từng thiết bị; giới hạn 8 giờ/lần bật khi thống kê; thời tiết dùng cache 30 phút; bỏ Analytics; bỏ đoạn lặp Gree | main.dart, firebase_sync.dart, weather.dart |
| 2026-11-10 | Thẻ thời tiết (Open-Meteo); đổi tên/icon app | weather.dart, main.dart |
| 2026-11-09 | Firebase: đăng nhập Google (credential), đồng bộ Firestore, nhật ký, Lịch sử; SQLite lên bản 2 | firebase_sync.dart, db.dart, main.dart, AndroidManifest.xml |
| 2026-11-03 → 11-09 | Thêm Midea, TCL, Samsung, Daikin, Panasonic; bảng khả năng theo giao thức; tần số sóng mang riêng | main.dart (nay là protocols.dart) |
| trước đó | IR qua kênh Kotlin; Gree A/B, Coolix, LG1/LG2; dò tự động; giao diện 3 cột kiểu OneLeap; SQLite (thiết bị, cài sẵn, trạng thái) | |
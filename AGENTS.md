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

Không cập nhật file này coi như chưa xong việc.

## 1. Dự án là gì

App Flutter (Android) điều khiển điều hòa bằng đèn IR của điện thoại, dùng cá nhân. Điều hòa cần điều khiển: LG đời cũ (remote Chunghop, mã 606, ghi trên máy "LG IDC18M2") và Casper. Điện thoại thử: TECNO Camon 40 (CM5), Android 16, có đèn IR.

- Package Android: `com.example.test2`. Tên gói Dart: `test2` (kiểm tra `name:` trong `pubspec.yaml` nếu import test lỗi).
- Thư mục dự án trên máy người dùng: `D:\New folder` (Windows, Android Studio).
- Toàn bộ giao diện và chú thích bằng tiếng Việt.

## 2. Bản đồ file

| File | Việc | Hàm/lớp chính |
|---|---|---|
| `lib/main.dart` | Giao diện và trạng thái màn hình, nhãn tiếng Việt, gọi Kotlin | `MethodChannel('ir')`, `hasIr`, `sendIr(pattern, freq)`, `RoundBtn`, `FanIcon`, `_AcPageState` |
| `lib/protocols.dart` | Enum `AcMode`, `AcFan`, `Feat`, `Proto`, lớp `IrCmd` và mã hóa 10 giao thức. Thuần Dart, không import Flutter | `greeState/greePattern`, `coolixFrame/coolixPattern`, `lgFrame/lgPattern`, `mideaState/Pattern`, `tclState/Pattern`, `samsungState/Extended/Pattern/Off`, `daikinState/Pattern`, `panasonicState/Pattern`, `clampInt`, `hexInt`, `hexBytes`, `coolixFeat` |
| `lib/db.dart` | SQLite (sqflite), bản 2 | `Db.devices/addDevice/updateDevice/deleteDevice`, `presets/addPreset/deletePreset`, `getMeta/setMeta`, `onChanged`, hàm dành cho đồng bộ (`allPresets`, `pendingDeletes`, `applyRemoteDevice/Preset`, `deleteByCid`) |
| `lib/firebase_sync.dart` | Firebase | `Cloud` (init, signIn, signOut, syncNow, `_sync`, log), `SyncCard`, `HistoryPage` |
| `lib/weather.dart` | Thời tiết | `WeatherApi.forecast/search`, `WeatherCard`, `Place` |
| `lib/firebase_options.dart` | do `flutterfire configure` tạo, không sửa tay | |
| `test/protocols_test.dart` | Test mã hóa | |
| `android/.../MainActivity.kt` | Kênh `ir`: `hasIr`, `transmit(freq, pattern)` qua `ConsumerIrManager` | |
| `android/app/src/main/AndroidManifest.xml` | Quyền `TRANSMIT_IR`, `INTERNET`; `android:label` là tên app | |
| `assets/icon/` | `icon.png`, `icon_foreground.png` cho `flutter_launcher_icons` | |

Trong `_AcPageState` (main.dart): `_cmd(proto, on, {powerChange})` dựng lệnh theo giao thức; `_send(on)` gửi và ghi nhật ký; `_change(fn)` đổi giá trị rồi gửi ngay; `_toggleFeat`; `_setProto`; `_applyMap/_snapshot/_persist` (state <-> SQLite); `_useDevice`; `_reloadFromCloud`; `_probe/_stopProbe`; `_remote()` (màn chính), `_settings()`; getters theo giao thức: `_feats`, `_minTemp`, `_modes`, `_inFrame`, `_isLg`, `_isCoolix`.

## 3. Tính năng đã có

- Điều khiển: Nguồn, Chế độ, Nhiệt độ (16–30 trên giao diện, tối thiểu theo giao thức), Quạt, Đảo gió, Ngủ, Đèn, Turbo. Đổi bất kỳ giá trị nào là gửi ngay cả trạng thái kèm BẬT.
- Dò tự động 10 giao thức (3 giây mỗi cái, bấm DỪNG khi điều hòa bíp; dò xong không dừng thì trả về giao thức ban đầu).
- Nhiều thiết bị (mỗi cái có giao thức, trạng thái riêng), cài sẵn, trạng thái tự lưu. Gửi mã thô hex cho Coolix và LG.
- Đồng bộ Firebase hai chiều (thiết bị, cài sẵn), nhật ký bật/tắt, màn Lịch sử (giờ bật 7 ngày, mỗi lần bật tối đa 8 giờ vì IR một chiều).
- Thẻ thời tiết Open-Meteo (hiện tại, 5 ngày, gợi ý cài điều hòa, đổi thành phố, cache 30 phút).
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

## 5. Dữ liệu cục bộ (SQLite `remote.db`, phiên bản 2)

- `devices(id, name, proto, mode, temp, fan, swing, sleep, turbo, light, cid, updated)`
- `presets(id, device_id, name, mode, temp, fan, swing, sleep, turbo, light, cid, device_cid, updated)`
- `meta(k, v)`; khóa dùng: `last_device`, `powered_<id>` (trạng thái bật/tắt cuối của từng thiết bị, chỉ trên máy), `weather_place`, `weather_cache`, `weather_at`.
- `pending_del(cid, kind, updated)`: các mục đã xóa nhưng chưa báo lên Firestore.
- `cid` là mã dùng chung giữa các máy; `updated` là mili giây. Sửa qua `Db.*` để `updated` và `onChanged` được cập nhật. Đổi cấu trúc bảng thì tăng `version` và viết `onUpgrade`, không phá dữ liệu cũ.

## 6. Firebase

- Dữ liệu dưới `users/{uid}/`: `devices/{cid}`, `presets/{cid}`, `logs/{id}`. Xóa = ghi `{deleted: true, updated}` (không xóa tài liệu).
- Quy tắc Firestore: chỉ `request.auth.uid == uid` đọc/ghi.
- `Cloud.init()` gọi trong `main()`; Firebase lỗi thì app vẫn chạy (`Cloud.ready = false`).
- Đồng bộ (`_sync`): đẩy bản xóa, tải toàn bộ devices và presets, so `updated` (bản mới hơn thắng), đẩy phần khác bằng một batch. Chạy sau 3 giây kể từ thay đổi (`Db.onChanged`), khi đăng nhập, khi app trở lại từ nền (`didChangeAppLifecycleState`). Timeout 25 giây. Có dữ liệu mới về thì `_reloadFromCloud` nạp lại danh sách và trạng thái thiết bị hiện tại.
- Đăng nhập: `google_sign_in` bản 7 (`GoogleSignIn.instance.initialize()`, `authenticate()`, lấy `idToken`) rồi `FirebaseAuth.signInWithCredential`. **Không dùng `signInWithProvider`**: luồng qua trình duyệt báo "missing initial state" trên máy này.
- `Cloud.log` ghi `logs` khi trạng thái nguồn đổi (không ghi khi chỉnh nhiệt độ lúc đang bật). Đã bỏ Analytics.

## 7. Thời tiết

Open-Meteo, không cần khóa: `api.open-meteo.com/v1/forecast` (hiện tại + 5 ngày, `timezone=auto`) và `geocoding-api.open-meteo.com/v1/search`. Mặc định Hà Nội. Lưu vị trí và cache JSON trong `meta`. Chưa gọi lại nếu cache dưới 30 phút (trừ nút làm mới và khi đổi thành phố).

## 8. Lệnh thường dùng

```
flutter pub get
flutter test
flutter run
dart run flutter_launcher_icons
dart pub global run flutterfire_cli:flutterfire configure   # flutterfire không có trong PATH
cd android; .\gradlew.bat signingReport                      # lấy SHA-1
```

Thư viện chính: sqflite, path, firebase_core, firebase_auth, cloud_firestore, google_sign_in, http; dev: flutter_launcher_icons.

## 9. Bẫy đã gặp (đừng lặp lại)

- Windows cần bật **Developer Mode** (symlink) khi cài plugin.
- Project ở ổ D, cache pub ở ổ C: Kotlin báo `different roots` → thêm `kotlin.incremental=false` vào `android/gradle.properties`.
- Đăng nhập Google cần SHA-1 của khóa ký khai báo trong Firebase, tải lại `google-services.json`; thiếu thì log `INVALID_CERT_HASH` và nút không phản hồi.
- Cần plugin Gradle `com.google.gms.google-services` (settings.gradle.kts: `id("com.google.gms.google-services") version "4.4.2" apply false`; app/build.gradle.kts: `id("com.google.gms.google-services")`) và `minSdk = 23` nếu Gradle đòi.
- `AndroidManifest.xml` phải có `INTERNET` (bản release không tự có).
- Cảnh báo "plugins apply Kotlin Gradle Plugin" của Flutter là cảnh báo tương lai, bỏ qua được.
- Tên riêng tư (dấu `_`) chỉ dùng được trong cùng file: hàm dùng chung giữa `main.dart` và `protocols.dart` phải không có dấu gạch dưới.
- `google-services.json` và `firebase_options.dart` nằm trong `.gitignore` (GitHub báo lộ khóa API). Không commit lại; máy mới chạy `flutterfire configure`. Khóa Android đã giới hạn theo app và 4 API; đổi khóa ký phải thêm SHA-1.
- IR một chiều: app không biết điều hòa thật đang bật hay tắt; `powered` chỉ là lệnh cuối app đã gửi.
- Icon mặc định Flutter dùng tên `Icons.toys_outlined` trông như xe đồ chơi; quạt dùng `FanIcon` tự vẽ.
- Độ dài chuỗi xung tối đa mà bộ phát IR của máy chấp nhận chưa biết (Daikin khoảng 580 giá trị); nếu một giao thức dài không phát được, hãy nghi ngờ giới hạn này.

## 10. Việc còn lại (theo thứ tự gợi ý)

1. Xác nhận giao thức của Casper và LG trên máy thật (kết quả dò của người dùng). Nếu không giao thức nào ăn: bắt tín hiệu remote thật bằng VS1838B + ESP32/Arduino (IRrecvDumpV2) rồi viết giao thức riêng.
2. Điều khiển TV (hãng chưa biết); mã lấy từ IRDB (probonopd/irdb) hoặc Flipper-IRDB.
3. Hẹn giờ (phụ thuộc giao thức đã xác nhận).
4. Nút "áp dụng gợi ý" từ thẻ thời tiết vào điều hòa.
5. Công tắc bật/tắt đồng bộ trong Cài đặt.
6. Thông báo nhắc (FCM cần Cloud Functions gói Blaze; thay thế không cần máy chủ: `flutter_local_notifications`).
7. Điều khiển từ xa qua internet bằng một điện thoại cũ làm "trạm" (lệnh qua Firestore).
8. Test thêm cho Gree, Coolix, LG bằng mã mẫu thật.

## 11. Nhật ký thay đổi

| Ngày | Thay đổi | File |
|---|---|---|
| 2026-11-14 | Khóa API bị GitHub báo lộ: giới hạn khóa Android theo app + 4 API, gỡ 2 file Firebase khỏi repo, cập nhật quy chuẩn Git | .gitignore, README.md, AGENTS.md |
| 2026-11-13 | Tách mã hóa giao thức khỏi `main.dart` sang `protocols.dart`, thêm `test/protocols_test.dart`, viết README và AGENTS.md | main.dart, protocols.dart, test/, README.md, AGENTS.md |
| 2026-11-12 | Sửa theo review: đồng bộ khi quay lại app và nạp lại trạng thái từ cloud; dò giao thức trả về giao thức cũ; nhớ trạng thái nguồn từng thiết bị; giới hạn 8 giờ/lần bật khi thống kê; thời tiết dùng cache 30 phút; bỏ Analytics; bỏ đoạn lặp Gree | main.dart, firebase_sync.dart, weather.dart |
| 2026-11-10 | Thẻ thời tiết (Open-Meteo); đổi tên/icon app | weather.dart, main.dart |
| 2026-11-09 | Firebase: đăng nhập Google (credential), đồng bộ Firestore, nhật ký, Lịch sử; SQLite lên bản 2 | firebase_sync.dart, db.dart, main.dart, AndroidManifest.xml |
| 2026-11-03 → 11-09 | Thêm Midea, TCL, Samsung, Daikin, Panasonic; bảng khả năng theo giao thức; tần số sóng mang riêng | main.dart (nay là protocols.dart) |
| trước đó | IR qua kênh Kotlin; Gree A/B, Coolix, LG1/LG2; dò tự động; giao diện 3 cột kiểu OneLeap; SQLite (thiết bị, cài sẵn, trạng thái) | |
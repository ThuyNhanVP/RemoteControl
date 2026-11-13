# Remote điều hòa (Flutter + hồng ngoại)

Ứng dụng Android điều khiển điều hòa bằng **đèn hồng ngoại (IR) có sẵn trên điện thoại**. Làm cho dùng cá nhân, thử trên TECNO Camon 40 (Android 16). Hỗ trợ nhiều giao thức vì cùng một hãng, thậm chí cùng một model, có máy ăn giao thức này, có máy ăn giao thức khác.

## Tính năng

- **Điều khiển điều hòa:** Nguồn, Chế độ (Lạnh, Khô, Quạt, Tự động, Sưởi), Nhiệt độ, Quạt, Đảo gió, Ngủ, Đèn, Turbo. Nút nào giao thức không hỗ trợ thì bị làm mờ.
- **10 giao thức IR:** Gree A, Gree B, Coolix, LG1, LG2, Midea, TCL, Samsung, Daikin, Panasonic.
- **Dò tự động giao thức:** app gửi lệnh BẬT lần lượt theo từng giao thức, bạn bấm DỪNG khi điều hòa kêu "bíp".
- **Nhiều thiết bị, nhiều cài sẵn:** mỗi điều hòa có giao thức và trạng thái riêng. Lưu và áp dụng cài sẵn bằng một chạm. Dữ liệu lưu trong SQLite trên máy.
- **Đồng bộ Firebase (tùy chọn):** đăng nhập Google để đồng bộ thiết bị và cài sẵn giữa nhiều điện thoại, lưu nhật ký bật/tắt và xem thống kê giờ bật 7 ngày.
- **Thời tiết:** dự báo hiện tại và 5 ngày theo thành phố (API Open-Meteo, miễn phí, không cần khóa), kèm gợi ý cài điều hòa.
- **Dùng được khi không có mạng:** điều khiển IR và dữ liệu SQLite không cần internet.

## Giao thức hỗ trợ

| Giao thức | Hãng thường gặp | Tính năng thêm | Nhiệt độ | Kiểm chứng |
|---|---|---|---|---|
| Gree A / Gree B | Gree và nhiều hãng khác | Đảo gió, Ngủ, Đèn, Turbo | 16–30 | Đối chiếu thư viện IRremoteESP8266 |
| Coolix | Nhiều máy giá rẻ | Đảo gió, Ngủ, Đèn, Turbo (lệnh riêng) | 17–30 | Đối chiếu thư viện |
| LG1 / LG2 | LG đời cũ (28 bit) | Không | 18–30 | Đối chiếu thư viện |
| Midea | Midea, Carrier, Comfee, Pioneer | Ngủ | 17–30 | Khớp mã mẫu (có test) |
| TCL | TCL, Hisense | Đảo gió, Turbo, Đèn | 16–30 | Khớp mã mẫu (có test) |
| Samsung | Samsung | Đảo gió | 16–30 | Khớp mã mẫu (có test) |
| Daikin | Daikin | Đảo gió, Turbo | 16–30 | Khớp một phần (có test) |
| Panasonic | Panasonic | Đảo gió, Turbo | 16–30 | Khớp tổng kiểm và độ dài (có test) |


## Yêu cầu

- Flutter (bản mới) và Android Studio. Làm việc trên Windows.
- Điện thoại Android **có đèn IR** (ConsumerIrManager). App tự kiểm tra và hiện "IR: CÓ" hoặc "KHÔNG" trong Cài đặt.
- Bật Developer Mode trong Windows (Flutter cần để tạo symlink khi cài plugin).
- Muốn đồng bộ: một project Firebase (gói miễn phí Spark là đủ).

## Cài đặt và chạy

1. Mở project trong Android Studio. Trong Terminal ở thư mục gốc (nơi có `pubspec.yaml`):
   ```
   flutter pub get
   flutter run
   ```
2. Chọn điện thoại thật (bật gỡ lỗi USB). Emulator không có đèn IR nên không phát được.
3. Nếu thư mục project và thư mục cache của Flutter nằm trên hai ổ đĩa khác nhau (ví dụ project ở `D:`, cache ở `C:`) và build báo `different roots`, thêm dòng này vào cuối `android/gradle.properties`:
   ```
   kotlin.incremental=false
   ```
4. Tạo file cài đặt: `flutter build apk --release`.

### Cấu hình Firebase (chỉ cần khi muốn đồng bộ)

1. Tạo project trên console.firebase.google.com và thêm app Android với package `com.example.test2`.
2. Cài công cụ: `npm install -g firebase-tools`, `dart pub global activate flutterfire_cli`, `firebase login`.
3. Trong thư mục project chạy `dart pub global run flutterfire_cli:flutterfire configure`. Lệnh tạo `lib/firebase_options.dart` và `android/app/google-services.json`.
4. Trong `android/settings.gradle.kts` và `android/app/build.gradle.kts`, kiểm tra plugin `com.google.gms.google-services` (xem `AGENTS.md` nếu thiếu).
5. Trên console: Authentication, bật nhà cung cấp **Google**. Firestore, tạo database (chế độ production) và dán quy tắc:
   ```
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       match /users/{uid}/{document=**} {
         allow read, write: if request.auth != null && request.auth.uid == uid;
       }
     }
   }
   ```
6. Thêm mã **SHA-1** của khóa ký vào app Android trong Project settings, tải lại `google-services.json`. Lấy SHA-1: `cd android` rồi `.\gradlew.bat signingReport`. Thiếu bước này, đăng nhập Google báo lỗi `INVALID_CERT_HASH`.

Chưa cấu hình Firebase thì app vẫn chạy bình thường, thẻ đồng bộ chỉ báo "Firebase chưa sẵn sàng".

## Cách dùng

1. **Chọn thiết bị:** bấm tên điều hòa ở thanh trên để mở danh sách. Chạm vào một thiết bị để dùng, bấm dấu ba chấm cạnh nó để đổi tên hoặc xóa, bấm **Thêm thiết bị** để tạo mới.
2. **Tìm giao thức đúng:** bấm biểu tượng chữ "i" ở góc phải trên để vào Cài đặt, bấm **Dò tự động giao thức**, đứng gần điều hòa. Điều hòa "bíp" thì bấm **DỪNG** ngay. Hoặc chọn tay từng giao thức ở các ô chọn.
3. **Điều khiển:** bấm các nút trên màn hình chính. Mỗi lần đổi chế độ, quạt, nhiệt độ hay tính năng, app gửi toàn bộ trạng thái kèm lệnh BẬT, giống bấm nút trên remote thật.
4. **Cài sẵn:** bấm "Lưu cài đặt này" để lưu, bấm vào một cài sẵn để áp dụng, bấm dấu x trên cài sẵn để xóa.
5. **Mã thô (Coolix, LG):** trong Cài đặt có ô gửi mã hex để thử mã tìm được từ nơi khác.
6. **Đồng bộ:** Cài đặt, "Đăng nhập bằng Google". Thiết bị và cài sẵn tự đồng bộ sau mỗi thay đổi và khi mở lại app. Nút **Lịch sử** hiện thống kê giờ bật.
7. **Thời tiết:** thẻ ở đầu màn hình chính. Bấm tên thành phố để đổi, bấm biểu tượng làm mới để cập nhật.

Lưu ý: IR chỉ truyền một chiều, app không biết điều hòa thật đang bật hay tắt. Nó chỉ nhớ lệnh cuối cùng nó đã gửi. Nếu bạn tắt bằng remote giấy, nút Nguồn trong app có thể lệch một nhịp.

## Cấu trúc thư mục

```
lib/
  main.dart            Giao diện, trạng thái màn hình, gọi sang Kotlin
  protocols.dart       Enum và mã hóa 10 giao thức (hàm thuần, không phụ thuộc Flutter)
  db.dart              SQLite (thiết bị, cài sẵn, meta) và dữ liệu phục vụ đồng bộ
  firebase_sync.dart   Đăng nhập, đồng bộ Firestore, nhật ký, màn Lịch sử
  weather.dart         Thẻ thời tiết và gọi API Open-Meteo
  firebase_options.dart  (do flutterfire tạo)
test/protocols_test.dart   Kiểm tra mã hóa giao thức
android/app/src/main/
  kotlin/.../MainActivity.kt   Phát IR qua ConsumerIrManager
  AndroidManifest.xml          Quyền TRANSMIT_IR và INTERNET
assets/icon/           Icon app (dùng với flutter_launcher_icons)
AGENTS.md              Tài liệu cho AI tiếp tục dự án
```

## Quy chuẩn làm việc với GitHub

**Nhánh**
- `main` luôn chạy được (`flutter test` qua, `flutter run` không lỗi). Không commit thẳng lên `main` khi sửa lớn.
- Mỗi việc một nhánh, đặt tên `loai/mo-ta-ngan`: `feat/hen-gio`, `fix/lg-nibble`, `docs/readme`, `refactor/db`, `test/gree`.

**Commit**

Cú pháp: `loại(phạm vi): mô tả ngắn` (phần phạm vi có thể bỏ). Mô tả viết thể mệnh lệnh, tiếng Việt, không chấm cuối, tối đa khoảng 70 ký tự.

| Type | Ý nghĩa | Khi nào sử dụng | Ví dụ |
|---|---|---|---|
| `feat` | Feature (Tính năng) | Thêm một tính năng mới cho người dùng | `feat(ui): thêm thanh chỉnh nhiệt độ` |
| `fix` | Bug Fix (Sửa lỗi) | Sửa một lỗi trong mã | `fix(lg): sửa lệch nibble khung LG` |
| `docs` | Documentation (Tài liệu) | Thêm hoặc sửa tài liệu (README, AGENTS) | `docs: thêm quy chuẩn Git vào README` |
| `style` | Code Style (Định dạng) | Sửa format, khoảng trắng, dấu chấm phẩy, không đổi logic | `style: format lại MainActivity` |
| `refactor` | Refactoring (Tối ưu mã) | Tái cấu trúc mã, không thêm tính năng, không sửa lỗi | `refactor: tách mã hóa sang protocols.dart` |
| `perf` | Performance (Hiệu năng) | Tăng tốc độ xử lý, giảm giật lag, tiết kiệm bộ nhớ/pin | `perf(weather): cache kết quả 30 phút` |
| `test` | Testing (Kiểm thử) | Thêm hoặc sửa test | `test(midea): thêm mã mẫu thư viện` |
| `build` | Build System | Đổi hệ thống build hoặc thư viện ngoài (Gradle, pub) | `build: nâng google_sign_in lên v7` |
| `ci` | Continuous Integration | Đổi cấu hình CI/CD (GitHub Actions) | `ci: thêm workflow chạy flutter test` |
| `chore` | Chore (Việc vặt) | Thay đổi lặt vặt không đụng mã chính (`.gitignore`, icon) | `chore: cập nhật .gitignore cho Android Studio` |
| `revert` | Revert (Hoàn tác) | Quay lại một commit trước đó | `revert: hoàn tác "feat(ui): thêm dark mode"` |

Phạm vi gợi ý: `proto`, `ui`, `db`, `sync`, `weather`, `android`, hoặc tên giao thức (`lg`, `gree`, `midea`...).

Quy tắc:

| Nên | Không nên |
|---|---|
| Mỗi commit một thay đổi có ý nghĩa, chạy được | Gộp nhiều việc không liên quan vào một commit |
| Sửa `AGENTS.md` trong cùng commit với mã | Commit `AGENTS.md` riêng sau đó |
| Thay đổi phá tương thích (đổi cấu trúc DB, đổi tên enum) ghi thêm dòng `BREAKING:` ở thân commit | Đổi cấu trúc dữ liệu mà không nói gì |
| Dùng thân commit (cách dòng trống) để giải thích lý do khi cần | Viết mô tả mơ hồ: `update`, `fix bug`, `sửa lỗi` |
| Tham chiếu issue ở cuối: `Closes #12` | Commit file build, khóa ký, file tạm |

**Trước khi commit**
1. `flutter test` phải qua.
2. `flutter analyze` không có lỗi mới.
3. `git status` kiểm tra không có file lạ hoặc file bí mật.

**Không đưa lên GitHub** (thêm vào `.gitignore`):
```
android/key.properties
android/local.properties
*.jks
*.keystore
```
Không commit mật khẩu, khóa ký, file `.env`. `google-services.json` và `firebase_options.dart` chỉ chứa khóa định danh công khai nên commit được, nhưng bảo mật dữ liệu phải dựa vào quy tắc Firestore, không dựa vào việc giấu file. Nếu repo công khai, cân nhắc đặt giới hạn cho API key trong Google Cloud Console.

**Quy trình**
```
git switch main
git pull
git switch -c feat/ten-viec
# ...sửa, test...
git add <file>
git commit -m "feat: mô tả"
git push -u origin feat/ten-viec
```
Mở Pull Request vào `main`, mô tả: làm gì, đã test thế nào (máy nào, giao thức nào), ảnh chụp nếu đổi giao diện. Tự xem lại phần thay đổi trước khi merge, dùng **Squash and merge** để lịch sử gọn. Merge xong xóa nhánh.

**Phiên bản**
- Đánh tag khi có mốc dùng được: `git tag v0.3.0` rồi `git push --tags`. Số phiên bản trong `pubspec.yaml` (`version:`) phải khớp.
- Tag thấp nhất cho bản đã thử trên điều hòa thật; ghi rõ máy nào đã xác nhận.

**Làm việc với AI**
- Bảo AI đọc `AGENTS.md` trước. Mỗi phiên AI làm trên nhánh riêng, không commit thẳng `main`.
- Đọc `git diff` trước khi commit phần AI viết. Mã AI viết không biên dịch trong môi trường của nó, nên chỉ coi là xong khi bạn đã chạy `flutter test` và `flutter run`.

## Kiểm thử

```
flutter test
```
Các bài test so từng byte với mã mẫu của thư viện IRremoteESP8266 (Midea, TCL, Samsung), kiểm tổng kiểm và độ dài khung cho Daikin, Panasonic, Gree và lệnh tắt của LG, Coolix.

## Đổi tên và icon

- Tên hiển thị: sửa `android:label` trong `AndroidManifest.xml`.
- Icon: đặt `icon.png` và `icon_foreground.png` vào `assets/icon/`, khai báo mục `flutter_launcher_icons` trong `pubspec.yaml`, rồi chạy `dart run flutter_launcher_icons`.

## Xử lý sự cố

| Hiện tượng | Cách xử lý |
|---|---|
| "IR: KHÔNG" | Điện thoại không có đèn IR, hoặc đang chạy trên emulator |
| Điều hòa không phản ứng | Hướng đèn IR (đầu máy) về điều hòa, đứng gần. Chạy Dò tự động, thử từng giao thức |
| Build báo `different roots` | Thêm `kotlin.incremental=false` vào `android/gradle.properties` |
| Báo cần Developer Mode | Bật Developer Mode trong Windows Settings |
| Đăng nhập Google không phản hồi, log `INVALID_CERT_HASH` | Thêm SHA-1 vào Firebase, tải lại `google-services.json` |
| Thẻ báo "Firebase chưa sẵn sàng" | Chạy lại `flutterfire configure`, kiểm tra plugin `google-services` |
| `flutter` hoặc `flutterfire` không nhận ra trong PowerShell | Dùng `dart pub global run flutterfire_cli:flutterfire configure` |

## Hạn chế và hướng phát triển

- Chưa có: điều khiển TV, hẹn giờ, thông báo nhắc nhở, điều khiển từ xa qua internet.
- Dữ liệu thời tiết từ Open-Meteo là dự báo theo mô hình, không phải đo tại nhà.

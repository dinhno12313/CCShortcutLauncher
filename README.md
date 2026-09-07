# CCShortcutLauncher 1.6.0

Control Center module cho iOS 16 và iOS 17 (rootless). Settings tải thủ công danh
mục My Shortcuts; mỗi module giữ danh sách Shortcut riêng. Tap module có nhiều
Shortcut thì hiện popup để chọn, module chỉ có một Shortcut thì chạy thẳng.
Mọi trường hợp đều chạy nền, không đưa app Shortcuts lên foreground.

## Cài đặt nhanh

Thêm repo sau vào Sileo rồi cài **CCShortcutLauncher**:

```text
https://dinhno12313.github.io/
```

[Add to Sileo](sileo://source/https://dinhno12313.github.io/)

Package release trực tiếp cũng có tại
[GitHub Releases](https://github.com/dinhno12313/CCShortcutLauncher/releases/tag/v1.6.0).

## Chức năng

- Nhiều module Control Center 1×1 thông qua CCSupport, mặc định 2, tối đa 8.
  Mỗi module có danh sách Shortcut và tên riêng.
- Giao diện cài đặt và menu chọn Shortcut hỗ trợ **Tiếng Việt / English**;
  mặc định là Tiếng Việt và có thể đổi ngay trong trang cài đặt của tweak.
- Module chỉ chứa đúng một Shortcut sẽ chạy ngay khi tap, không hiện popup, và
  lấy luôn glyph của Shortcut đó làm icon trong Control Center.
- Mỗi module có trang cấu hình riêng ngay trong **Settings → Control Center**,
  ngoài đường vào cũ ở **Settings → CCShortcutLauncher**.
- Cache tên, workflow UUID, glyph và màu icon của toàn bộ Shortcut. Cache tự
  cập nhật: resolver theo dõi `Shortcuts.sqlite` và nạp lại vài giây sau khi
  bạn tạo, đổi tên hay xóa Shortcut. Nút **Load My Shortcuts** giờ chỉ để ép
  nạp lại thủ công.
- Màn hình quản lý của từng module có phần đã thêm với nút trừ/tay nắm kéo và
  phần chưa thêm với nút cộng, sắp xếp theo tên.
- **Load My Shortcuts** chỉ cache danh mục, không tự thêm Shortcut nào vào
  module. Người dùng tự chọn.
- Trang quản lý và popup hiển thị icon đã đọc từ `ZSHORTCUTICON`; glyph được
  dựng qua `WFWorkflowIcon`/`WFWorkflowIconDrawer` của framework Shortcuts
  giống chính ứng dụng. CoreText và icon chung chỉ còn là fallback an toàn.
- Module có một Shortcut tự dùng icon của Shortcut. Module có nhiều Shortcut
  có thể chọn một trong 44 glyph đơn sắc; khi chưa chọn, cả hai trang Settings
  và nút Control Center cùng dùng glyph lưới mặc định.
- Bundle có icon riêng trong danh sách thêm module tại **Settings → Control
  Center**.
- Tap module để mở action sheet chứa danh sách đã cache.
- Chọn một hàng để chạy Shortcut tương ứng.
- Gọi `WFSpringBoardWorkflowRunnerClient` để chạy trong nền.
- Đọc lại cache sau mỗi lần tap, không cần respring sau khi tải lại danh mục.
- Chặn tap lặp trong khi workflow trước vẫn đang chạy.
- Theo dõi workflow đến khi hoàn tất, kể cả Shortcut chạy lâu hơn 60 giây.
- Không gọi `shortcuts://` và không fallback sang app Shortcuts.
- Rung phản hồi ngay lúc tap module. Bật/tắt và chọn độ mạnh (Nhẹ / Vừa / Mạnh)
  ở **Settings → CCShortcutLauncher → RUNG PHẢN HỒI**; mặc định bật, độ mạnh
  Vừa. Rung phát đúng thời điểm chạm, trước cả khi Shortcut chạy hay popup mở,
  vì Shortcut chạy nền không để lại dấu hiệu nào trên màn hình.

## Kiến trúc

`cslresolved` là LaunchDaemon chạy dưới user `mobile`. Nó có entitlement giới
hạn cho vùng lưu trữ Shortcuts và chỉ mở `Shortcuts.sqlite` ở chế độ read-only.
Sau khi khởi động, daemon đọc database một lần rồi đặt kqueue watcher (qua
`DISPATCH_SOURCE_TYPE_VNODE`) lên thư mục Shortcuts và lên chính file database.
Mỗi lần có thay đổi, nó gộp sự kiện trong 3 giây rồi đọc lại, lưu mảng
`ShortcutsCatalog` gồm tên, UUID, `iconGlyph` và `iconColor`. Nếu catalog mới
giống hệt catalog cũ thì không ghi prefs.

Module không mở database; nó chỉ tạo popup từ cache. Module được CCSupport nạp
qua provider bundle để provider trả trực tiếp settings icon cho danh sách
Control Center. Lần đọc tự động thất bại (ví dụ chưa mở khóa lần đầu sau khi
khởi động máy) chỉ ghi log, giữ nhịp 30 giây cho bốn lần tải đầu, rồi thử lại
sau 60 giây và mỗi 120 giây cho tới khi thành công; nó không ghi trạng thái
lỗi đè lên UI.

## Dependencies

Máy build:

- Theos và iPhoneOS 16.5 SDK; deployment target iOS 16.0.
- Header/stub CCSupport, ControlCenterUIKit và Preferences.
- `libsqlite3`, clang, make và `ldid`.

iPhone:

- iOS 16.0 - 17.3.1 và jailbreak rootless (Dopamine, palera1n...).
- CCSupport 1.3.11 trở lên (`com.opa334.ccsupport`).
- PreferenceLoader (`preferenceloader`).

## Build

```sh
cd CCShortcutLauncher
export THEOS=/path/to/theos
./scripts/check-build-env.sh
make clean package FINALPACKAGE=1
```

## Cài đặt

Chép package vào `/var/mobile/`, sau đó:

```sh
sudo dpkg -i '/var/mobile/com.dinhnguyenx.ccshortcutlauncher_1.6.0_iphoneos-arm64.deb'
sudo sbreload
```

Post-install script tự load resolver daemon. Sau đó:

1. Vào **Settings → CCShortcutLauncher**.
2. Chọn **Ngôn ngữ** nếu muốn đổi từ Tiếng Việt sang English.
3. Bấm **Tải phím tắt của tôi** và ghi lại số lượng báo về.
4. Dùng nút **− / +** ở **Số mô-đun** nếu muốn khác 2.
5. Vào **Settings → Control Center** và thêm các module **CCShortcutLauncher**.
6. Tap từng module trong danh sách đó để chọn Shortcut, đổi thứ tự, đổi tên.
7. Mở Control Center rồi tap module. Module nhiều Shortcut hiện popup đúng thứ
   tự đã sắp; module một Shortcut chạy ngay.

## Log chẩn đoán

```sh
idevicesyslog -m '[CCShortcutLauncher]' --no-colors
```

Đường chạy thành công:

```text
[CCShortcutLauncher][Resolver] CATALOG_REQUESTED
[CCShortcutLauncher][Resolver] CATALOG_LOADED count=... skipped=... icons=... completeIcons=... synchronized=1
[CCShortcutLauncher][Background] START_SENT name="Tên Shortcut" workflowID=...
[CCShortcutLauncher][Background] RUNNING name="Tên Shortcut"
[CCShortcutLauncher][Background] FINISHED_OBSERVED name="Tên Shortcut"
```

## Giới hạn

- Trên iOS 16.1, presenter của module được tìm qua runtime có kiểm tra;
  các exception đồng bộ được chặn trước khi thoát khỏi module.
- Catalog lọc `ZTOMBSTONED` và `ZHIDDENFROMLIBRARYANDSYNC` khi schema hỗ trợ.
- Cấu hình lưu UUID theo thứ tự cho từng module; Shortcut mới tải thêm không tự
  chen vào danh sách đã chọn.
- CCSupport chỉ hỏi provider một lần mỗi process, nên SpringBoard có thể giữ
  danh sách module cũ. Tweak bắn `com.opa334.ccsupport/ReloadProviders` khi mở
  Settings và khi đổi cấu hình để SpringBoard nạp lại, không cần respring. Nếu
  module vẫn không hiện thì respring.
- Bản cũ nâng cấp lên giữ nguyên module đã đặt trong Control Center vì module
  đầu tiên dùng lại identifier cũ.
- Bản 1.3.x không chọn gì thì mặc định popup hiện toàn bộ Shortcut. Từ 1.4.0
  mặc định là rỗng; lựa chọn cũ đã lưu sẽ được chuyển vào module đầu tiên.
- Popup chưa có thanh tìm kiếm; danh sách dài dùng khả năng cuộn của action sheet.
- Shortcut trùng tên được đánh số theo thứ tự để phân biệt, không hiển thị UUID.
- Shortcut yêu cầu UI, mở khóa hoặc cấp quyền mới vẫn có thể cần tương tác.
- WorkflowKit là private API của iOS. Package giới hạn firmware ở `>= 16.0`
  và `<< 17.4`: đã chạy được tới 17.3.1, từ 17.4 trở lên chưa kiểm chứng nên
  không mở.
- Watcher chỉ chạy khi daemon còn sống. Nếu catalog lệch thực tế, bấm
  **Load My Shortcuts** để ép nạp lại.
- Cache cũ không có metadata icon sẽ dùng icon dự phòng cho tới lần nạp lại
  kế tiếp.

## Gỡ bỏ

```sh
sudo dpkg -r com.dinhnguyenx.ccshortcutlauncher
sudo sbreload
```

Preremove script unload resolver daemon trước khi gỡ file.

## License

CCShortcutLauncher được phát hành theo [MIT License](LICENSE).

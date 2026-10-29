# PlanBlindBox · Flutter 可视化 Step 6.1

这是独立的 Flutter 前端源码包，不会覆盖你的 Spring Boot `PlanBlindBox` 后端。

## 本阶段实现

- **真实首页**：日期、今日完成率、金币/经验/水滴、今日任务和习惯。
- **排序切换**：`GET /today?userId=1&sort=time|importance`，使用后端排序结果。
- **任务增量执行**：`POST /tasks/{taskId}/complete?userId=1`，请求体 `{ "actualCount": 本次完成数量 }`。
- **习惯打卡**：`POST /habits/{habitId}/check-in?userId=1`。
- **创建任务**：`POST /tasks`，提供标题、目标次数、重要程度 1～5、难度 1～5、截止时间。
- **创建 DAILY 习惯**：`POST /habits`，使用当前服务端 Today 日期和 `{"type":"DAILY"}`。
- 接口失败显示提示、支持下拉刷新；执行类操作期间禁用按钮，不自动重试非幂等请求。
- **临期提醒**：任务截止前不足 5 小时字体变红；当日逾期显示删除线。这只是前端**展示规则**，还没有逾期弹窗、续时、次日自动结算。

**未实现**：多页面导航、历史分析、登录认证、任务编辑、WEEKLY 习惯创建、按难度奖励、逾期续时/未完成状态、Flutter Web 跨域配置。不要把这些功能当成已经完成。

## 如何在 Windows 上运行

### 1. 安装 Flutter

先按 Flutter 官网安装 Flutter SDK，并完成 `flutter doctor`。本压缩包不含 Flutter SDK，也不含 Android / Windows 平台生成文件。

- 官方说明：https://docs.flutter.dev/install
- IDE 可以继续用 IntelliJ IDEA（需 Flutter/Dart 插件）或 VS Code。

### 2. 创建 Flutter 平台工程

**注意：请把本压缩包解压到一个新目录，千万不要直接放进 Java 后端根目录。**

建议路径：`E:\CODE\code\plan_blind_box_flutter`。

在 PowerShell 中执行：

```powershell
cd E:\CODE\code\plan_blind_box_flutter
flutter doctor
flutter create --platforms=windows,android .
flutter pub get
```

`flutter create` 用来补齐此源码包缺少的 Windows/Android 平台脚手架，不要加 `--overwrite`，否则可能覆盖本包的 `lib/main.dart`。

### 3. 启动后端

确保 `PlanBlindBox` 的 Spring Boot 后端已启动，端口为 `8080`，并且通过 Apifox 验证了：

```text
GET http://localhost:8080/today?userId=1&sort=time
```

### 4A. 在 Windows 桌面运行（最容易调试接口）

```powershell
flutter run -d windows --dart-define=API_BASE_URL=http://localhost:8080 --dart-define=USER_ID=1
```

如果 `flutter doctor` 报 Windows 桌面工具链缺失，需要安装 **Visual Studio 的“使用 C++ 的桌面开发”组件**；它不是 VS Code。

### 4B. 在 Android 模拟器运行

Android 模拟器访问宿主机的 localhost 使用 `10.0.2.2`：

```powershell
flutter devices
flutter run -d <显示的Android设备ID> --dart-define=API_BASE_URL=http://10.0.2.2:8080 --dart-define=USER_ID=1
```

在运行前打开 `android/app/src/main/AndroidManifest.xml`：

1. 在 `<manifest>` 内添加 `<uses-permission android:name="android.permission.INTERNET" />`。
2. 在 `<application>` 标签内增加 `android:usesCleartextTraffic="true"`，允许开发环境用 HTTP。

注意，这只适用于开发环境。发布正式 App 时应使用 HTTPS，并关闭明文流量权限。

### 4C. 实体 Android 手机

不要填 `localhost` 或 `10.0.2.2`，需要电脑局域网 IP（例如 `http://192.168.1.20:8080`），同时确认 Spring Boot 监听网卡、电脑和手机在同一网络、Windows 防火墙允许访问。不要把带 `userId` 参数的无认证服务公开到互联网。

## 自测顺序

```powershell
flutter test
flutter analyze
```

然后在实际页面依次验证：

1. 今日首页显示与 Apifox 相同的任务、习惯和三种资产。
2. 切换 **按时间**、**按重要程度**，观察任务顺序改变。
3. 点击 **新建任务**，设置 importance=5 / difficulty=3，创建后检查 Today 列表。
4. 点击 **记录进度**，填写本次新增次数，核对 `remainingCount`、状态和奖励。
5. 创建 DAILY 习惯，再打卡一次，核对 `checkedInToday` 和资产更新。
6. 同一习惯打卡后按钮应被禁用；网络超时后先刷新，不盲目重试提交。

## 结构

```text
lib/
  main.dart                       Flutter 入口
  config/api_config.dart         后端 URL、测试 userId
  data/today_api.dart            实际 HTTP 接口与错误处理
  models/today_models.dart       Today 响应模型
  theme/app_theme.dart           色彩与主题
  widgets/dashboard_cards.dart   首页卡片组件
  screens
    
test/
  today_models_test.dart
  today_api_test.dart
design_preview.html              静态视觉预览，可直接用浏览器打开（不连接数据库）
视觉预览.png                       用示例数据绘制的视觉草图，非 Flutter 运行截图
```

## 开发边界与已知限制

- `TodayResponse.date` 应继续保持 `yyyy-MM-dd` 字符串。
- Task/ Habit 写入请求必须由现有后端校验，前端校验只是辅助。
- 任务执行和打卡涉及奖励，只在用户确认时发送一次；网络重试前先 GET 查询实际状态。
- 当前后端使用服务器本地日期，前端 `<5小时` 的提示使用设备本地时间；未来需要明确时区配置。
- `userId=1` 只用于个人 MVP 调试，后续登录认证完成后必须从认证上下文获取身份。
- 代码是在未安装 Flutter SDK 的环境中生成的，**没有实际完成 `flutter test`、`flutter analyze` 或模拟器运行验收**。

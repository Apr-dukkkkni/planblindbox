# PlanBlindBox Mobile V1：本地优先改造说明

## 本次改造目标

核心功能不再依赖 Spring Boot / MySQL。任务、习惯、打卡、奖励、资产、盲盒、收藏品、日历、统计和时间记录全部通过 Flutter Repository 访问本地 SQLite。

- Android/iOS：使用 `sqflite`，数据库文件由系统保存在 App 私有目录。
- Edge/Web：使用 `sqflite_common_ffi_web`（SQLite WASM），数据库持久化在浏览器 IndexedDB。
- 在线 Mod、社区、排行榜和跨设备同步暂不实现；后续作为独立在线扩展层接入。
- 本次按“全新开始”处理，不从旧 MySQL 导入数据。

## 主要代码位置

| 文件 | 职责 |
|---|---|
| `frontend/lib/data/local/local_database.dart` | SQLite 初始化、表结构、索引、内置盲盒与蝴蝶图鉴种子数据 |
| `frontend/lib/data/local/local_plan_repository.dart` | 核心业务读写、事务、奖励发放、日历和统计聚合 |
| `frontend/lib/data/local/collectible_assets.dart` | 数据库存储路径到 Flutter 本地图片资源的映射 |
| `frontend/lib/data/today_api.dart` | 今日页本地门面，保留原 UI 使用的方法签名 |
| `frontend/lib/data/habit_api.dart` | 习惯本地门面，支持归档、恢复和历史打卡统计 |
| `frontend/lib/data/shop_api.dart` | 本地商店、盲盒开盒和幂等请求 |
| `frontend/lib/data/collection_api.dart` | 本地图鉴读取 |
| `frontend/lib/data/stats_api.dart` | 本地统计、日历和时间记录 |
| `frontend/lib/main.dart` | 应用启动前初始化本地数据库 |
| `frontend/test/today_api_test.dart` | 本地数据库、任务奖励、习惯打卡、每日签到和盲盒幂等测试 |

## Edge 开发运行

在 Windows PowerShell 中执行：

```powershell
cd E:\CODE\code\PlanBlindBox\frontend
flutter pub get
```

首次使用 Web SQLite 时，执行一次静态文件初始化：

```powershell
dart run sqflite_common_ffi_web:setup
```

该命令会在 `frontend/web` 生成 `sqlite3.wasm` 和 `sqflite_sw.js`。这是 Web SQLite 驱动需要的运行文件，不是额外服务或数据库环境。

然后运行：

```powershell
flutter test
flutter analyze
flutter run -d edge --web-port=3000
```

不再需要：

```text
--dart-define=API_BASE_URL=http://127.0.0.1:8080
```

本地核心功能不需要启动 Spring Boot，也不需要启动 MySQL。

## Web 数据持久化注意事项

1. 固定使用 `http://localhost:3000` 对应的 Edge 浏览器配置文件。
2. 不要随意更换 Web 端口；浏览器 IndexedDB 按源站隔离，不同端口的数据互相独立。
3. 清除 `localhost:3000` 的网站数据会删除当前 Edge 本地测试数据。
4. Edge 数据和 Android 手机上的 SQLite 文件是两份独立数据；跨设备同步属于后续功能。

## 当前本地业务规则

- 业务日仍按凌晨 05:00 切换。
- 任务进度、习惯打卡和奖励流水在同一个 SQLite 事务中提交。
- 任务奖励沿用重要程度、难度等级的金币/经验计算规则。
- 习惯打卡每个业务日唯一，归档和恢复不删除历史打卡记录。
- 每日签到按业务日唯一，重复调用不会重复发放水滴。
- 盲盒扣款、奖励发放、收藏品库存、流水和开盒记录在同一个事务中提交；`requestId` 唯一约束用于幂等。
- 日历和统计直接从业务记录与资产流水聚合，不维护第二份统计缓存。

## 当前不包含

- MySQL 历史数据迁移（本次明确选择全新开始）。
- 坚果云同步、Mod 社区、在线排行榜和用户登录。
- Android 安装包构建；本次仍以 Edge 模拟测试为主。

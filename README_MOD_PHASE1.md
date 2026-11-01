# PlanBlindBox V2 — Mod 平台第一阶段（离线、声明式）

## 安装

此补丁基于 **PlanBlindBox-Mobile-V1-local-first.zip + PlanBlindBox-settings-backup-patch.zip** 的对应设置页面构造。请先备份当前项目：

1. 将 `frontend/lib/services/mod_registry.dart`（新增）、`frontend/lib/screens/mod_management_page.dart`（新增）和 `frontend/test/mod_registry_test.dart`（新增）复制到对应目录。
2. 比较并合并 `frontend/lib/screens/settings_page.dart`：**新增一个 import 和一张 Mod 扩展入口卡片**。如果你已经定制设置页面，请只合并这两个变化，切勿整页覆盖。
3. 在 Edge 中启动 Flutter，从 **我的 → 设置 → Mod 管理器** 进入。
4. 在 **导入 Mod** 选择附带的 `example-mod.json`，勾选“创建任务”权限并安装，然后在“可用任务模板”点击一项并确认创建。

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d edge --web-port=3000
```

## 约束和说明

- **无数据库版本升级**：注册表放在原有 `app_settings` 表的 `mods.registry.v1` 键中，所以现有 JSON 备份、恢复和重置机制自动覆盖它。
- **不依赖 Spring Boot、Redis 或 RabbitMQ**。
- **不会运行第三方代码**：只解释 manifest 的 `taskTemplates` 字段，权限白名单仅允许 `tasks.create`，任务由用户二次确认后通过原有 `TodayApi.createTask` 创建。
- 模板创建的任务在卸载 Mod 后仍然保留；Mod 没有任务历史和资产的读写权限。
- 已安装其他 Mod 依赖的 Mod 不可停用或卸载；同 ID 必须使用更高版本升级。
- 版本 1 是个人使用的受控扩展协议，不具备任意第三方代码执行能力；签名验证、在线发布、Mod 沙箱、依赖版本范围、应用市场、RabbitMQ + Redis 排行榜属于后续阶段。
- Mod 清单的作者身份尚未经过密码学验证，**只能导入你信任的 JSON 文件**。

## V1 Manifest 示例

见 `example-mod.json`。支持字段：

- schemaVersion: 必须为 1
- id: 反向域名形式，例如 `com.example.reading`
- name、description、version (`x.y.z`)
- permissions: 目前只支持 `tasks.create`
- dependencies: 其他已安装且已启用的 Mod ID 列表
- taskTemplates: 标题、备注、目标次数、重要程度、难度

后续阶段建议：**在线 Mod 元数据服务 + 身份与签名验证 → 发布/安装流程 → RabbitMQ 下载事件 → Redis ZSet 排行榜与数据库对账**。在线系统独立部署，离线核心永不依赖它。

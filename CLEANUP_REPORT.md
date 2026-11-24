# PlanBlindBox 旧版数据库与仓储清理报告

**日期：** 2026-11-11  
**基准源码：** 用户上传的 `frontend-current.zip`，并结合上一轮 Frontend Repair Patch  
**范围：** 清理已无外部引用的旧数据库、仓储和旧成长服务；补回 P0-1 共享测试向量。

## 1. 当前主数据访问链路

`main.dart` 导入的是 `lib/data/local/local_database.dart`。当前 API adapters、MOD Store、同步服务和私密仓库也统一导入 `lib/data/local/` 下的数据库及仓储。

主链路保留为：

```text
main.dart
  └─ lib/data/local/local_database.dart
       └─ lib/data/local/local_plan_repository.dart
            ├─ lib/data/*.dart API adapters
            ├─ lib/services/*.dart
            └─ lib/mod_platform/*
```

## 2. 发现的两组遗留实现

### A. `lib/local/` 下的重复数据库和仓储

- `lib/local/local_database.dart`
- `lib/local/local_plan_repository.dart`
- `lib/local/sqflite_web_factory_stub.dart`（上一轮修复补丁新增；如存在一并删除）

依赖扫描显示，旧 Repository 只引用同目录的旧 Database，没有任何其他 `lib/` 或 `test/` 文件引用这两个类。

两套 Database 都使用同一个物理数据库文件名 `plan_blind_box_v1.db`。上传快照中，旧入口 schema v8、主入口 schema v7；上一轮修复补丁把主入口升级到 schema v8。两套入口继续并存会造成维护者误用和 schema 漂移风险。

### B. 早期独立数据库与成长服务

- `lib/data/local_database.dart`
- `lib/local/local_growth_service.dart`

依赖扫描显示：
- 旧 `LocalGrowthService` 是唯一引用 `lib/data/local_database.dart` 的文件；
- 没有任何其他文件引用 `LocalGrowthService`；
- 早期数据库使用 `plan_blind_box_local.db`、schema v1；
- 旧成长服务使用 `user_asset`、`daily_sign_in` 等单数表名；
- 当前主库使用 `user_assets`、`daily_sign_ins`；本地 `dailySignIn()` 已停用，签到由服务端处理。

这四个遗留文件均无活动调用方，且不属于当前主数据访问链路。

## 3. 删除清单

| 文件 | 处理 | 原因 |
|---|---|---|
| `lib/local/local_database.dart` | 删除 | 重复数据库入口，与主库同文件名 |
| `lib/local/local_plan_repository.dart` | 删除 | 仅依赖旧 Database，无外部调用方 |
| `lib/local/local_growth_service.dart` | 删除 | 无外部调用方，依赖早期独立数据库和旧表结构 |
| `lib/data/local_database.dart` | 删除 | 早期 schema v1 数据库，仅被旧 Growth Service 引用 |
| `lib/local/sqflite_web_factory_stub.dart` | 若存在则删除 | 旧目录数据库的条件导入占位文件 |

## 4. 保留清单

以下主实现保留，不做删除或重命名：

- `lib/data/local/local_database.dart`
- `lib/data/local/local_plan_repository.dart`
- `lib/data/local/sqflite_web_factory_stub.dart`

同时保留当前 API adapters、同步服务、私密仓库、MOD Broker、MOD Store 和测试。

## 5. 依赖扫描结果

对上传快照中的 84 个 Dart 文件执行 import/export/part 路径扫描：

- 非遗留文件引用 `lib/local/local_database.dart`：0
- 非遗留文件引用 `lib/local/local_plan_repository.dart`：0
- 非遗留文件引用 `lib/local/local_growth_service.dart`：0
- 非遗留文件引用 `lib/data/local_database.dart`：0

旧文件之间的内部引用随整组文件一并清除。

## 6. Manifest V1 测试夹具修复

用户提供的 `flutter test` 结果为 84 passed、2 failed。两个失败都在 `manifest_v1_validator_test.dart`，原因是仓库根目录缺少：

`mod-spec/conformance/manifest-v1-vectors.json`

P0-1 补丁包原本包含该文件，但用户当前上传的是 frontend 子目录快照，不包含根目录 `mod-spec`。本补丁将 P0-1 中同一份共享向量原样放回项目根目录，不修改 Validator 逻辑或测试预期。

## 7. 清理脚本保护措施

`CLEANUP_LEGACY_LOCAL_STORAGE.ps1`：
- 检查主数据库、主仓储、主 Web stub 和 schema v8；
- 读取 `pubspec.yaml` 的 package 名称；
- 扫描 `frontend/lib` 和 `frontend/test` 的 Dart import/export/part；
- 若发现任何非遗留代码仍引用旧文件，则中止且不删除；
- 只删除明确列出的精确文件；
- 仅当 `lib/local/` 为空时才删除目录；
- 支持 `-WhatIf` 预览。

## 8. 验证边界

当前环境没有 Windows Flutter SDK，没有执行 `flutter analyze` / `flutter test`。请在本机执行：

```powershell
cd frontend
flutter analyze
flutter test
```

最终以本机工具链输出为准。

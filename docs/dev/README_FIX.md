# V2.5 第二阶段最小修复

本补丁只覆盖以下两个文件：

- `../../frontend/lib/data/mod_market_api.dart`：恢复 V2.3 的 `ranking()`，同时保留 V2.5 第二阶段 SHA-256 下载校验。
- `../../mod-server/src/test/java/com/planblindbox/mod/DownloadRateLimiterTest.java`：修正 Mockito 对 Redis `execute` 可变参数的匹配；不修改生产限流代码。

在 `E:\CODE\code\PlanBlindBox` 目录执行：

```powershell
Expand-Archive "$HOME\Downloads\PlanBlindBox-V2.5-phase2-hotfix.zip" "." -Force
cd .\mod-server
mvn clean test
cd ..\frontend
flutter test
```

先备份两个源文件。若测试通过，再按 V2.5 第二阶段原说明进行真实 SHA-256 验收。

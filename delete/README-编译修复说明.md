# Step 5.1 编译修复包

当前错误原因：Step 5.1 的测试源码已合并，但 4 个对应的生产源码文件仍停留在 Step 4 的版本。

本包根目录直接从 `../../../download/PlanBlindBox_Step5_1_%E7%BC%96%E8%AF%91%E4%BF%AE%E5%A4%8D%E5%8C%85/src` 开始，不包含多余的 `PlanBlindBox/` 文件夹。

使用方法（项目根目录：`E:\CODE\code\PlanBlindBox`）：
1. 可先在 IDE 中备份 4 个原文件或使用 Git 查看当前修改。
2. 将本包里的 `src` 文件夹复制/合并到项目根目录；针对这 4 个文件选择覆盖。不要覆盖整个项目目录。
3. 检查 `src/main/java/com/planblindbox/dto/response/TodayResponse.java` 的 `TaskItem` 中有 `importance`、`difficulty` 字段。
4. 检查 `src/main/java/com/planblindbox/service/TodayService.java` 中有 `getToday(Long userId, String sort)`。
5. 执行：`./mvnw.cmd "-Dtest=TodaySortServiceTest,TodaySortControllerTest,TodayServiceTest,TodayControllerTest" test`。
6. 通过后执行：`./mvnw.cmd test`。

注意：本包仅更新 Today 的 4 个 Java 文件，不包含测试文件（此前已拷贝），不涉及数据库及奖励事务。

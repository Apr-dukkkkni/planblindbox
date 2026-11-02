# PlanBlindBox V2.5：隔离数据库的排行榜压测数据生成器

**目标**：先用 **100 个 Mod + 10,000 条下载事件** 做一轮 MySQL 降级性能测试，不直接向现有 `plan_mod_market` 导入假数据。**该生成器只生成 SQL 文件，不会自动连接或修改 MySQL。**

## 1. 使用前的保护

- 保留当前稳定的 `plan_mod_market`、8091 端口和 Redis 6380 不动。
- 本脚本生成的 SQL 第一项操作是 `CREATE DATABASE plan_mod_perf_10k`，**如果数据库已经存在，会报错而不是覆盖**。不要更改 SQL 里的目标库为 `plan_mod_market`。
- 默认创建与 V2.1～V2.5 Flyway V1/V2 **一致**的四张表。写入合成事件和与之对应的 Outbox 行，Outbox 状态 `PUBLISHED` **只是模拟已完成的历史状态**，不能拿来证明 RabbitMQ 真正投递成功。
- 数据在独立库中生成；使用单独的服务端口 **8092**，禁用 Flyway（仅因为这个独立压测库由生成器建表）与 Redis 排行缓存，先专门测试 MySQL 聚合读取性能。
- 请不要将包含数据库密码的脚本加入 Git 仓库。若要彻底清理测试库，请先确认数据库名，再手工执行 DROP；本工具不包含自动删库命令。

## 2. 生成 SQL（Windows PowerShell）

将本 ZIP 解压到：`E:\CODE\code\PlanBlindBox\perf`，然后运行：

```powershell
cd E:\CODE\code\PlanBlindBox\perf
py -3 .\generate_perf_seed.py --mods 100 --events 10000 --db plan_mod_perf_10k --out perf_seed_10k.sql
```

如果没有 `py` 命令，也可以使用 `python .\generate_perf_seed.py ...`。

本步骤不会连接数据库。文件大小约几 MB。

## 3. 在 MySQL 中导入（需有建库权限）

确认机器上有 `mysql` 命令，然后在 PowerShell 中执行：

```powershell
cd E:\CODE\code\PlanBlindBox\perf
cmd /c 'mysql -u root -p < perf_seed_10k.sql'
```

输入你本地的 MySQL 管理员密码。**不要把密码写入命令或发到聊天中**。

如果 `mysql` 命令没有安装到 PATH，可以在 MySQL 自带客户端中使用：

```sql
SOURCE E:/CODE/code/PlanBlindBox/perf/perf_seed_10k.sql;
```

导入脚本会为已存在的 `'mod_app'@'localhost'` 授予测试库的 DML 权限。如果该账户的 host 不是 localhost，需先确认实际用户 host 并单独授予测试库权限；不要修改生产库权限。

**预期 SQL 检查值：**

- `mod_count = 100`
- `download_count = 10000`
- `outbox_count = 10000`
- `missing_outbox = 0`

## 4. 启动只读 MySQL 压测后端（单独窗口）

在配置了真实 `MOD_DB_PASSWORD` 的 PowerShell 窗口执行（不要把密码明文存盘）：

```powershell
cd E:\CODE\code\PlanBlindBox\mod-server
$env:MOD_SERVER_PORT = "8092"
$env:MOD_DB_URL = "jdbc:mysql://localhost:3306/plan_mod_perf_10k?useUnicode=true&characterEncoding=utf8&serverTimezone=Asia/Shanghai"
$env:MOD_DB_USER = "mod_app"
$env:MOD_DB_PASSWORD = Read-Host "MySQL mod_app 密码"
$env:SPRING_FLYWAY_ENABLED = "false"
$env:MOD_RANKING_ENABLED = "false"
mvn spring-boot:run
```

**重要**：这些设置仅用于此终端启动的 8092 实例；本机正常使用的 8091 实例仍保留原配置。压测实例 `MOD_RANKING_ENABLED=false`，因此排行榜走 MySQL 查询；本次不测试真实的 Redis 高速路径、RabbitMQ 或下载写入性能。

若启动报 `Access denied`，检查 SQL 导入时的授权及当前 PowerShell 中 `MOD_DB_PASSWORD`。若报 `Port 8092 was already in use`，检查是否已经启动了另一个 8092 服务。

确认接口：

```powershell
Invoke-RestMethod 'http://127.0.0.1:8092/api/v1/mods/ranking?limit=10' |
  ConvertTo-Json -Depth 5
```

预期返回以 `com.perftest.mod...` 开头的 Mod。

## 5. 运行 k6（约 80 秒）

```powershell
cd E:\CODE\code\PlanBlindBox\perf
docker run --rm -v "${PWD}:/scripts" grafana/k6 run /scripts/ranking-mysql-load.js
```

脚本逐步提升到 50 VUs，每个虚拟用户请求间暂停 0.2 秒，避免在初轮测试就对本机施加无停顿写入压力。记录 `http_req_duration` 的 avg/p95、`http_req_failed`、`http_reqs` 和测试时后端日志。

## 6. 扩容到 10 万条下载事件（新库，不覆盖上一轮）

先验证 1 万条数据的导入和查询正常，再生成新的独立库：

```powershell
py -3 .\generate_perf_seed.py --mods 1000 --events 100000 --db plan_mod_perf_100k --out perf_seed_100k.sql
```

与前面一样导入 SQL。8092 服务重启前将 `MOD_DB_URL` 更换为 `plan_mod_perf_100k` 即可。**不要反复向同一个数据库插入同一批生成的主键**。

## 7. 测试边界

这轮测试的目标是量化**数据规模对 MySQL 排行榜聚合查询的影响**。由于运行于单机 Windows + Docker 环境、是合成数据、不同于真实用户流量，不能据此推断生产环境最大 QPS。测试中的 `PUBLISHED` Outbox 为合成历史状态，不代表通过 RabbitMQ 进行了消息投递。后续下载写入链路应使用另一组 HTTP 压测与独立库，不能用插入 SQL 代替业务流程验证。

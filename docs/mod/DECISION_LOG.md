# 产品决策记录：D-SEC-001

**标题：** 宿主业务 API 与外部网络/外发能力互斥\
**状态：** 已确认\
**确认日期：** 2026-11-09\
**适用范围：** PlanBlindBox MOD V1

## 决策

任何获得 PlanBlindBox 宿主业务 API 的 MOD，无论 API
是只读还是写入，都不得同时拥有外部网络或其他外发/跨 MOD 通道。

宿主业务 API 包括但不限于：

-   `host.data.*.read`
-   `host.tasks.*`
-   `host.habits.*`
-   `host.checkins.*`（如未来加入）

## V1 有效 Profile

  -----------------------------------------------------------------------------------------------------
  Profile                     能力边界
  --------------------------- -------------------------------------------------------------------------
  `standalone_networked`      不拥有任何宿主业务 API；可申请经审核的外部出口能力；网络请求经 Network
                              Gateway 同步 MOD 自有数据

  `standalone_offline`        不拥有宿主业务 API，也不拥有任何外部出口能力

  `host_integrated_offline`   拥有宿主业务
                              API；允许用户授权的只读与有限写入、隔离本地存储；禁止外部网络和外发通道
  -----------------------------------------------------------------------------------------------------

`declarative` 是 Runtime 类型，不是安全 Profile。

## 数据归属

MOD 向 Host API 提交的字段，以及 Host API
返回的结果，均按宿主数据处理。MOD
不得把这些字段或由宿主数据产生的摘要、统计、预测、AI
分析结果同步到开发者服务器。

MOD 自己独立产生的数据（例如农场金币、作物成长、Anki
卡片、健身训练记录）仍属于 MOD 自有数据，可以在 `standalone_networked`
模式下同步。

## 技术执行要求

1.  Manifest 只声明能力请求，不允许开发者声明可信的 `securityProfile`。
2.  平台根据审核批准的权限集合计算 `effectiveProfile`。
3.  `effectiveProfile` 必须写入平台签名的 Store Attestation，并绑定 MOD
    ID、版本、Publisher Key ID、包摘要、批准权限和策略版本。
4.  同一 Manifest 同时请求宿主业务 API 与 `network.fetch`、MOD
    间消息或外部跳转等出口能力时，拒绝该组合。
5.  `host_integrated_offline` 必须在 Runtime
    层阻断所有直接网络请求和其他外发旁路。
6.  Profile
    变化必须创建新的安装实例和存储命名空间；不得把宿主集成离线实例的数据恢复或迁移到联网实例。
7.  撤销宿主权限时，立即终止对应 Runtime Session。

## 设计后果

-   V1 的农场 MOD 如果需要同步自己的云端数据，应使用
    `standalone_networked`，不能同时申请 `host.tasks.create`。
-   如果农场 MOD 需要把任务写入 PlanBlindBox，则该版本必须使用
    `host_integrated_offline`，其 MOD 自有数据只能在本地保存。
-   同一个 MOD 同时需要宿主业务 API
    和自有云同步的场景，留待未来更强的隔离架构评审；V1
    不通过权限例外放行。
-   开发者可以拆分产品功能，但 V1 不允许通过 MOD-to-MOD
    消息把宿主数据转交给联网 MOD。

## 重新评审条件

只有当未来实现了可验证的独立信任域、数据通道隔离、强制信息流控制和跨平台安全测试，并通过单独安全评审后，才可重新讨论同一
MOD 同时访问宿主数据和联网的能力。

# PlanBlindBox MOD Platform Spec Draft 0.1

本目录包含四份 MOD 平台技术规范草案，以及 Manifest JSON Schema 和示例。

## 文件

-   `MOD_PLATFORM_ARCHITECTURE_V1.md`：总体架构、MOD
    Shell、Runtime、生命周期、现有源码基线。
-   `MOD_SECURITY_V1.md`：威胁模型、宿主数据边界、网络隔离、Private
    Vault 安全要求。
-   `MOD_MANIFEST_PACKAGE_V1.md`：Manifest、ZIP、checksums、签名、安装校验和
    CLI。
-   `MOD_PERMISSION_API_V1.md`：权限目录、授权模型、Host Bridge、Network
    API 和服务端路由。
-   `schemas/manifest-v1.schema.json`：Manifest 结构校验草案。
-   `examples/`：独立联网 MOD、宿主集成 MOD、快捷入口 MOD 示例。

## 重要说明

1.  文档状态为 Draft 0.1，不代表功能已经实现。
2.  用户已确认的产品决定与技术建议在文档中分开标记。
3.  Manifest Schema 是工作草案，正式冻结前仍需跨语言测试和安全评审。
4.  当前源码没有 MOD 可执行 Runtime、Capability Broker、Publisher 和 ZIP
    制品分发。
5.  宿主数据读取与网络外发在首期采用互斥安全 Profile。若未来需要同一 MOD
    同时拥有两者，必须先设计并验证更强的隔离架构。
6.  不因 MOD 重构而重置 PlanBlindBox
    的账号、OPAQUE、AMK、私密仓库和核心业务数据。

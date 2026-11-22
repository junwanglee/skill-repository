# performance-diagnosis-java

一个面向 Linux Docker 中 Java 服务的线上性能自主诊断 Skill。按根目录 [`SKILL.md`](SKILL.md) 的流程执行，使用 Arthas 进行 JVM 诊断，并通过现有 SSH 配置连接服务器。

## 使用内容

- `SKILL.md`：入口、工作流、操作分级和硬性安全边界。
- `references/`：SSH/Docker/JVM 兼容性、Arthas 部署、分症状诊断与安全规范。
- `scripts/`：只读的本地 SSH 检查和输入校验辅助脚本。
- `templates/`：环境记录和最终报告模板。

## 前置条件

- 本机 OpenSSH client，以及已由执行人配置并验证的 SSH alias/key。
- 远程 Linux 主机可通过该 alias 连接，且当前 SSH 用户有 Docker 只读诊断所需权限；脚本不会自动 sudo。
- 目标容器运行 Java，且容器/JVM 满足 Arthas Attach 条件。
- 对服务器、容器、JVM PID 分别取得执行人的明确确认。

## 安全与版本

生产默认只读。L1 为低开销只读采集；L2 instrumentation 需限定范围并默认不超过 30 秒；L3 高风险操作在 v1 禁止。只使用容器已有可写临时目录，Attach 临时目录与报告目录分别检查。SSH 私钥不会被读取或复制，密钥配置由执行人自行完成。

Arthas 不自动追踪 `latest`。使用已验证并缓存的固定版本；首次下载时从官方发行源获取并核验 SHA-256，且记录版本和哈希。设计方案未锁定具体 Arthas 版本，因此执行前需在目标 Java 8 环境验证并明确固定版本。

## 本地检查脚本

```bash
scripts/check-local-ssh.sh
scripts/list-ssh-servers.sh
scripts/validate-target.sh --host-alias beta --container-id 0123456789ab --pid 1
```

这些脚本不会连接或改变远端服务；列出的 SSH alias 需要再通过 batch-mode 实际连接确认。远程执行须遵循 Skill 中的逐项确认流程。

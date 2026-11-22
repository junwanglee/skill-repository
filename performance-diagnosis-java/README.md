# performance-diagnosis-java

一个面向 Linux Docker 中 Java 服务的线上性能自主诊断 Skill。按根目录 [`SKILL.md`](SKILL.md) 的流程执行，使用 Arthas 进行 JVM 诊断，并通过现有 SSH 配置连接服务器。

## 使用内容

- `SKILL.md`：入口、工作流、操作分级和硬性安全边界。
- `references/`：SSH/Docker/JVM 兼容性、Arthas 部署、分症状诊断与安全规范。
- `scripts/`：本地 SSH 配置检查、Arthas 下载缓存、任务状态台账和受限 L1 批处理脚本。
- `templates/`：环境记录和最终报告模板。
- `references/usage-guide.md`：带端到端示例的使用教程，供 Agent 按需加载。
- `docs/design.md`：原始详细设计方案，仅作历史背景和追溯依据；当前行为以 `SKILL.md` 为准。

## 前置条件

- 本机 OpenSSH client，以及目标服务器的 SSH alias；支持本地交互式密码认证或密钥认证。
- 远程 Linux 主机可通过该 alias 连接，且当前 SSH 用户有 Docker 只读诊断所需权限；脚本不会自动 sudo。
- 目标容器运行 Java，且容器/JVM 满足 Arthas Attach 条件。
- 服务器、容器、Java 服务/PID 分三次编号选择，每轮只询问当前项；PID 选择即完成目标确认，不再增加重复的第四次确认。
- 症状只在用户未提供主症状时询问，且不与目标选择合并。

## 安全与版本

生产默认只读。L1 为低开销只读采集；L2 instrumentation 需限定范围并默认不超过 30 秒；L3 高风险操作在 v1 禁止。只使用容器已有可写临时目录，Attach 临时目录与报告目录分别检查。SSH 密码由本地 OpenSSH 提示符接收，不进入 Skill；SSH 私钥不会被读取或复制。

V1 固定 Arthas 4.3.5，首次使用时由 `scripts/prepare-arthas.sh` 从官方启动包地址下载到本地版本缓存，检查 JAR 内版本并记录 SHA-256；后续使用缓存副本并校验其未变化。该摘要记录首次 HTTPS 下载的文件，不是独立发布者签名。Arthas 批处理使用 `as.sh -f <script> <pid>` 等价方式，L1 外层超时最多 30 秒，批处理命令必须明确次数上限。Arthas 会话和 profiler 在清理时分别停止并验证。

## 本地检查脚本

```bash
scripts/check-local-ssh.sh
scripts/list-ssh-servers.sh
scripts/validate-target.sh --host-alias beta --container-id 0123456789ab --pid 1
scripts/arthas-task.sh status --task-id PD-20261122-220000
```

新增服务器时运行交互式向导，避免逐条手动输入初始化命令：

```bash
scripts/setup-ssh-server.sh
```

向导默认支持首次交互式密码登录（密码由本地 OpenSSH 提示，不会被脚本捕获），也可选择密钥登录。脚本会把新 Host 块追加到本机 `~/.ssh/config` 并保留原有内容；存在 `Host *` 时会拒绝写入，且不会覆盖重名 alias 或自动向远端安装公钥。详见 [`references/ssh-management.md`](references/ssh-management.md)。

`list-ssh-servers.sh` 只解析本机配置，从不探测网络。只有服务器选择后才连接；密码只输入本地 OpenSSH 提示符。新建 alias 会配置短期 ControlMaster；已有 alias 需检查有效配置是否支持连接复用。远程诊断须遵循 Skill 的逐项确认流程。

Arthas 准备脚本会在本地缓存缺失时自动下载，单独准备可运行：

```bash
scripts/prepare-arthas.sh
```

Arthas L1 批处理示例（省略 `--arthas-boot` 时自动准备/复用本地缓存）：

```bash
scripts/arthas-batch.sh --java /path/to/java --pid 123 --timeout 20 --commands 'dashboard -n 1;thread -n 10;jvm;memory;version'
```

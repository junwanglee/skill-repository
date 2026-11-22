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
- 先选择服务器，再选择排查方向；之后逐步选择容器、Java 服务/PID 和诊断方法。
- 优先使用客户端原生选项控件；纯文本场景接受选项名称，不要求手动输入编号。
- 持续采样时由执行者选择时长和间隔；L2 profiler 仍需单独明确批准。

## 安全与版本

生产默认只读。L1 为低开销只读采集；L2 instrumentation 需限定范围，profiler 默认 20 秒、单次最多 5 分钟（300 秒），不得拆分任务规避上限；L3 高风险操作在 v1 禁止。只使用容器已有可写临时目录，Attach 临时目录与报告目录分别检查。SSH 密码由本地 OpenSSH 提示符接收，不进入 Skill；SSH 私钥不会被读取或复制。

V1 固定 Arthas 4.3.5，首次使用时由 `scripts/prepare-arthas.sh` 从官方启动包地址下载到本地版本缓存，检查 JAR 内版本并记录 SHA-256；后续使用缓存副本并校验其未变化。该摘要记录首次 HTTPS 下载的文件，不是独立发布者签名。CPU profiler 默认采样间隔 10 ms，可选择 20/50 ms；总时长默认 20 秒、执行者可选择最长 5 分钟。容器内存使用达到 limit 的 80% 或近期发生 OOM 时不执行 profiler。L1 外层超时最多 30 秒，批处理命令必须明确次数上限。Arthas 会话和 profiler 在清理时分别停止并验证。

Profiler 默认同时生成 AI 易读的 `profile.md`（热点与调用树）和可视化 `flamegraph.html`；Markdown 便于模型检索/归纳，HTML 便于人交互查看。最终报告须将热点映射到具体类、方法和可验证的源码位置，并给出带优先级、取舍和验证方式的优化建议；没有源码时须明确列出待核实的方法/调用栈，不得编造文件或行号。

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

`list-ssh-servers.sh` 只解析本机配置，从不探测网络。只有服务器选择后才连接；若 ControlMaster 已存在就直接复用，只在不存在或过期时需要本地 OpenSSH 密码登录。新建 alias 的连接空闲 1 小时后过期；已有 alias 以 `ssh -G <alias>` 显示的 `ControlPersist` 为准。远程诊断须遵循 Skill 的逐项确认流程，所有面向执行者的交互使用中文。

Arthas 准备脚本会在本地缓存缺失时自动下载，单独准备可运行：

```bash
scripts/prepare-arthas.sh
```

Arthas L1 批处理示例（省略 `--arthas-boot` 时自动准备/复用本地缓存）：

```bash
scripts/arthas-batch.sh --java /path/to/java --pid 123 --timeout 20 --commands 'dashboard -n 1;thread -n 10;jvm;memory;version'
```

本地 Arthas 缓存位于 `~/.performance-diagnosis/arthas/versions/4.3.5/`。原始监测数据、环境记录和报告保存在 `~/.performance-diagnosis/diagnostics/<host>/<container-id>/<task-id>/`。远程临时文件放在目标主机/容器已有可写的 `/tmp/pd-<task-id>/`；开始采样前 Skill 会向执行者展示实际使用路径。

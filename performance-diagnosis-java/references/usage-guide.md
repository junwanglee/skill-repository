# Java Docker 线上性能诊断使用教程

本文以“`beta` 服务器上的 `order-service` 容器 CPU 持续偏高”为例，说明如何使用 `performance-diagnosis-java` Skill 完成一次受控诊断。示例中的主机名、容器名、PID、路径和输出均为虚构值；执行前必须以实际环境为准。

## 1. Skill 能做什么

Skill 使用 SSH 连接 Linux Docker 主机，确认容器和 JVM 后，通过 Alibaba Arthas 采集 JVM 证据，并结合 Docker/Linux 资源信息形成报告。适用问题包括：

- CPU 使用率高
- 接口响应慢
- 内存使用异常
- GC 频繁或停顿
- 线程阻塞或死锁
- 暂不确定原因的综合诊断

入口说明见 [`../SKILL.md`](../SKILL.md)，设计原文见 [`../docs/design.md`](../docs/design.md)。本教程用于说明产品工作流；示例中的命令和确认语句不是独立授权，执行时仍须遵守 `SKILL.md` 的安全边界。

## 2. 开始前的准备

1. 本机已安装 OpenSSH，并为目标服务器准备 SSH alias；可以使用密钥认证，也可以首次连接时通过本地终端交互输入账户密码。
2. 目标主机可通过 SSH 连接；首次连接的 Host Key 已按组织流程核实/接受。
3. SSH 用户具有所需 Docker 查询权限。Skill 不会自动执行 `sudo`。
4. 确认诊断窗口和生产变更/观测流程，避免在发布、扩缩容或其他高风险操作期间产生混淆。
5. 不要将私钥、密码或 token 发给 Agent。

本地辅助检查：

```bash
cd performance-diagnosis-java
scripts/check-local-ssh.sh
scripts/list-ssh-servers.sh
```

`list-ssh-servers.sh` 只解析本地 SSH 配置，不连接任何服务器，所以列表状态是“未测试”。只有你选择某台服务器后才建立连接；需要密码时，在本地 OpenSSH 提示符输入。

如果尚未配置服务器，Agent 提供两种方式，最终都会把配置记录到本机 `~/.ssh/config`：

**方式 A：逐项问答。** Agent 每轮只问一个字段，收到回答后再问下一个，不一次要求你填整张表：

```text
Agent：服务器别名叫什么？
你：beta
Agent：服务器 IP 或域名是什么？
你：172.26.159.208
Agent：SSH 用户名是什么？
你：lijunwang
Agent：SSH 端口使用默认 22 吗？
你：是
Agent：使用密码登录还是 SSH key？密码只在本机终端输入。
你：密码
```

随后 Agent 调用脚本并把 Host 块记录到本机 SSH 配置。

**方式 B：一条命令。** Agent 把需要的值填入命令，让执行人复制运行：

```bash
!bash ~/.claude/skills/performance-diagnosis-java/scripts/setup-ssh-server.sh --alias beta --host 10.20.1.15 --user deploy --port 22 --auth password
```

脚本检查 alias 未重复及 `Host *` 冲突后，将新 Host 块追加到本机 `~/.ssh/config`，保留既有配置并设置文件权限为 `600`，随后用 `ssh -G` 校验有效值。旧版本留下的同名片段会保留，但不会阻止写入。完成后 alias 会被服务器列表脚本发现。密码只输入本地 OpenSSH 提示符，不提供给 Agent。新建密码 alias 会配置 1 小时连接复用；只在连接复用不存在或已过期时，Agent 才请你在本地终端运行 `ssh beta true` 输入一次密码。诊断结束后连接保持到 1 小时空闲期满；如需立即关闭，可运行 `ssh -O exit beta`。已有 alias 的有效时长以 `ssh -G beta` 为准。密钥模式可用 `--auth key --public-key ~/.ssh/id_ed25519.pub`；脚本只展示公钥，不上传，也不读取私钥内容。

如果直接在本地终端运行（有 TTY），也可不传参数启动向导：

```bash
bash ~/.claude/skills/performance-diagnosis-java/scripts/setup-ssh-server.sh
```

如果 `!bash` 不带参数运行，脚本会打印用法并明确报错，不会静默退出。非交互一条命令示例不包含密码；不要把密码写到命令行、聊天或脚本参数中。

## 3. 发起一次诊断

向 Agent 描述问题、目标服务和可观察到的现象。例如：

> 请使用 `performance-diagnosis-java` Skill，排查 beta 环境 `order-service` 的 CPU 使用率从 14:20 开始持续在 85% 以上的问题。先做低开销检查；如需 profiler，默认 20 秒，最长 5 分钟，由我选择时长。不要执行会修改生产状态的操作。

好的请求可以提供：

- SSH alias 或环境名称
- 服务/容器名称（作为候选，不等于已确认目标）
- 问题类型、开始时间、是否仍在发生
- 影响范围或相关接口
- 允许的诊断时间窗口和组织内要求

不要在请求中提供密码、token、私钥或完整环境变量。首次密码认证时，密码只输入 OpenSSH 在本地终端显示的提示符，不要输入聊天框或 Skill 表单。

## 4. 按步骤选择

### 4.1 选择服务器

Agent 应列出本机 `~/.ssh/config` 中的目标，即使 Host 是 IP 也要作为可选项，例如：

| 选项 | Alias | Host | User | Port | 状态 |
|---:|---|---|---|---:|---|
| 1 | beta | 10.20.1.15 | deploy | 22 | 未测试 |
| 2 | staging | 10.20.2.18 | ops | 2222 | 未测试 |

在支持原生选项控件的客户端中，直接点选 `beta` 或 `staging`；纯文本客户端可以回复选项名称（如“beta”），不必输入编号。

即使只有一个候选，也应明确选择。连接始终复用 alias，以保留 SSH 配置中的 ProxyJump、端口和 IdentityFile 等设置。

### 4.2 选择排查方向

服务器选择后，Agent 再展示排查方向。若你一开始已经描述“CPU 持续偏高”，该选项会标为推荐项，但 Agent 仍应询问你是否采用，或改选其他方向：

- CPU 偏高
- 接口变慢/超时
- 内存上涨/OOM
- GC 频繁/停顿
- 线程阻塞/卡死
- 不确定，先查看基线

点选方向，或在纯文本客户端回复方向名称。选择后 Agent 才连接服务器。若服务器未配置，先完成 SSH 配置向导，再回到服务器选择。

### 4.3 选择容器

服务器确认后，Agent 先列出该主机所有运行中的容器（此时不检查容器内部进程），展示可选项：

| 选项 | 容器名 | 容器 ID | 镜像 | 状态 |
|---:|---|---|---|---|
| 1 | order-service | `a1b2c3d4e5f6` | `company/order:2026.11` | Running |
| 2 | billing-worker | `b2c3d4e5f6a1` | `company/billing:4.2` | Running |

你选择一个容器：

> `order-service`

Agent 必须等你选择后才查看该容器的进程。一次只诊断一个容器。

### 4.4 选择 JVM PID

选中容器后，Agent 列出其中识别到的 Java 服务/PID 作为可选项，例如：

```text
1. order-service.jar — PID 1 — Java 1.8.0_402 — UID:GID 10001:10001
2. metrics-agent — PID 32 — Java 1.8.0_402 — UID:GID 10001:10001
```

Agent 展示 Java 服务/PID 候选。使用原生选项控件点选服务；纯文本时回复服务名或 PID。这个选择就是目标确认，Agent 简要复述目标后直接检查兼容性，不重复询问同一组信息：

> `order-service.jar`，PID 1

即使只有一个 JVM，也必须显示选项并等待选择。若容器重启、ID 或 PID/进程身份变化，当前任务停止并重新列出受影响阶段的选项。

### 密码输入位置

密码不要发在聊天里。选择服务器后，Agent 先检查 `ssh -O check beta`。如果已有 ControlMaster，就直接复用，不再让你运行登录命令；只有 master 不存在/过期时，才给出 `! ssh beta true`。在本机终端执行后，OpenSSH 会显示密码提示；直接在该提示中输入即可，内容通常不会回显。同一 master 默认保持至配置的空闲期结束。新建 alias 为 1 小时；你当前的 beta 配置若 `ssh -G beta` 显示 `controlpersist 600`，则仍是 10 分钟。可在本机 `~/.ssh/config` 的 beta 主机块中将 `ControlPersist 600` 改为 `ControlPersist 1h`。若出现 `Permission denied`，不要反复尝试；先核对用户名、密码和服务器授权，避免账号锁定。

## 5. 选择诊断方法、采样时长和输出位置

通过兼容性检查后，若本机没有 Arthas 缓存，准备脚本会自动从官方启动地址下载 4.3.5、核对 JAR manifest 版本并缓存：

```bash
scripts/prepare-arthas.sh
```

普通诊断时，`arthas-batch.sh` 在未指定 `--arthas-boot` 时会自动调用准备脚本。首次下载记录的 SHA-256 用于之后检查本地缓存是否变化，不是独立的发布者签名。

Attach 前，Agent 应检查 Linux/架构、Java 版本和路径、JVM 用户、PID namespace、Attach 能力、容器资源限制，以及临时目录和报告输出能力。Attach 运行目录与报告文件目录要分开确认。检查后，Agent 先给出本次可选的排查方法，说明推荐项和每项可能产物，例如：

| 选项 | 方法 | 适用情况 | 影响与产物 |
|---|---|---|---|
| L1 基线（推荐） | 低开销快照 | 先确认当前是否仍异常 | 主机/容器/JVM 快照和线程列表 |
| L1 持续采样 | 问题间歇发生、当前快照未复现 | 周期性采集线程/CPU；按执行者选择时长和间隔 |
| L2 profiler 热点分析 | L1 证据指向 JVM 计算热点，且采样时负载正在发生 | 有界插桩；优先生成 AI 易读 Markdown，HTML 火焰图可视化；需单独明确批准 |
| L2 定向 trace/monitor | 已知具体类/方法，需要看耗时或调用次数 | 定向插桩；输出方法级记录；需单独明确批准 |

Agent 应按症状删去不适用项或替换为对应方法（例如 GC、内存、线程分析），并给出推荐理由。你在原生选择控件中点选；纯文本时回复方法名称。方法选择本身不等于 L2 批准。

选择持续采样后，Agent 分两轮询问，先选时长并暂停，再选采样间隔并暂停。建议选项：

- 时长：1 分钟（推荐）、3 分钟、5 分钟、10 分钟，或在上限内自定义。
- 间隔：5 秒、10 秒（推荐）、30 秒。

CPU profiler 的默认采样间隔是 10 ms（每秒约 100 次采样），与总采样时长不是一回事。你可以选择 10 ms（常规细节）、20 ms 或 50 ms；间隔越长，采样次数和开销越低，但细节会减少。Arthas 以纳秒参数传递该间隔，例如 20 ms 为 `-i 20000000`。总采样时长默认 20 秒，可选择 1、3 或 5 分钟，也可自定义不超过 300 秒的值。不得拆分任务规避单次 5 分钟上限。时长选择后暂停；接着展示目标、方法、间隔、时长、输出路径和停止方案，再单独请求明确批准。不能把“选择某个方法”当成启动 L2 的批准。

Arthas 默认生成 HTML 火焰图，因为它便于浏览器交互查看。Arthas 4.3.5 也支持 `profiler stop --format md` 生成包含热点和调用树的 Markdown，便于 AI 分析。默认优先选择 Markdown；若固定版本能从同一份采样数据安全导出两种格式，可同时保存 Markdown 与 HTML。一个 profiler 任务只能停止/导出一次，不能为了第二种格式重新采样。输出前核验 Arthas 4.3.5 实际支持的格式参数。

若主机或目标容器近期发生 OOM，或目标容器当前内存使用达到 limit 的 80%，默认推荐不运行任何 L2（profiler/trace/watch/monitor），改为 L1 只读检查或等待风险条件解除后重新检查。同时提供“强制启用 L2（承担风险）”选项。选择后，Agent 必须展示实际 OOM/内存证据、具体操作、目标、时长/次数和停止方案，并在单独一轮请求执行者明确确认；普通的“批准 profiler”不等同于风险确认。确认后严格遵守批准范围，并将风险接受、证据及结果记入台账和报告。不得将其描述为消除了风险。Profiler 不与重复 dashboard 采集并行运行。

执行前，Agent 要明确展示保存位置：

- Arthas 启动包缓存：`~/.performance-diagnosis/arthas/versions/4.3.5/arthas-boot.jar`
- 本地采集数据与报告：`~/.performance-diagnosis/diagnostics/<host>/<container-id>/<task-id>/`，包括原始监测数据、`environment.md` 和 `report.md`
- 本地任务状态记录：`~/.performance-diagnosis/tasks/<task-id>.state`
- 远程临时文件：目标主机/容器内已存在且可写的 `/tmp/pd-<task-id>/`

这些本地路径对应运行下载/采集脚本的操作者本机账户。Agent 应确认执行环境能读写该本机目录；若当前运行在隔离容器或路径映射不同，先明确实际本机落盘位置。若实际路径不同，Agent 应报出确切路径，并在开始采样前让你选择继续或取消。

例如：

```text
兼容性：有条件兼容
- Java 8、Linux x86_64
- JVM UID 与诊断进程 UID 一致
- 容器根文件系统只读，但已有 /tmp 可写
- 文本输出可回传；火焰图输出空间尚未确认
计划：先执行 L1；文件型 profiler 暂不启动，直到输出目录验证完成
```

没有 `jcmd` 或 Shell 不一定表示 Attach 必然失败；但目标身份或 Attach 条件无法安全确认时，应停止而不是猜测。

## 6. 示例：CPU 偏高诊断

一个安全的诊断顺序如下：

1. 采集 `uptime`、`free -m`、`docker stats --no-stream`，判断宿主机和容器资源状态。
2. 采集 Arthas `dashboard`，记录 JVM 线程、内存、GC 等基线。
3. 使用 `thread -n 10` 找出 CPU 较高线程，结合线程栈和短间隔重复观察确认现象。
4. 只有证据指向 JVM 热点、容器内存余量安全且输出位置可用，才提供 profiler 方案；建议 20 秒、采样间隔 10 ms。执行者可将采样间隔调到 20 或 50 ms 以降低开销，但会减少细节；总时长可由执行者选择，单次不超过 5 分钟，并需单独批准。
5. 到时停止同一 profiler 任务，确认已停止，再分析热点方法/调用树。
6. 保存原始输出和时间线，回传文件并校验 SHA-256。
7. 只清理本次任务创建的远程临时文件，生成报告。

诊断过程中的示例沟通：

> Agent：L1 显示容器 CPU 配额为 2 核，CPU 使用接近配额。`thread -n 10` 连续两次发现同一业务线程栈集中在 `PriceCalculator.rebuildIndex`。容器内存余量为 35%，未发现近期 OOM。建议 CPU profiler 采样 20 秒，采样间隔 10 ms，优先输出到容器已有的 `/tmp/pd-<task-id>/profile.md`；可视化格式及其安全导出能力已核验。是否批准？
>
> 执行人：批准 CPU profiler 20 秒。

L2 操作应有明确目标、上限和可靠停止方式；同一 JVM 同时最多一个主动采样任务。无法限制或停止时，不执行该操作。

## 7. 其他问题类型的选择

| 现象 | 优先检查 | 可能的深入方向 |
|---|---|---|
| 接口慢 | dashboard、目标线程栈、请求对应方法 | 限定方法的 trace/monitor；区分本地耗时与下游等待 |
| 内存异常 | 容器内存限制、`memory`、`jvm`、GC 变化 | 有界 allocation 采样；分清分配速率与泄漏 |
| GC 频繁/停顿 | dashboard、jvm、memory、已有 GC 日志 | 比较次数、时长、回收前后占用；不启用新 JVM 参数 |
| 阻塞/死锁 | thread 状态、重复线程栈、锁关系 | 核实锁环和持锁线程；WAITING 本身不代表异常 |
| 不确定 | 先做 L1 主机、容器、JVM 基线 | 根据证据选择一个深入方向，不一次跑完所有高开销操作 |

Heap Dump、动态修改类/JVM 参数、重启/停止容器、Kill 进程等 L3 或状态变更操作不由 v1 Skill 自动执行。

## 8. 查看结果

推荐本地目录：

```text
~/.performance-diagnosis/diagnostics/beta/order-service/PD-20261122-142500/
├── 00-summary.md
├── 01-environment.md
├── 02-docker-info.txt
├── 03-jvm-dashboard.txt
├── 04-thread.txt
├── 05-profiler.html
└── diagnosis-report.md
```

实际文件按诊断能力生成，不要求每次都有 profiler 文件。报告至少包含目标身份、诊断时间、命令时间线、证据、根因候选及可信度、具体热点类/方法及源码位置（如可访问）、优化建议和验证方式、未解决问题、附件哈希和清理状态。未经脱敏的 token、密码、密钥不得写入报告。

结论应区分事实和推断。例如，“采样中约 42% 样本位于 `PriceCalculator.rebuildIndex`”是观测；“该方法是 CPU 升高的唯一根因”则需要额外证据支持。

## 9. 异常与停止处理

- **SSH 认证失败：** 停止远端操作，由执行人修复本地凭据/权限后重试。
- **Docker 无权限：** 不 sudo；请管理员按组织流程配置只读诊断权限。
- **多个容器/JVM：** 展示候选并等待明确选择。
- **Attach 失败：** 收集错误和兼容性证据，不自动提权或修改容器。
- **无可写报告目录：** 仅执行可安全 stdout 回传的文本诊断，跳过文件型采样。
- **SSH 中断：** 先核实本任务状态，避免重复启动；确认结束后再清理。
- **文件回传失败：** 保留远端任务文件和校验信息，稍后恢复回传。
- **目标身份变化或清理归属不明：** 停止并报告，不清理可能属于其他会话的资源。

## 10. 完成后检查

- [ ] 服务器、容器、JVM PID 都由执行人确认。
- [ ] L2 任务已停止，持续任务状态已核实。
- [ ] 原始结果和报告已保存到本地。
- [ ] 回传文件大小与 SHA-256 已验证（适用时）。
- [ ] 只清理了当前任务创建的文件。
- [ ] 报告写明限制、不确定性和未执行项。

## 相关文档

- [Skill 入口与约束](../SKILL.md)
- [设计方案原文](../docs/design.md)
- [性能诊断报告模板](../templates/performance-report.md)
- [安全策略](../references/security-policy.md)

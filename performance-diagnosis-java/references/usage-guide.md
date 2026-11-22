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

`list-ssh-servers.sh` 会对 SSH config 中的普通 Host alias 使用 BatchMode 和 5 秒超时做密钥认证检查。未通过可能表示需要交互式密码，也可能表示连接不可用；不要仅凭此结果判定服务器不可达，也不要关闭 Host Key 校验。

如果尚未配置服务器，Agent 应先在对话中依次询问：SSH alias、主机/IP、用户名、端口（默认 22）和认证方式。用户回答后，在 Agent shell 中用参数调用脚本；不要用不带参数的 `!bash` 启动交互式版本，因为 `!` 执行环境通常没有 TTY：

```bash
!bash ~/.claude/skills/performance-diagnosis-java/scripts/setup-ssh-server.sh --alias beta --host 10.20.1.15 --user deploy --port 22 --auth password
```

脚本会在 `~/.ssh/config.performance-diagnosis.beta` 生成供审阅的 SSH 配置片段，不会改写现有 `~/.ssh/config`。Agent shell 没有 TTY 时，密码模式不会尝试连接；请在你自己的终端运行脚本输出的 `ssh -F ...` 命令。密码只输入 OpenSSH 本地提示符，不要提供给 Agent。若要让 alias 出现在后续服务器列表中，需将已审阅的 `Host` 片段加入 `~/.ssh/config`。密钥模式可用 `--auth key --public-key ~/.ssh/id_ed25519.pub`；脚本只显示公钥，不上传，也不读取私钥内容。

如果直接在本地终端运行（有 TTY），也可不传参数启动向导：

```bash
bash ~/.claude/skills/performance-diagnosis-java/scripts/setup-ssh-server.sh
```

如果 `!bash` 不带参数运行，脚本现在会打印 `--help` 用法并明确报错，不会再无输出地退出。

## 3. 发起一次诊断

向 Agent 描述问题、目标服务和可观察到的现象。例如：

> 请使用 `performance-diagnosis-java` Skill，排查 beta 环境 `order-service` 的 CPU 使用率从 14:20 开始持续在 85% 以上的问题。先做低开销检查；如需 profiler，请限制在 30 秒内。不要执行会修改生产状态的操作。

好的请求通常提供：

- SSH alias 或环境名称
- 服务/容器名称（作为候选，不等于已确认目标）
- 问题类型、开始时间、是否仍在发生
- 影响范围或相关接口
- 允许的诊断时间窗口和组织内要求

不要在请求中提供密码、token、私钥或完整环境变量。首次密码认证时，密码只输入 OpenSSH 在本地终端显示的提示符，不要输入聊天框或 Skill 表单。

## 4. 按步骤确认目标

### 4.1 选择服务器

Agent 应列出实际可用的 SSH alias，例如：

| Alias | Host | User | Port | 连通状态 |
|---|---|---|---:|---|
| beta | 10.20.1.15 | deploy | 22 | BatchMode 可连接 |
| staging | 10.20.2.18 | ops | 2222 | BatchMode 可连接 |

你明确回复：

> 确认使用 beta。

即使只有一个候选，也应明确确认。连接始终复用 alias，以保留 SSH 配置中的 ProxyJump、端口和 IdentityFile 等设置。

### 4.2 选择容器

Agent 查询运行容器并检查实际 Java 进程后，展示类似信息：

| 容器名 | 容器 ID | 镜像 | Java 进程 | 状态 |
|---|---|---|---|---|
| order-service | `a1b2c3d4e5f6` | `company/order:2026.11` | `order-service.jar` | Running |
| billing-worker | `b2c3d4e5f6a1` | `company/billing:4.2` | `billing.jar` | Running |

你明确选择一个容器：

> 确认诊断 `order-service`，容器 ID `a1b2c3d4e5f6`。

镜像名称包含 Java 字样不能作为 Java 容器的判断依据；一次只诊断一个容器。

### 4.3 确认 JVM PID

Agent 识别进程后应展示进程身份，例如：

```text
容器：order-service / a1b2c3d4e5f6
容器内 PID：1
Java：1.8.0_402
用户：10001:10001
进程：/opt/java/bin/java -jar /app/order-service.jar
```

你确认：

> 确认目标是容器 `a1b2c3d4e5f6` 内 PID 1 的 `order-service.jar`。

多 JVM 时逐项展示候选并由你选择。即使只发现一个 JVM，也要确认。若容器重启、ID 或 PID/进程身份变化，当前任务停止并重新确认。

## 5. 兼容性检查与诊断计划

Attach 前，Agent 应检查 Linux/架构、Java 版本和路径、JVM 用户、PID namespace、Attach 能力、容器资源限制，以及临时目录和报告输出能力。Attach 运行目录与报告文件目录要分开确认。

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
4. 如果证据指向 JVM 热点，且输出位置可用，说明范围后启动一次最多 30 秒的 profiler 采样。
5. 到时停止同一 profiler 任务，确认已停止，再分析热点方法/调用树。
6. 保存原始输出和时间线，回传文件并校验 SHA-256。
7. 只清理本次任务创建的远程临时文件，生成报告。

诊断过程中的示例沟通：

> Agent：L1 显示容器 CPU 配额为 2 核，CPU 使用接近配额。`thread -n 10` 连续两次发现同一业务线程栈集中在 `PriceCalculator.rebuildIndex`。Profiler 需要使用已有 `/tmp` 输出目录，计划采样 20 秒，是否继续？
>
> 执行人：确认，限定 `PriceCalculator.rebuildIndex` 相关热点，20 秒后停止。

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

实际文件按诊断能力生成，不要求每次都有 profiler 文件。报告至少包含目标身份、诊断时间、命令时间线、证据、根因候选及可信度、建议、未解决问题、附件哈希和清理状态。未经脱敏的 token、密码、密钥不得写入报告。

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

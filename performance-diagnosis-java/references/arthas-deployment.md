# Arthas 缓存、部署与任务生命周期

本地缓存根目录：`~/.performance-diagnosis/arthas/versions/<version>/arthas-boot.jar`，当前固定版本记录在 `current-version`。诊断数据位于 `~/.performance-diagnosis/diagnostics/<host>/<container>/<task-id>/`。本地结果目录应仅当前用户访问。不得将 SSH 私钥或凭据复制到该目录。

## 固定版本

V1 固定使用 Arthas **4.3.5**。官方发布页当前标记 4.3.5 为最新版本：[Arthas Releases](https://github.com/alibaba/arthas/releases)。下载入口使用官方推荐的 `https://arthas.aliyun.com/arthas-boot.jar`。首次下载时，`scripts/prepare-arthas.sh` 检查启动 JAR 的 manifest 版本为 4.3.5 后缓存；若官方入口返回其他版本，脚本会拒绝缓存。

下载成功后脚本将 SHA-256 写入同一用户本地缓存目录，并在之后每次使用前校验。该首次摘要基于 HTTPS 下载结果，用于后续本地完整性检查；官方入口未提供本项目可核对的独立摘要或签名，因此这不是发布者签名验证。下载失败、manifest 版本不符或缓存摘要不匹配时均停止，不部署。

## 部署次序

1. 唯一任务 ID（如 `PD-YYYYMMDD-HHMMSS`）绑定已确认 host/container/PID。
2. 调用 `scripts/prepare-arthas.sh`：缓存不存在时自动从官方 HTTPS 地址下载、核对版本并生成本地摘要；缓存存在时检查摘要和 manifest。
3. SCP 到远端任务专属临时位置；Docker CP 到目标容器任务目录。远端无需互联网。
4. 确认写入位置是现有可用临时空间，不改变容器 mounts、根文件系统或权限。
5. 以目标 JVM 兼容的用户和已确认 PID 启动 Arthas，记录版本、启动输出和 Attach 结果。

## 非交互批处理

Arthas 批处理调用支持 `-f <script> <pid>`；每条命令单独一行。`dashboard`、`trace`、`watch`、`monitor` 等必须带有限次数参数，避免批处理不退出。L1 统一经 `scripts/arthas-batch.sh` 调用，它只接受文档列出的只读命令并要求系统存在 `timeout`/`gtimeout`。示例：

```bash
scripts/arthas-batch.sh --java /path/to/java --pid 123 --timeout 20 --commands 'dashboard -n 1;thread -n 10;jvm;memory;version'
```

未指定 `--arthas-boot` 时，批处理脚本会先执行 `scripts/prepare-arthas.sh`，因此本地无缓存时会自动下载；也可以单独调用准备脚本。

底层等价形式为 `java -jar arthas-boot.jar -f commands.as <pid>`。批处理正常退出后仍需对本次 Arthas 会话执行 `stop`，并确认会话退出；进程超时退出不等同于已验证清理。

## 任务生命周期

持续采样须有任务 ID、目标 PID、开始/截止时间和状态。通过 `scripts/arthas-task.sh init/status/finish` 在本机 `~/.performance-diagnosis/tasks/` 维护权限为 700/600 的任务台账。开始前查询所有未完成任务；会话中断后先查询台账和远端任务状态，不盲目重复启动。CPU profiler 默认间隔为 10 ms，可选 20/50 ms；总时长默认 20 秒且最多 30 秒。目标容器内存使用达到限制的 80% 或近期 OOM 时不执行 L2。结束后发送 Arthas profiler stop（如适用）和 Arthas `stop`，验证任务已停止再标记完成。只清理该任务创建的文件。确认本地回传哈希一致后才清远端副本；回传失败保留远端文件并记录恢复步骤。

任务台账是本地恢复索引，不会自动探测远端进程。若 SSH 中断后无法安全确认远程状态，暂停新采样并要求操作者恢复连接检查；不得仅凭本地状态执行 kill。

若 Arthas 支持的非交互调用方式无法可靠地捕获退出状态、约束命令和停止持续任务，则不要改用无限期交互会话；说明当前执行环境不满足安全条件。

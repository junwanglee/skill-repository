# Arthas 缓存、部署与任务生命周期

本地缓存根目录：`~/.performance-diagnosis/arthas/versions/<version>/arthas-boot.jar`，当前固定版本记录在 `current-version`。诊断数据位于 `~/.performance-diagnosis/diagnostics/<host>/<container>/<task-id>/`。本地结果目录应仅当前用户访问。不得将 SSH 私钥或凭据复制到该目录。

方案未给出经过 Java 8 验证的确切 Arthas 版本；首次部署前必须选定并验证固定版本，记录来源、版本和 SHA-256。不得自动使用 `latest`、自动升级或静默接受哈希变化。

## 部署次序

1. 唯一任务 ID（如 `PD-YYYYMMDD-HHMMSS`）绑定已确认 host/container/PID。
2. 从本地缓存取已验证 Jar；下载仅从官方发行源，先校验 SHA-256 再缓存。
3. SCP 到远端任务专属临时位置；Docker CP 到目标容器任务目录。远端无需互联网。
4. 确认写入位置是现有可用临时空间，不改变容器 mounts、根文件系统或权限。
5. 以目标 JVM 兼容的用户和已确认 PID 启动 Arthas，记录版本、启动输出和 Attach 结果。

## 任务生命周期

持续采样须有任务 ID、目标 PID、开始/截止时间和状态。默认最长 30 秒；结束后验证任务已停止。会话中断后先查询该任务状态，不盲目重复启动。只清理该任务创建的文件。确认本地回传哈希一致后才清远端副本；回传失败保留远端文件并记录恢复步骤。

若 Arthas 支持的非交互调用方式无法可靠地捕获退出状态、约束命令和停止持续任务，则不要改用无限期交互会话；说明当前执行环境不满足安全条件。

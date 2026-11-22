# Arthas 命令与权限表

每次记录命令、目标、原因、开始/结束时间、退出状态、原始输出和任务 ID。命令选项需按已固定 Arthas 版本核验；不要猜测版本行为。

| 等级 | 命令/能力 | 执行约束 |
|---|---|---|
| L1 | `dashboard -n 1`, `thread -n 1..20`, `jvm`, `memory`, `version` | 只对已确认 JVM 执行；由 `scripts/arthas-batch.sh` 限时调用。 |
| L2 | `trace`, `monitor`, `watch` | 明确类/方法，限制次数、周期和输出；不对全局通配符运行。 |
| L2 | `profiler start` / `profiler stop` | 同一任务成对管理；最多 30 秒、每 JVM 单任务；输出位置预先验证；完成后确认停止。 |
| L3 | heap dump、改变 JVM/类/业务运行状态的命令 | v1 禁止自动执行；停止并解释风险。 |

CPU、延迟、内存、GC 和线程策略见各专题文档。Profiler 的启动和停止是同一个任务的两个阶段，不得重复启动。输出文件的格式、参数必须符合固定 Arthas 版本的官方文档。

每次 Arthas 批处理结束后停止该 Arthas 会话并验证；有持续任务时先停止具体 profiler/trace/watch，再执行 Arthas `stop`。脚本进程退出或被 timeout 终止不能单独作为远端采样已停止的证据。

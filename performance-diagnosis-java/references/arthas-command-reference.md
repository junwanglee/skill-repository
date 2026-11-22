# Arthas 命令与权限表

每次记录命令、目标、原因、开始/结束时间、退出状态、原始输出和任务 ID。命令选项需按已固定 Arthas 版本核验；不要猜测版本行为。

| 等级 | 命令/能力 | 执行约束 |
|---|---|---|
| L1 | `dashboard -n 1`, `thread -n 1..20`, `jvm`, `memory`, `version` | 只对已确认 JVM 执行；由 `scripts/arthas-batch.sh` 限时调用。 |
| L2 | `trace`, `monitor`, `watch` | 明确类/方法，限制次数、周期和输出；不对全局通配符运行。 |
| L2 | `profiler start` / `profiler stop` | 同一任务成对管理；默认 20 秒、单次最多 300 秒；CPU 采样间隔默认 10 ms，可选择 20/50 ms；每 JVM 单任务；输出位置预先验证；先检查内存余量及近期 OOM，完成后确认停止。不得通过分段任务绕过上限。 |
| L3 | heap dump、改变 JVM/类/业务运行状态的命令 | v1 禁止自动执行；停止并解释风险。 |

CPU、延迟、内存、GC 和线程策略见各专题文档。Profiler 的启动和停止是同一个任务的两个阶段，不得重复启动。输出文件的格式、参数必须符合固定 Arthas 版本的官方文档。

`profiler` CPU 的 `-i` 是采样间隔，默认 `10000000` ns（10 ms）；例如 `-i 20000000` 表示 20 ms。`-d` 是总运行时长（秒），例如 `-d 300` 表示采 5 分钟。不要把采样间隔与总时长混为一谈，也不要为了延长总时长而提高生产风险。

Profiler 停止时默认优先保存结构化 Markdown 和 HTML 火焰图两种文件（如果目标环境能安全保存两者）：

Markdown 与 HTML 都有价值：Markdown 提供热点、自耗时和调用树，利于 AI 文本分析；HTML 保留交互式火焰图，利于人工浏览。固定版本 4.3.5 的每个 profiler 任务只能停止/导出一次；不能假定一次 `stop` 能同时输出两种格式，也不能再次启动采样来补另一种格式。执行前按[Arthas Profiler 官方文档](https://arthas.aliyun.com/doc/profiler.html)核对该版本的格式能力，并选择可靠方案：若支持从同一份采样数据导出两种格式，则两者都保存；否则默认优先 `--format md --file /tmp/pd-<task-id>/profile.md`，HTML 可作为替代选项由执行者选择。导出后验证文件和采样任务停止状态。

每次 Arthas 批处理结束后停止该 Arthas 会话并验证；有持续任务时先停止具体 profiler/trace/watch，再执行 Arthas `stop`。脚本进程退出或被 timeout 终止不能单独作为远端采样已停止的证据。

# 内存异常诊断

先对比容器实际内存/limit、JVM heap、non-heap、GC 状态与时间序列。结合 Arthas `dashboard`、`memory`、`jvm` 观察变化；有经过验证的 allocation profiler 时，作为 L2 使用有界短采样。

区分堆占用、非堆、容器内存和对象分配速率。高分配速率不等于泄漏；泄漏判断需有持续增长且回收后基线不回落等证据。不得自动执行 heap dump（L3），不得改变 JVM 参数或启用新日志配置。说明现有数据不能回答的问题及建议的后续人工采集方案。

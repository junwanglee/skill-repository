# Docker 容器与 JVM 目标确认

只有执行人选择并确认服务器后才连接 SSH。先确认 `docker version` 可读且 Docker daemon 可访问；无权限时停止并报告，不使用 sudo。

获取运行容器清单：

```bash
docker ps --format '{{.ID}} {{.Names}} {{.Image}} {{.Status}}'
```

通过 SSH 执行时，把每条远端命令完整放在引号内；`--format` 和它的模板不能被换行拆成两条命令。例如：

```bash
ssh beta 'docker version --format "{{.Server.Version}}"'
ssh beta 'docker ps --format "{{.ID}} {{.Names}} {{.Image}} {{.Status}} {{.Command}}"'
```

如果把一组命令放进 SSH 的单引号中，每条命令可另起一行，但每条命令自己的参数和模板必须保持完整。不要在 `--format` 后直接换行。

镜像名不能证明容器正在运行 Java。Agent 先把所有运行中的容器按编号列给执行人，展示名称、完整 ID、镜像和状态，然后暂停等待选择；不得先进入所有容器探测 Java 进程。选中后，只检查该容器内 Java 进程命令、Java 可执行路径、Jar 或主类。探测方式应适应精简镜像，不假定有 bash、ps 或 jcmd；可在目标环境支持时使用 `docker exec <confirmed-container> jcmd -l`，也可检查 `/proc`。命令不可用只代表探测受限。

对所选容器内发现的 Java 服务候选按编号列出 PID、Jar/主类、用户、Java 版本和启动身份；暂停等待执行人选择服务/PID。只有一个 JVM 时也必须显示选项并等待。选择后复述服务器、容器 ID、服务和 PID，然后继续兼容性检查；不再重复确认同一目标。

后续所有调用绑定已确认的容器 ID 与 PID。每次阶段切换前核实容器 ID/状态和进程身份；容器重启、PID 改变或身份不匹配时立即停止并重新确认。一次只处理一个容器。

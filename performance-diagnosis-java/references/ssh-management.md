# SSH 主机发现与连接

复用当前用户的 `~/.ssh/config` 和 SSH agent。支持 SSH key，也支持首次连接时由本地 OpenSSH 提示输入账户密码或 keyboard-interactive 验证。优先使用配置中的 Host alias，避免自行重建参数而破坏 ProxyJump、IdentityFile、端口或其他 SSH 选项。

## 本地预检

检查 `ssh` 是否可用、`~/.ssh` 是否存在、config/key 文件是否存在、agent 是否可用。Key 文件存在只说明文件存在，不说明认证可用。绝不读取私钥内容。

`scripts/list-ssh-servers.sh` 仅调用 `ssh -G` 解析本地有效配置，不尝试建立网络连接。因此它不判断主机是否可达，也不声称密钥登录成功。用户选择服务器后，才对该 alias 发起连接。不要设置 `StrictHostKeyChecking=no`。未知 Host Key 必须交由执行人按其组织流程核实和接受。列表可展示 alias、解析出的 HostName/User/Port，并标为“未测试”。

## 服务器选择与新增

每次任务都要求执行人明确选择服务器，即使候选只有一个。若没有可用 alias，Agent 提供两种方式：逐项询问 alias、主机/IP、用户名、端口和认证方式后代为运行脚本；或把这些值填好，给执行人一条可直接运行的完整命令。两种方式最后都由脚本把 Host 块写入本机 `~/.ssh/config`。无 TTY 环境必须使用参数模式，不能运行裸交互脚本：

```bash
performance-diagnosis-java/scripts/setup-ssh-server.sh --alias beta --host 10.20.1.15 --user deploy --port 22 --auth password
```

脚本支持有 TTY 的本地交互模式，也支持上述非交互参数模式。缺少 TTY 且缺少必要参数时会输出用法并报错，不会静默退出。写入前会检查 alias 是否重复及前置 `Host *`，成功后以原子替换方式保留原配置内容并追加新 Host 块，配置文件权限设为 `600`；写入后用 `ssh -G` 核实 HostName/User/Port 的有效值。旧版本遗留的 `config.performance-diagnosis.<alias>` 片段会保留，但不会阻止新 Host 写入。密码/keyboard-interactive 密码不经脚本输入、参数、日志或文件。如 Agent shell 没有 TTY，用户只在没有可复用 ControlMaster 时才需在本地终端运行 `ssh <alias> true` 并在 OpenSSH 密码提示中输入；不要发给 Agent。新建密码 alias 配置 `ControlMaster auto`、`ControlPath ~/.ssh/cm-%C` 和 1 小时 `ControlPersist`。认证成功后，同一 SSH 配置下的后续命令应复用连接；诊断结束时默认让连接自行过期，执行人可随时运行 `ssh -O exit <alias>` 主动关闭。对于已有 alias，不自动改写配置；检查 `ssh -G <alias>` 和 `ssh -O check <alias>`。若 master 不存在或已过期，再提示执行人登录一次。key 模式支持 `--public-key ~/.ssh/id_ed25519.pub`；有 TTY 时也可以由本机调用 `ssh-keygen` 生成专用 key。私钥只保留在本机，脚本显示 `.pub` 公钥供执行人按组织流程安装，不自动上传。

向导不捕获或保存密码，不关闭 Host Key 校验，不覆盖已有 alias/密钥/配置片段。交互密码仅由 OpenSSH 客户端直接接收。向导不执行远端 `authorized_keys` 修改。

SSH 失败时记录错误并停止远端操作；检查 DNS/网络、端口、用户和 key 绑定，不要通过关闭校验或自动提权规避。

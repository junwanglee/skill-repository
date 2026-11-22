# SSH 主机发现与连接

复用当前用户的 `~/.ssh/config` 和 SSH agent。支持 SSH key，也支持首次连接时由本地 OpenSSH 提示输入账户密码或 keyboard-interactive 验证。优先使用配置中的 Host alias，避免自行重建参数而破坏 ProxyJump、IdentityFile、端口或其他 SSH 选项。

## 本地预检

检查 `ssh` 是否可用、`~/.ssh` 是否存在、config/key 文件是否存在、agent 是否可用。Key 文件存在只说明文件存在，不说明免密可用。绝不读取私钥内容。

逐个探测 config alias 时使用非交互模式和短超时，例如：

```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 beta 'printf SSH_OK'
```

BatchMode 成功表示当前密钥/agent 可用；失败也可能只是需要交互式密码，不能直接把该 alias 判为不可达。列表应标记为“需要交互认证或暂不可达”，由执行人选择后再连接。不要设置 `StrictHostKeyChecking=no`。未知 Host Key 必须交由执行人按其组织流程核实和接受。报告可展示 alias、解析出的 HostName/User/Port 和测试状态，但避免输出私钥路径之外的敏感连接细节。

## 服务器选择与新增

每次任务都要求执行人明确选择服务器，即使候选只有一个。若没有可用 alias，Agent 在对话中逐项收集 alias、主机/IP、用户名、端口和认证方式，然后用参数调用向导；不要让用户猜脚本提示，也不要在 Agent 的无 TTY shell 中运行裸交互脚本：

```bash
performance-diagnosis-java/scripts/setup-ssh-server.sh --alias beta --host 10.20.1.15 --user deploy --port 22 --auth password
```

脚本支持有 TTY 的本地交互模式，也支持上述非交互参数模式。缺少 TTY 且缺少必要参数时会输出用法并报错，不会静默退出。密码/keyboard-interactive 模式会生成独立配置片段，但密码不经脚本输入、参数、日志或文件；如执行环境没有 TTY，用户需在自己的终端运行脚本给出的 `ssh -F <snippet> <alias> true` 命令并在 OpenSSH 提示符输入密码。配置片段由脚本生成供审阅，不自动改写现有 `~/.ssh/config`。key 模式支持 `--public-key ~/.ssh/id_ed25519.pub`；有 TTY 时也可以由本机调用 `ssh-keygen` 生成专用 key。私钥只保留在本机，脚本显示 `.pub` 公钥供执行人按组织流程安装，不自动上传。

向导不捕获或保存密码，不关闭 Host Key 校验，不覆盖已有 alias/密钥/配置片段。交互密码仅由 OpenSSH 客户端直接接收。向导不执行远端 `authorized_keys` 修改。

SSH 失败时记录错误并停止远端操作；检查 DNS/网络、端口、用户和 key 绑定，不要通过关闭校验或自动提权规避。

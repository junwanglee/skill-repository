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

每次任务都要求执行人明确选择服务器，即使候选只有一个。若没有可用 alias，直接引导执行人运行仓库提供的交互式向导：

```bash
performance-diagnosis-java/scripts/setup-ssh-server.sh
```

不要让执行人逐条手动敲初始化命令。向导询问 alias、主机、用户名、端口和认证方式。默认密码/keyboard-interactive 模式可以选择立即试连，由本地 OpenSSH 提示输入密码；密码不经过脚本输入、参数、日志或文件。配置片段供执行人审阅，不自动改写现有 `~/.ssh/config`。也可以选择 key 模式：本地调用 `ssh-keygen` 生成专用 ed25519 key 或复用现有 key，私钥只保留在本机；脚本显示 `.pub` 公钥供执行人按组织流程安装，不自动上传。

向导不捕获或保存密码，不关闭 Host Key 校验，不覆盖已有 alias/密钥/配置片段。交互密码仅由 OpenSSH 客户端直接接收。向导不执行远端 `authorized_keys` 修改。

SSH 失败时记录错误并停止远端操作；检查 DNS/网络、端口、用户和 key 绑定，不要通过关闭校验或自动提权规避。

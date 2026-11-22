# SSH 主机发现与连接

复用当前用户的 `~/.ssh/config` 和 SSH agent。优先使用配置中的 Host alias，避免自行重建参数而破坏 ProxyJump、IdentityFile、端口或其他 SSH 选项。

## 本地预检

检查 `ssh` 是否可用、`~/.ssh` 是否存在、config/key 文件是否存在、agent 是否可用。Key 文件存在只说明文件存在，不说明免密可用。绝不读取私钥内容。

逐个探测 config alias 时使用非交互模式和短超时，例如：

```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 beta 'printf SSH_OK'
```

不要设置 `StrictHostKeyChecking=no`。未知 Host Key 必须交由执行人按其组织流程核实和接受。报告可展示 alias、解析出的 HostName/User/Port 和测试状态，但避免输出私钥路径之外的敏感连接细节。

## 服务器选择与新增

每次任务都要求执行人明确选择服务器，即使候选只有一个。若没有可用 alias，直接引导执行人运行仓库提供的交互式向导：

```bash
performance-diagnosis-java/scripts/setup-ssh-server.sh
```

不要让执行人逐条手动敲 `ssh-keygen`、`ssh-copy-id` 或 SSH 配置命令。向导询问 alias、主机、用户名、端口和公钥选择；可以调用本机 `ssh-keygen` 生成专用 ed25519 key，并在本地显示公钥。私钥只保留在本机。它生成独立、权限受限的配置片段供执行人审阅，但不自动改写现有 `~/.ssh/config`，也不自动把公钥上传到服务器。执行人应通过组织批准的服务器访问流程安装公钥，审阅并手动合并配置片段，再验证 Host Key 和 BatchMode 连接。

向导不要求或读取密码，不关闭 Host Key 校验，不覆盖已有 alias/密钥/配置片段。若用户请求自动安装公钥，应说明需要先有经批准的远程认证方式；本向导不执行密码登录或远端 `authorized_keys` 修改。

SSH 失败时记录错误并停止远端操作；检查 DNS/网络、端口、用户和 key 绑定，不要通过关闭校验或自动提权规避。

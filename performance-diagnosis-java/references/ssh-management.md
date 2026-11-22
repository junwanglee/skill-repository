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

每次任务都要求执行人明确选择服务器，即使候选只有一个。若没有可用 alias，提供手动配置建议：检查现有 key；由执行人决定是否生成 ed25519 key；由执行人将公钥加入服务器；由执行人编辑 SSH config；再以 BatchMode 测试。不得自动生成密钥、编辑配置、执行密码登录或要求用户把密码提供给 AI。

SSH 失败时记录错误并停止远端操作；检查 DNS/网络、端口、用户和 key 绑定，不要通过关闭校验或自动提权规避。

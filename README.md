# Skill Repository

这里集中维护面向 AI Agent 的可复用 Skill。每个 Skill 通常以独立目录组织，包含入口说明、参考资料、辅助脚本和输出模板，便于按需使用和迭代。

## 当前 Skills

| Skill | 用途 | 入口 |
|---|---|---|
| `performance-diagnosis-java` | 使用 SSH、Docker 和 Alibaba Arthas，辅助诊断 Linux Docker 中 Java 服务的线上性能问题。 | [performance-diagnosis-java/SKILL.md](performance-diagnosis-java/SKILL.md) |

## 目录结构

```text
.
├── README.md
└── performance-diagnosis-java/
    ├── SKILL.md          # Agent 使用入口与诊断工作流
    ├── README.md         # Skill 简介、前置条件与本地脚本说明
    ├── references/       # 安全策略、环境检查和问题专项诊断资料
    ├── scripts/          # 本地 SSH 检查和目标参数校验脚本
    └── templates/        # 环境检查与性能诊断报告模板
```

## 使用方式

选择与任务匹配的 Skill，先阅读其 `SKILL.md`，再按文档中的工作流执行。各 Skill 的 `README.md` 说明适用范围、前置条件和辅助文件。`references/` 中的内容用于补充具体步骤，`templates/` 用于统一结果格式。

当前 Java 性能诊断 Skill 的详细说明见 [`performance-diagnosis-java/README.md`](performance-diagnosis-java/README.md)。

## 安全原则

- Skill 文档用于指导 Agent；其中描述的操作步骤不自动构成对外部系统执行操作的授权。
- 涉及生产环境时遵循对应 Skill 中的目标确认、权限分级和停止条件。
- 不将凭据、私钥或未经脱敏的敏感信息写入仓库。
- 辅助脚本应保持范围清晰、输入经过校验，并明确说明其会访问或修改的对象。

## 新增 Skill

新增内容请放入独立目录，并提供入口 `SKILL.md`。建议同时补充简明 `README.md`、必要的参考资料、可复用模板和经过审慎设计的辅助脚本；在入口文档中说明适用场景、前置条件、执行步骤和安全边界。

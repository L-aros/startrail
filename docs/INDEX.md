# 文档目录

```text
StarTrail-docs/
├── AGENTS.md / CLAUDE.md              开发代理与实施约束
├── README.md                          项目入口
├── LICENSE-DECISION.md                许可证待决说明
├── SECURITY.md PRIVACY.md             对外安全与隐私政策
├── CONTRIBUTING.md THIRD_PARTY.md CHANGELOG.md
└── docs/
    ├── product/PRD.md
    ├── architecture/{ARCHITECTURE,PROJECT_STRUCTURE,TECH_STACK}.md
    ├── data/{DATA_MODEL,DATABASE}.md
    ├── security/{VAULT_FORMAT,CRYPTOGRAPHY,THREAT_MODEL}.md
    ├── sync/{OBJECT_FORMAT,R2_SYNC,CONFLICTS}.md
    ├── flows/CORE_FLOWS.md
    ├── ui/{NAVIGATION,DESIGN_SYSTEM}.md
    ├── operations/{ERROR_HANDLING,LOGGING,TELEMETRY,UPDATE_PROTOCOL}.md
    ├── development/{DEVELOPMENT,AI_RULES,GIT_WORKFLOW}.md
    ├── quality/{TESTING,ACCEPTANCE}.md
    ├── platforms/{ANDROID,WINDOWS}.md
    ├── adr/{ADR_POLICY,ADR-0001…ADR-0004}.md
    └── GLOSSARY.md
```

阅读路径：产品负责人从 PRD 开始；实现者读 AGENTS、架构、数据/安全/同步；发布者读质量、平台、更新、隐私、安全与第三方组件；任何协议变动先读 ADR policy。

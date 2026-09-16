# Deploy - 部署配置分支

工作分支：`deploy`
默认工作区：`Deploy/`（仓库根平铺）

## 核心原则

**Deploy 分支只做"部署配置"，不做"构建"。**

- CI 负责：代码 checkout → 构建镜像 → 打 tag → 推镜像仓库
- Deploy 负责：helm chart / k8s manifests / 环境配置 / rollout

## 目录结构

```
Deploy/
├── apps/
│   ├── api-gateway/helm/
│   │   ├── Chart.yaml
│   │   ├── templates/
│   │   ├── values.yaml
│   │   ├── environments/
│   │   │   ├── .env.staging
│   │   │   └── .env.production
│   │   └── deploy.sh
│   └── user-service/helm/
├── environments/
│   ├── staging/
│   └── production/
├── releases/                # 发布快照
├── scripts/
│   ├── deploy.sh
│   ├── rollback.sh
│   └── healthcheck.sh
└── .deploy/                 # 私有工作目录
```

## 镜像 Tag 策略

- 默认：develop 分支最新 commit SHA
- 发布：Git Tag（如 v1.0.0）
- 特殊：用户指定
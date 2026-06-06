# 月夜见0 · 全部网站资产盘点

## 域名资产

| 域名 | 状态 | 指向 | 说明 |
|------|------|------|------|
| `tsukiyomi.world` | ❌ DNS不可达 | 应指向43.160.235.191 | 月夜见0主站 |
| `sora-o.com` | ⚠️ HTTP 401 | 43.160.235.191 | 主域名(需认证) |
| `docmind.sora-o.com` | ❌ DNS不可达 | 应指向43.160.235.191 | AI文档问答 |

## 服务器端口

| 端口 | 服务 | 状态 | 说明 |
|------|------|------|------|
| 80 | Nginx | ⚠️ HTTP 403 | 静态文件服务器 |
| 16801 | resurrect.js | ✅ HTTP 200 | Express网关(核心服务) |
| 3000 | OpenClaw | ❌ 不可达 | 外接通信网关 |

## GitHub Pages 状态

| 仓库 | GitHub Pages | website/目录 | 状态 |
|------|-------------|-------------|------|
| `DNAOS` | ❌ 未启用 | ✅ 有 | 宪章OS网站 |
| `Suk-Builder` | ❌ 未启用 | ❌ 无 | 产品矩阵 |
| `builder-system` | ❌ 未启用 | ❌ 无 | 递砖机核心 |
| `bdi-suite` | ❌ 未启用 | ❌ 无 | BDI套件 |
| `sukaczev-platform` | ❌ 未启用 | ❌ 无 | 视频平台 |
| `baihua-suite` | ❌ 未启用 | ❌ 无 | 白桦套件 |
| `brick-games` | ❌ 未启用 | ❌ 无 | 递砖游戏 |
| `suk-builder-org` | ❌ 未启用 | ❌ 无 | 组织规范 |

## 需要做的事

1. **修复DNS** — tsukiyomi.world / docmind.sora-o.com 解析
2. **启用GitHub Pages** — 8个仓库全部开启静态网站
3. **给6个整合仓库添加website/** — 至少一个着陆页
4. **所有网站加四语切换** — 🇨🇳🇬🇧🇩🇪🇫🇷

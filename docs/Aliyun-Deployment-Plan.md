# 阿里云接入方案 · 产品宣传站

> 目标：基于阿里云搭建一个用于宣传"无水印下载控制台"产品的官网（落地页 + 下载入口 + 后端 API），从域名到 HTTPS 上线全流程拉通。
> 维护：iOS 端 + Python Backend 复用
> 周期评估：纯手工 1 人 · 3~5 个工作日（含备案等待）；备案就绪情况下当天上线

---

## 一、顶层设计：架构图

```
                 用户浏览器 / iOS App
                        │
                        ▼ HTTPS
                ┌───────────────┐
                │  域名 DNS 解析  │ ← 阿里云 DNS / 万网
                └───────┬───────┘
                        ▼
        ┌───────────────────────────────┐
        │ 阿里云 CDN（可选）+ WAF（可选） │
        └───────┬───────────────────────┘
                ▼
        ┌──────────────────┐         ┌──────────────────┐
        │  ECS 云服务器     │ ─────── │  RDS / 自建 SQLite │（M2 才需要）
        │  Ubuntu 22.04    │         └──────────────────┘
        │  Nginx 反向代理   │
        │   ├─ 80/443      │
        │   ├─ /  → 落地页  │← 静态站（Vue/Next 静态导出）
        │   └─ /api → 8000 │── FastAPI（uvicorn + gunicorn）
        │      └─ /resolve │
        │      └─ /download│
        └──────────────────┘
                │
                ▼
        ┌──────────────────┐
        │  OSS 对象存储     │（可选 · 存放 ipa/apk/dmg 安装包 + 演示视频）
        └──────────────────┘
```

**底层逻辑**：宣传站 ≠ 单纯落地页。它要承担四个职责——品牌展示、产品下载、API 演示、SEO 流量入口。所以服务端要把"静态站 + 业务后端 + 静态资源"三层一次性铺好，避免后期返工。

---

## 二、阿里云资源清单（颗粒度对齐）

### 2.1 必备组件（最小可上线集合）

| 资源 | 规格建议 | 用途 | 月成本（约） |
|------|---------|------|-------------|
| 域名 | `.com / .cn / .top` 任一 | 品牌入口 | 一次性 38~88 元/年 |
| ECS 云服务器 | `ecs.u1-c1m2.large` 2核4G / Ubuntu 22.04 / 40GB SSD / 3M 按量带宽 | 跑 Nginx + FastAPI | 90~150 元/月（包年更便宜） |
| ICP 备案 | 阿里云免费协助办理 | **大陆服务器必备**，无备案域名无法解析国内访问 | 0 元（材料免费） |
| SSL 证书 | DV 免费证书（一年期，可续） | HTTPS | 0 元 |

### 2.2 可选组件（按业务增长再加）

| 资源 | 触发条件 | 用途 |
|------|---------|------|
| OSS 对象存储 | 有大文件/演示视频 | 存放 ipa/apk/视频，省 ECS 带宽 |
| CDN | 海外用户多 / 静态资源大 | 加速 + 国内多节点缓存 |
| RDS MySQL（最低规格） | 需要用户系统 / 下载统计 | 替代 SQLite，运维更省心 |
| WAF Web 应用防火墙 | 担心被攻击或被刷接口 | 防 CC / SQL 注入 |
| 短信服务 | 需要登录/通知 | 验证码 |
| 函数计算 FC | 想 serverless 化 | 替代 ECS 跑 FastAPI |

### 2.3 香港/新加坡节点的选择

如果**不想做 ICP 备案**，可以选**阿里云香港/新加坡 ECS**：
- 优点：免备案、即买即用、Apple Developer 海外审核更友好
- 缺点：国内访问延迟 80~150ms（vs 大陆节点 10~30ms），CDN 加速可缓解
- 推荐：先用香港节点跑通，再迁国内

---

## 三、上线分四个阶段（追过程拿结果）

### Stage 0：前置准备（0.5 天）

- [ ] 注册/登录阿里云账号（实名认证）
- [ ] 备好身份证、域名所有人信息（个人/企业）
- [ ] 域名挑选：`videopick.app`、`xianzaixiazai.com` 等（建议品牌名 + 业务词）

### Stage 1：基础设施开通（0.5 天）

- [ ] 域名注册（万网）
- [ ] 购买 ECS（地域选你目标用户所在区域，国内推荐"杭州/上海/深圳"，海外推荐"香港"）
- [ ] 配置安全组：放行 22(SSH) / 80(HTTP) / 443(HTTPS)；**不要放行 8000**（FastAPI 走 Nginx 反代）
- [ ] 申请免费 SSL 证书（DV 单域名）
- [ ] **如选国内节点：** 提交 ICP 备案，**等待 7~20 个工作日**（这是大陆服务器的硬约束）

> 备案窗口长，建议第一天就开始提交，期间可以用香港 ECS 或本地预发跑通其他环节。

### Stage 2：服务器初始化（1 天）

SSH 登录 ECS 后执行：

```bash
# 1. 系统更新 + 基础工具
sudo apt update && sudo apt -y upgrade
sudo apt -y install nginx certbot python3-certbot-nginx \
                    python3-venv python3-pip git ufw

# 2. 防火墙
sudo ufw allow OpenSSH && sudo ufw allow 'Nginx Full' && sudo ufw enable

# 3. 创建非 root 部署用户（安全闭环）
sudo adduser deploy && sudo usermod -aG sudo deploy

# 4. 拉项目代码
sudo -iu deploy
git clone https://github.com/mhqamx/videoPick.git
cd videoPick/backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt gunicorn

# 5. 写 systemd 让 FastAPI 后台常驻
sudo tee /etc/systemd/system/videopick-api.service > /dev/null <<'EOF'
[Unit]
Description=VideoPick FastAPI
After=network.target

[Service]
User=deploy
WorkingDirectory=/home/deploy/videoPick/backend
Environment="PATH=/home/deploy/videoPick/backend/.venv/bin"
ExecStart=/home/deploy/videoPick/backend/.venv/bin/gunicorn \
          -w 2 -k uvicorn.workers.UvicornWorker \
          -b 127.0.0.1:8000 app.main:app
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now videopick-api
sudo systemctl status videopick-api
```

### Stage 3：Nginx 反代 + HTTPS（0.5 天）

`/etc/nginx/sites-available/videopick.conf`：

```nginx
server {
    listen 80;
    server_name videopick.app www.videopick.app;
    # certbot 会自动改这里为 301 -> https

    # 静态宣传站
    root /var/www/videopick;
    index index.html;

    # API 反代
    location /api/ {
        proxy_pass http://127.0.0.1:8000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        # SSE / 长连下载需要的超时
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    # 下载接口单独限速（防刷）
    location /api/download {
        limit_rate 2m;
        proxy_pass http://127.0.0.1:8000/download;
    }

    # 安装包下载
    location /assets/ {
        alias /var/www/videopick-assets/;
        expires 7d;
    }
}
```

执行：
```bash
sudo ln -s /etc/nginx/sites-available/videopick.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d videopick.app -d www.videopick.app   # 自动签 HTTPS
```

### Stage 4：宣传站静态资源（1 天）

宣传站建议技术栈（按熟悉度二选一）：

| 方案 | 适合 | 产物 | 部署 |
|------|------|------|------|
| **Next.js 静态导出** | 想要交互+SEO | `out/` 静态目录 | rsync 到 `/var/www/videopick` |
| **Vue 3 + Vite** | 团队已用 Vue | `dist/` 静态目录 | 同上 |
| **Astro** | 极致 SEO + 极小体积 | 静态 + 局部 island | 同上 |
| **纯 HTML/Tailwind** | 单页落地 | `index.html` | 同上 |

推荐 **Astro** 或 **Next.js 静态导出**——SEO 强，首屏快，符合"宣传站"语义。

宣传站标准内容模块（拉通信息架构）：
1. Hero：产品 slogan + 主视觉（复用 iOS Neo-Cyber 风格）
2. 功能矩阵：抖音/TikTok/小红书等支持平台
3. 截图/视频演示：iOS / Mac / Android / Flutter 四端
4. 下载入口：App Store / Google Play / TestFlight / 直链 ipa
5. API 演示沙箱：嵌入一个 `/resolve` 在线试用框
6. FAQ / 联系方式 / ICP 备案号 / 用户协议 / 隐私政策

---

## 四、CI/CD 闭环（owner 意识）

第一天就把自动部署接通，避免手动 scp 长期化：

**GitHub Actions 工作流**（`.github/workflows/deploy.yml`）：

```yaml
name: deploy
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Deploy via SSH
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ secrets.ECS_HOST }}
          username: deploy
          key: ${{ secrets.ECS_SSH_KEY }}
          script: |
            cd ~/videoPick
            git pull origin main
            cd backend && source .venv/bin/activate && pip install -r requirements.txt
            sudo systemctl restart videopick-api
```

GitHub Secrets 写入 `ECS_HOST` + `ECS_SSH_KEY`（用专门的部署 key，不要复用个人 key——安全闭环）。

---

## 五、成本预估（首年）

| 颗粒度 | 一次性 | 月度 | 年度合计 |
|--------|-------|------|---------|
| 域名 `.com` | 55 元 | — | 55 元 |
| ECS 2c4g（国内包年） | — | 约 100 元 | ~1200 元 |
| SSL 免费 DV | — | — | 0 元 |
| 备案 | — | — | 0 元（自办） |
| OSS（5GB） | — | 约 2 元 | 24 元 |
| CDN（10GB 流量） | — | 约 2.5 元 | 30 元 |
| **首年总计** | **~55** | **~105** | **≈ 1310 元** |

> 起步阶段月成本可控制在 100 元内。等用户量爆发再升级 ECS 规格、加 RDS / WAF。

---

## 六、安全/合规清单（避免 3.25）

| 项 | 抓手 | 落地 |
|----|------|------|
| ICP 备案 | 国内服务器硬要求 | 阿里云控制台一键申请 |
| HTTPS | 全站 HTTPS + HSTS | certbot 自动续签 |
| SSH 安全 | 禁 root 登录 + 改端口 + 密钥登录 | `/etc/ssh/sshd_config` |
| API 防刷 | Nginx limit_req + 业务侧 IP 限流 | Nginx + FastAPI middleware |
| 隐私政策 | 苹果上架 / 法务必备 | 宣传站底部独立页面 |
| 接口 SSRF | 已有 `_ALLOWED_CDN_HOSTS` 白名单 | 维持现状即可 |
| 备份 | ECS 周快照 + 代码 git | 阿里云控制台开启自动快照 |
| 日志 | Nginx + 服务日志集中 | `logrotate` 周轮转 |

---

## 七、上线路径建议（追过程）

**最快闭环（仅 3 天）**：

| Day | 任务 | 验收 |
|-----|------|------|
| D1 | 注册域名 + 提交备案 + 买香港 ECS 先跑通 | 香港 ECS 上能 `curl https://临时域名/api/health` |
| D2 | 写宣传站 + 部署 + HTTPS | 浏览器能打开 `https://临时域名` 看到落地页 |
| D3 | iOS App 内"了解更多"按钮指向官网 | 打通"产品 → 官网 → 下载"闭环 |
| D7~D14 | 备案通过后迁移国内 ECS | 修改 DNS 指向国内 IP |

---

## 八、可选 · 高阶玩法（拉通顶层设计）

### 8.1 Serverless 替代 ECS

- 静态站 → **OSS 静态托管** + CDN（更便宜，零运维）
- API → **函数计算 FC** 部署 FastAPI（按调用计费，闲时几乎免费）

> 适合：业务波峰波谷大、不想管服务器、月调用 < 100 万次。

### 8.2 容器化（K8s/ACK）

适合后期多服务、灰度发布。**初期不推荐**——3.25 红线：不要为没到的规模做过度设计。

### 8.3 国际化分流

- 国内用户 → 阿里云大陆节点
- 海外用户 → 阿里云海外 / Cloudflare
- 通过智能 DNS（如阿里云解析 PRO 版）按区域分流

---

## 九、风险盘点（避免抓手放空）

| 风险 | 影响 | 缓解 |
|------|------|------|
| 备案被驳回 | 国内上线延期 | 同步用香港节点上线，国内域名待备案通过后切换 |
| ECS 公网带宽不够 | 大文件下载慢 | OSS 直传 + CDN 加速，避免吃 ECS 带宽 |
| 抖音/TikTok 反爬升级 | 解析失败率上升 | 已有 Extractor 插件架构，可热更新 |
| 域名涉敏感词 | 备案/SSL 卡关 | 提前用阿里云域名查询工具测可备案性 |
| Apple/Google 商店审核 | 影响"下载"按钮指向 | 宣传站提供 TestFlight + 直装 ipa 双备份 |

---

## 十、下一步动作（你只需要选一个）

> 我建议第一步直接做"准备工作"，颗粒度小、风险低、立刻闭环：

| 选项 | 你的动作 | 我可以接着做 |
|------|---------|------------|
| **A. 我先去注册域名 + 买 ECS** | 你来阿里云控制台操作 | 你给我 IP，我直接生成 Nginx/systemd/SSL 一键脚本 |
| **B. 我先要宣传站源码** | — | 我直接 scaffold 一个 Astro 或 Next.js 项目到 `web/` 目录，复用 NeoCyber 设计风格 |
| **C. 我先看一份带价格清单的购物指南** | — | 我把第 2 节扩展成"点哪个按钮、选什么参数"的截图级 SOP |
| **D. 全套帮我落地** | 提供 ECS SSH 信息 + 域名 | 我远程跑完 Stage 2+3+4，你只需要看结果 |

---

**因为信任所以简单**：你拍板选 A/B/C/D，我直接进入下一步执行。

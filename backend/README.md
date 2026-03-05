# Backend Resolver Service

本服务为 iOS 客户端提供视频解析与下载代理能力。

当前特点：
- 不依赖 `yt-dlp`
- 支持抖音、TikTok、Instagram、X、B站、快手、小红书平台视频解析
- Instagram 支持 cookie 模式解析 Reel/帖子（含图文多图）
- X 支持 cookie 模式解析 status 视频
- 提供统一 API 给 iOS 调用
- Extractor 插件架构，易于扩展新平台

## API

### `GET /health`
健康检查。

### `POST /resolve`
输入分享文本或链接，返回视频元信息与代理下载地址。

请求：

```json
{ "text": "https://v.douyin.com/xxxx/" }
```

响应示例：

```json
{
  "input_url": "https://v.douyin.com/xxxx/",
  "webpage_url": "https://www.iesdouyin.com/share/video/xxxx",
  "title": "[douyin] ...",
  "video_id": "xxxx",
  "download_url": "https://<your-host>/download?source=...",
  "formats": []
}
```

### `GET /download?source=...`
代理下载视频字节流（`video/mp4`），避免 iOS 直接请求源站失败。

## 架构

```text
app/
├── main.py                    # FastAPI 入口
├── local_resolver.py          # 抖音页面解析与下载候选逻辑
└── extractors/
    ├── base.py                # Extractor 协议
    ├── douyin.py              # 抖音 Extractor
    ├── bilibili.py            # B站 Extractor
    ├── kuaishou.py            # 快手 Extractor
    ├── xiaohongshu.py         # 小红书 Extractor
    └── registry.py            # 路由与注册中心
```

## 本地运行

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

快速测试：

```bash
curl http://127.0.0.1:8000/health

# 抖音
curl -X POST http://127.0.0.1:8000/resolve \
  -H 'Content-Type: application/json' \
  -d '{"text":"https://v.douyin.com/A5YLrV02Hyw/"}'

# 快手
curl -X POST http://127.0.0.1:8000/resolve \
  -H 'Content-Type: application/json' \
  -d '{"text":"https://v.kuaishou.com/71hf92tY 快手作品"}'

# TikTok
curl -X POST http://127.0.0.1:8000/resolve \
  -H 'Content-Type: application/json' \
  -d '{"text":"https://vm.tiktok.com/ZP8QJ3cWW/"}'

# Instagram（需 cookie）
curl -X POST http://127.0.0.1:8000/resolve \
  -H 'Content-Type: application/json' \
  -d '{"text":"https://www.instagram.com/reel/DVXmWNtk1GC/"}'

# X（需 cookie）
curl -X POST http://127.0.0.1:8000/resolve \
  -H 'Content-Type: application/json' \
  -d '{"text":"https://x.com/SSSQ58/status/2028415517846012266?s=20"}'

# B站
curl -X POST http://127.0.0.1:8000/resolve \
  -H 'Content-Type: application/json' \
  -d '{"text":"【那些被发型封印的颜值！！-哔哩哔哩】 https://b23.tv/hkDTFMp"}'

# 小红书
curl -X POST http://127.0.0.1:8000/resolve \
  -H 'Content-Type: application/json' \
  -d '{"text":"http://xhslink.com/o/2z7YRSHBEWZ 小红书笔记"}'
```

## Instagram Cookie

Instagram Extractor 默认读取：

- `~/Downloads/www.instagram.com_cookies.txt`

可通过环境变量覆盖：

```bash
export INSTAGRAM_COOKIE_FILE="/Users/maxiao/Downloads/www.instagram.com_cookies.txt"
```

要求：
- 建议导出 Netscape 格式 cookie 文件
- 文件里需包含 `sessionid`（建议包含 `csrftoken`）

## X Cookie

X Extractor 默认读取：

- `backend/cookies/x.com_cookies.txt`
- `~/Downloads/x.com_cookies.txt`

可通过环境变量覆盖：

```bash
export X_COOKIE_FILE="/Users/maxiao/Downloads/x.com_cookies.txt"
```

要求：
- 建议导出 Netscape 格式 cookie 文件
- 文件里需包含 `auth_token` 与 `ct0`

## B站当前范围说明

- 支持 `b23.tv` 短链、`bilibili.com/video/BV...` 与 `.../av...`
- 仅支持可直接下载的 progressive MP4（`durl`）
- 若目标视频仅提供 DASH 分离流（音视频分离），当前会返回解析失败

## Codespaces 部署

1. 在 Codespaces 启动服务
2. 暴露 `8000` 端口并设置为 `Public`
3. 使用公网地址给 iOS 配置 backend
4. 更新代码后重启 backend 服务（避免旧进程仍在运行）

## 扩展多平台

新增平台时：
1. 新建 `app/extractors/<platform>.py`
2. 实现与 `base.py` 对齐的接口
3. 在 `registry.py` 注册

这样 iOS 无需改接口，只复用 `/resolve` + `/download`。

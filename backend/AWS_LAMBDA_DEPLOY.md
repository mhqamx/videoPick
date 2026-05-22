# AWS Lambda 部署备忘

用于把当前 FastAPI backend 临时部署到 AWS Lambda，并通过 Function URL 给 iOS 演示使用。

## 当前配置

- AWS 区域：`ap-northeast-1`
- Lambda 函数名：`VideoPick`
- 运行时：`Python 3.12`
- 架构：`x86_64`
- Handler：`lambda_function.lambda_handler`
- 超时：`30` 秒
- 内存：`256 MB`
- Function URL：
  `https://jv4mmmmt3fw4hq7qdmqmszohbi0jrvhc.lambda-url.ap-northeast-1.on.aws`
- 部署包：
  `/Users/maxiao/Desktop/demo/douyinDownLoad/DouyinDownLoad/backend/douyin-fastapi-lambda.zip`

## 进入项目目录

```bash
cd /Users/maxiao/Desktop/demo/douyinDownLoad/DouyinDownLoad/backend
```

## 登录 AWS CLI

如果 CLI 报 `NoCredentials: Unable to locate credentials`，先登录：

```bash
aws login
```

确认当前身份：

```bash
aws sts get-caller-identity
```

## 上传 Lambda 代码包

```bash
AWS_RETRY_MODE=adaptive AWS_MAX_ATTEMPTS=10 \
aws lambda update-function-code \
  --region ap-northeast-1 \
  --function-name VideoPick \
  --zip-file fileb://douyin-fastapi-lambda.zip \
  --cli-connect-timeout 60 \
  --cli-read-timeout 300
```

如果网络报错：

```text
Could not connect to the endpoint URL
Connection was closed before we received a valid response
```

一般是本机到 AWS endpoint 网络不稳定，不是 zip 问题。可以换网络、开代理，或在 Lambda 网页控制台手动上传：

```text
Lambda -> VideoPick -> Code -> Upload from -> .zip file
```

上传文件：

```text
/Users/maxiao/Desktop/demo/douyinDownLoad/DouyinDownLoad/backend/douyin-fastapi-lambda.zip
```

## 更新运行时配置

```bash
aws lambda update-function-configuration \
  --region ap-northeast-1 \
  --function-name VideoPick \
  --handler lambda_function.lambda_handler \
  --runtime python3.12 \
  --timeout 30 \
  --memory-size 256
```

注意：当前 CLI 不认 `--architectures x86_64`，不要加这个参数。架构在网页里确认是 `x86_64` 即可。

等待配置更新完成：

```bash
aws lambda wait function-updated \
  --region ap-northeast-1 \
  --function-name VideoPick
```

## Function URL 配置

如果还没有公网地址，在 Lambda 网页里创建：

```text
Lambda -> VideoPick -> Configuration -> Function URL -> Create function URL
```

配置：

- Auth type：`NONE`
- CORS：演示时可以先打开

创建后会得到类似：

```text
https://jv4mmmmt3fw4hq7qdmqmszohbi0jrvhc.lambda-url.ap-northeast-1.on.aws
```

## 测试接口

健康检查：

```bash
curl -i https://jv4mmmmt3fw4hq7qdmqmszohbi0jrvhc.lambda-url.ap-northeast-1.on.aws/health
```

预期返回：

```json
{"status":"ok"}
```

测试 TikTok 解析：

```bash
curl -i -X POST 'https://jv4mmmmt3fw4hq7qdmqmszohbi0jrvhc.lambda-url.ap-northeast-1.on.aws/resolve' \
  -H 'Content-Type: application/json' \
  -d '{"text":"https://www.tiktok.com/@koudi632/video/7618072232383745287"}'
```

如果返回：

```json
{"detail":"No video link found in TikTok page"}
```

说明云端可能还没有部署新版 zip，或 TikTok 在 AWS 出口返回的页面没有视频字段。当前新版 zip 已加入 TikTok fallback，需要确认重新上传成功。

## iOS 工程配置

iOS 工程后端地址位于：

```text
ios/DouyinDownLoad/Services/DouyinDownloadService.swift
```

当前配置：

```swift
URL(string: "https://jv4mmmmt3fw4hq7qdmqmszohbi0jrvhc.lambda-url.ap-northeast-1.on.aws/resolve")!,
```

## 演示前检查

建议演示前 30 分钟执行：

```bash
curl -i https://jv4mmmmt3fw4hq7qdmqmszohbi0jrvhc.lambda-url.ap-northeast-1.on.aws/health
```

再执行一次业务接口：

```bash
curl -i -X POST 'https://jv4mmmmt3fw4hq7qdmqmszohbi0jrvhc.lambda-url.ap-northeast-1.on.aws/resolve' \
  -H 'Content-Type: application/json' \
  -d '{"text":"https://www.tiktok.com/@koudi632/video/7618072232383745287"}'
```

## 停用公网服务

Lambda 不是传统服务器，不访问时不会一直运行。要关闭公网入口，删除 Function URL 即可：

```bash
aws lambda delete-function-url-config \
  --region ap-northeast-1 \
  --function-name VideoPick
```

删除 Function URL 后，这个公网地址会失效：

```text
https://jv4mmmmt3fw4hq7qdmqmszohbi0jrvhc.lambda-url.ap-northeast-1.on.aws
```

如果后续完全不用，可以删除整个函数：

```bash
aws lambda delete-function \
  --region ap-northeast-1 \
  --function-name VideoPick
```

建议演示结束后优先删除 Function URL，不急着删除函数。下次需要时重新创建 Function URL 即可。

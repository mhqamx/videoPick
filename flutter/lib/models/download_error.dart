class DownloadError implements Exception {
  final String message;
  const DownloadError(this.message);

  @override
  String toString() => message;

  static const invalidURL = DownloadError('无法从输入中提取有效链接');
  static const videoDataNotFound = DownloadError('未找到视频数据');
  static const noVideoLinkFound = DownloadError('解析成功但未找到视频链接');
  static const noPermission = DownloadError('没有相册访问权限');

  static DownloadError downloadFailed(int statusCode) =>
      DownloadError('下载失败 (HTTP $statusCode)');

  static DownloadError backendResolveFailed(String reason) =>
      DownloadError('后端解析失败: $reason');

  static DownloadError saveFailed(String reason) =>
      DownloadError('保存失败: $reason');
}

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import '../models/video_info.dart';
import '../services/download_service.dart';

class DownloadViewModel extends ChangeNotifier {
  final _service = DownloadService();

  String inputText = '';
  bool isLoading = false;
  String? errorMessage;
  String? successMessage;
  VideoInfo? videoInfo;
  bool showPreview = false;
  double? downloadProgress;

  Completer<void>? _cancelCompleter;
  bool _isCancelled = false;

  void updateInput(String text) {
    inputText = text;
    notifyListeners();
  }

  void clearInput() {
    inputText = '';
    errorMessage = null;
    successMessage = null;
    videoInfo = null;
    showPreview = false;
    downloadProgress = null;
    notifyListeners();
  }

  Future<void> pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      inputText = data.text!;
      notifyListeners();
    }
  }

  Future<void> processInput() async {
    if (inputText.trim().isEmpty) return;

    isLoading = true;
    errorMessage = null;
    successMessage = null;
    videoInfo = null;
    showPreview = false;
    downloadProgress = null;
    _isCancelled = false;
    _cancelCompleter = Completer<void>();
    notifyListeners();

    try {
      final info = await _service.parseAndDownload(
        inputText,
        onProgress: (progress) {
          if (_isCancelled) return;
          downloadProgress = progress;
          notifyListeners();
        },
      );

      if (_isCancelled) return;

      videoInfo = info;
      showPreview = true;
      downloadProgress = null;
    } catch (e) {
      if (_isCancelled) return;
      errorMessage = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void cancelDownload() {
    _isCancelled = true;
    _cancelCompleter?.complete();
    isLoading = false;
    downloadProgress = null;
    notifyListeners();
  }

  Future<void> saveMedia() async {
    if (videoInfo == null) return;

    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth) {
      errorMessage = '没有相册访问权限，请在设置中开启';
      notifyListeners();
      return;
    }

    try {
      if (videoInfo!.mediaType == MediaType.images) {
        for (final path in videoInfo!.localImagePaths) {
          final file = File(path);
          if (await file.exists()) {
            await PhotoManager.editor.saveImageWithPath(
              path,
              title: 'VideoPick_${DateTime.now().millisecondsSinceEpoch}',
            );
          }
        }
        successMessage = '已保存 ${videoInfo!.localImagePaths.length} 张图片到相册';
      } else {
        final localPath = videoInfo!.localPath;
        if (localPath != null) {
          final file = File(localPath);
          if (await file.exists()) {
            await PhotoManager.editor.saveVideo(
              file,
              title: 'VideoPick_${DateTime.now().millisecondsSinceEpoch}',
            );
            successMessage = '视频已保存到相册';
          }
        }
      }
    } catch (e) {
      errorMessage = '保存失败: $e';
    }

    notifyListeners();
  }

  void dismissPreview() {
    showPreview = false;
    notifyListeners();
  }
}

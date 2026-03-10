import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../models/video_info.dart';
import '../viewmodels/download_viewmodel.dart';
import '../views/fullscreen_image_page.dart';

class PreviewSection extends StatelessWidget {
  const PreviewSection({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DownloadViewModel>();

    if (!vm.showPreview || vm.videoInfo == null) {
      return const SizedBox.shrink();
    }

    final info = vm.videoInfo!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (info.title != null && info.title!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              info.title!,
              style: Theme.of(context).textTheme.titleSmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (info.mediaType == MediaType.video && info.localPath != null)
          _VideoPreview(videoPath: info.localPath!),
        if (info.mediaType == MediaType.images &&
            info.localImagePaths.isNotEmpty)
          _ImageGrid(imagePaths: info.localImagePaths),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => vm.saveMedia(),
          icon: const Icon(Icons.save_alt),
          label: Text(
            info.mediaType == MediaType.images
                ? '保存 ${info.localImagePaths.length} 张图片到相册'
                : '保存视频到相册',
          ),
        ),
      ],
    );
  }
}

class _VideoPreview extends StatefulWidget {
  final String videoPath;

  const _VideoPreview({required this.videoPath});

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.videoPath))
      ..initialize().then((_) {
        setState(() => _initialized = true);
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: _controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(_controller),
            GestureDetector(
              onTap: () {
                setState(() {
                  _controller.value.isPlaying
                      ? _controller.pause()
                      : _controller.play();
                });
              },
              child: AnimatedOpacity(
                opacity: _controller.value.isPlaying ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(12),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageGrid extends StatelessWidget {
  final List<String> imagePaths;

  const _ImageGrid({required this.imagePaths});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: imagePaths.length,
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FullscreenImagePage(
                  imagePaths: imagePaths,
                  initialIndex: index,
                ),
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(imagePaths[index]),
              fit: BoxFit.cover,
            ),
          ),
        );
      },
    );
  }
}

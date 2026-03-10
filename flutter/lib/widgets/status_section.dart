import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../viewmodels/download_viewmodel.dart';

class StatusSection extends StatelessWidget {
  const StatusSection({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DownloadViewModel>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Error message
        if (vm.errorMessage != null)
          _StatusCard(
            color: Theme.of(context).colorScheme.errorContainer,
            textColor: Theme.of(context).colorScheme.onErrorContainer,
            icon: Icons.error_outline,
            message: vm.errorMessage!,
          ),

        // Success message
        if (vm.successMessage != null)
          _StatusCard(
            color: Colors.green.shade50,
            textColor: Colors.green.shade800,
            icon: Icons.check_circle_outline,
            message: vm.successMessage!,
          ),

        // Loading indicator
        if (vm.isLoading) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          vm.downloadProgress != null
                              ? '下载中 ${(vm.downloadProgress! * 100).toInt()}%'
                              : '解析中...',
                        ),
                      ),
                      TextButton(
                        onPressed: vm.cancelDownload,
                        child: const Text('取消'),
                      ),
                    ],
                  ),
                  if (vm.downloadProgress != null) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: vm.downloadProgress,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  final Color color;
  final Color textColor;
  final IconData icon;
  final String message;

  const _StatusCard({
    required this.color,
    required this.textColor,
    required this.icon,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: textColor, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: textColor, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

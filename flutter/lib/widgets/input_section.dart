import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../viewmodels/download_viewmodel.dart';

class InputSection extends StatefulWidget {
  const InputSection({super.key});

  @override
  State<InputSection> createState() => _InputSectionState();
}

class _InputSectionState extends State<InputSection> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DownloadViewModel>();

    // Sync controller with viewmodel when pasted from clipboard
    if (_controller.text != vm.inputText) {
      _controller.text = vm.inputText;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: vm.inputText.length),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          onChanged: vm.updateInput,
          maxLines: 4,
          minLines: 3,
          decoration: InputDecoration(
            hintText: '粘贴分享链接到这里...',
            border: const OutlineInputBorder(),
            suffixIcon: vm.inputText.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _controller.clear();
                      vm.clearInput();
                    },
                  )
                : null,
          ),
          enabled: !vm.isLoading,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: vm.isLoading
                    ? null
                    : () async {
                        await vm.pasteFromClipboard();
                        _controller.text = vm.inputText;
                      },
                icon: const Icon(Icons.paste),
                label: const Text('粘贴'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: vm.isLoading || vm.inputText.trim().isEmpty
                    ? null
                    : () => vm.processInput(),
                icon: const Icon(Icons.download),
                label: const Text('下载'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

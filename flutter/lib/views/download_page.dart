import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../viewmodels/download_viewmodel.dart';
import '../widgets/header_section.dart';
import '../widgets/input_section.dart';
import '../widgets/status_section.dart';
import '../widgets/preview_section.dart';
import 'cookie_settings_page.dart';

class DownloadPage extends StatelessWidget {
  const DownloadPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DownloadViewModel(),
      child: const _DownloadPageContent(),
    );
  }
}

class _DownloadPageContent extends StatelessWidget {
  const _DownloadPageContent();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VideoPick'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.cookie_outlined),
            tooltip: 'Cookie 设置',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CookieSettingsPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HeaderSection(),
              SizedBox(height: 20),
              InputSection(),
              SizedBox(height: 16),
              StatusSection(),
              SizedBox(height: 16),
              PreviewSection(),
            ],
          ),
        ),
      ),
    );
  }
}

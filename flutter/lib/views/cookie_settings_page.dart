import 'package:flutter/material.dart';
import '../services/cookie_store.dart';

class CookieSettingsPage extends StatefulWidget {
  const CookieSettingsPage({super.key});

  @override
  State<CookieSettingsPage> createState() => _CookieSettingsPageState();
}

class _CookieSettingsPageState extends State<CookieSettingsPage> {
  final _controllers = <String, TextEditingController>{};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadCookies();
  }

  Future<void> _loadCookies() async {
    for (final platform in CookieStore.supportedPlatforms) {
      final cookies = await CookieStore.getCookies(platform.platform);
      for (final field in platform.fields) {
        final key = '${platform.platform}::${field.key}';
        _controllers[key] =
            TextEditingController(text: cookies[field.key] ?? '');
      }
    }
    setState(() => _loaded = true);
  }

  Future<void> _saveCookies() async {
    for (final platform in CookieStore.supportedPlatforms) {
      final cookies = <String, String>{};
      for (final field in platform.fields) {
        final key = '${platform.platform}::${field.key}';
        final value = _controllers[key]?.text ?? '';
        if (value.isNotEmpty) {
          cookies[field.key] = value;
        }
      }
      await CookieStore.saveCookies(platform.platform, cookies);
    }
  }

  Future<void> _clearPlatform(String platform) async {
    await CookieStore.clearCookies(platform);
    for (final p in CookieStore.supportedPlatforms) {
      if (p.platform == platform) {
        for (final field in p.fields) {
          _controllers['${platform}::${field.key}']?.clear();
        }
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cookie 设置'),
        actions: [
          TextButton(
            onPressed: () async {
              await _saveCookies();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cookie 已保存')),
                );
                Navigator.pop(context);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final platform in CookieStore.supportedPlatforms) ...[
                  _buildPlatformSection(platform),
                  const SizedBox(height: 24),
                ],
              ],
            ),
    );
  }

  Widget _buildPlatformSection(PlatformCookieConfig platform) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  platform.displayName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                TextButton(
                  onPressed: () => _clearPlatform(platform.platform),
                  child: const Text('清除', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final field in platform.fields) ...[
              TextField(
                controller:
                    _controllers['${platform.platform}::${field.key}'],
                decoration: InputDecoration(
                  labelText: field.displayName,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              platform.footerText,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

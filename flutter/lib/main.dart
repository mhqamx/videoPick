import 'package:flutter/material.dart';
import 'views/download_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VideoPickApp());
}

class VideoPickApp extends StatelessWidget {
  const VideoPickApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VideoPick',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      home: const DownloadPage(),
    );
  }
}

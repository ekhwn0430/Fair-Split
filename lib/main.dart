import 'package:flutter/material.dart';

import 'screens/receipt_upload_screen.dart';
import 'services/gemini_receipt_service.dart';
import 'services/receipt_storage_service.dart';

/// 실행 시 `--dart-define=GEMINI_API_KEY=발급받은키`로 전달한다.
const _geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fair Split',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: _geminiApiKey.isEmpty
          ? const _MissingApiKeyScreen()
          : ReceiptUploadScreen(
              service: GeminiReceiptService(apiKey: _geminiApiKey),
              storage: ReceiptStorageService(),
            ),
    );
  }
}

/// GEMINI_API_KEY가 전달되지 않았을 때 보여주는 안내 화면.
class _MissingApiKeyScreen extends StatelessWidget {
  const _MissingApiKeyScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'GEMINI_API_KEY가 설정되지 않았습니다.\n'
            '--dart-define=GEMINI_API_KEY=발급받은키 옵션으로 실행해 주세요.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

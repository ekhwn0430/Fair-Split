// 실제 기기나 실제 Gemini API 키 없이 영수증 업로드 -> 분석 -> 수정 화면 전체 흐름을
// 끝까지 검증하는 테스트. image_picker는 플랫폼 채널을 모킹하고, Gemini 호출은
// GenerativeModel의 httpClient를 가짜 응답으로 대체한다.
import 'dart:convert';
import 'dart:io';

import 'package:fair_split/screens/receipt_edit_screen.dart';
import 'package:fair_split/screens/receipt_upload_screen.dart';
import 'package:fair_split/services/gemini_receipt_service.dart';
import 'package:fair_split/services/receipt_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('영수증 업로드부터 수정 화면까지 전체 흐름', (tester) async {
    final tempImage = await File(
      '${Directory.systemTemp.path}/fake_receipt_test.jpg',
    ).writeAsBytes([0, 1, 2, 3]);
    addTearDown(() => tempImage.delete());

    const pickerChannel = MethodChannel('plugins.flutter.io/image_picker');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pickerChannel,
      (call) async => call.method == 'pickImage' ? tempImage.path : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        pickerChannel,
        null,
      ),
    );

    final fakeAnalysisJson = jsonEncode({
      'items': [
        {
          'name': '소주',
          'price': 4000,
          'quantity': 1,
          'category': 'regular_alcohol',
        },
        {'name': '삼겹살', 'price': 18000, 'quantity': 1, 'category': 'food'},
      ],
      'paidAt': '2026-11-05T20:30:00',
      'totalAmount': 22000,
    });

    final mockClient = MockClient((request) async {
      // 로딩 상태가 프레임에 반영될 시간을 주기 위한 지연.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'role': 'model',
                'parts': [
                  {'text': fakeAnalysisJson},
                ],
              },
              'finishReason': 'STOP',
            },
          ],
        }),
        200,
      );
    });

    final service = GeminiReceiptService.withModel(
      GenerativeModel(
        model: 'test-model',
        apiKey: 'test-key',
        httpClient: mockClient,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReceiptUploadScreen(
          service: service,
          storage: ReceiptStorageService(),
        ),
      ),
    );

    // 1. 개인정보 안내 문구가 보인다.
    expect(
      find.text('영수증 텍스트 인식을 위해 이미지 데이터가 Google Gemini API로 전송됩니다.'),
      findsOneWidget,
    );

    // 2. 갤러리 버튼을 누르면 이미지를 선택하고, Gemini 전송 동의 안내가 뜬다.
    await tester.tap(find.text('갤러리'));
    await tester.pump();
    expect(find.text('영수증 이미지 전송 안내'), findsOneWidget);

    // 3. 동의해야 분석이 시작된다.
    await tester.tap(find.text('동의하고 분석'));
    await tester.pump();
    expect(find.text('영수증을 분석하는 중입니다...'), findsOneWidget);

    // 4. 분석이 끝나면 ReceiptEditScreen으로 이동하고 분석 결과가 반영된다.
    //
    // pumpAndSettle()은 쓸 수 없다: _pickAndAnalyze는 Navigator.push가 반환하는
    // Future(= 화면이 pop될 때 완료)를 기다리는 중이라 _isAnalyzing이 true로 남아
    // 있고, 그 아래 ReceiptUploadScreen의 CircularProgressIndicator가 계속
    // 애니메이션을 돌려서 "더 그릴 프레임이 없는" 상태가 영영 오지 않는다.
    await tester.pump(const Duration(milliseconds: 100)); // mock 지연 해소
    await tester.pump(const Duration(milliseconds: 300)); // 화면 전환 애니메이션

    expect(find.byType(ReceiptEditScreen), findsOneWidget);
    expect(find.text('소주'), findsOneWidget);
    expect(find.text('삼겹살'), findsOneWidget);
    expect(find.text('항목 합계'), findsOneWidget);
    expect(find.text('22,000원'), findsOneWidget);
    expect(find.text('22000'), findsOneWidget); // 영수증 총액 입력 필드
  });
}

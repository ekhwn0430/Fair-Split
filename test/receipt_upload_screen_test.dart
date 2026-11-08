// 실제 Gemini API를 호출하지 않고, Gemini 전송 동의 안내(취소 시 API 미호출)와
// 분석 실패 시 보여주는 오류 메시지 생성 로직을 검증하는 테스트.
//
// image_picker는 플랫폼 채널을 모킹한다(receipt_flow_test.dart와 같은 방식).
// 다만 사진을 고른 뒤 실제로 분석까지 끝까지 진행되는 경로(실제 파일 읽기 +
// 네트워크 응답 처리)는 여기서 끝까지 확인하지 않는다: XFile.readAsBytes()
// 같은 진짜 비동기 I/O는 testWidgets의 가짜 비동기(FakeAsync) 영역 안에서
// 시작되면 이후 tester.runAsync()로도 완료시킬 수 없어(이미 다른 Zone에서
// 생성된 Future라서), receipt_flow_test.dart가 겪는 것과 같은 종류의 무한
// 대기로 이어진다. 그래서:
// - '취소' 경로는 그 실제 I/O 지점에 도달하기 전에 멈추므로 끝까지 검증한다.
// - '동의' 경로는 기존 분석 흐름이 실제로 시작되는지(분석 중 상태로
//   전환되는지)까지만 확인한다.
// - 오류 메시지를 만드는 로직(describeAnalysisFailure)은 위젯/비동기 없이
//   순수 함수 단위 테스트로 모든 실패 케이스를 확인한다.
import 'dart:io';

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
  group('describeAnalysisFailure', () {
    test('GeminiReceiptService가 만든 구체적인 안내 문구를 그대로 쓰고 재시도 방법을 덧붙인다', () {
      const error = ReceiptAnalysisException(
        '무료 API 사용 한도에 도달했습니다. 추가 호출 없이 직접 입력을 이용해 주세요.',
      );

      final message = describeAnalysisFailure(error);

      expect(
        message,
        '무료 API 사용 한도에 도달했습니다. 추가 호출 없이 직접 입력을 이용해 주세요.\n'
        '카메라 또는 갤러리 버튼으로 다시 시도해 주세요.',
      );
    });

    test('네트워크 오류·응답 파싱 실패 등 다른 ReceiptAnalysisException도 메시지가 그대로 보존된다', () {
      for (final message in [
        '네트워크 연결에 실패했습니다.',
        '영수증 데이터 해석에 실패했습니다.',
        'Gemini 서버 또는 모델에 연결할 수 없습니다.',
        'API 키 인증에 실패했습니다.',
      ]) {
        final result = describeAnalysisFailure(ReceiptAnalysisException(message));
        expect(result, startsWith(message));
        expect(result, contains('카메라 또는 갤러리 버튼으로 다시 시도해 주세요'));
      }
    });

    test('ReceiptAnalysisException이 아닌 예기치 못한 오류는 일반적인 안내로 대체한다', () {
      final message = describeAnalysisFailure(Exception('뭔가 알 수 없는 오류'));

      expect(
        message,
        '영수증을 분석하지 못했습니다.\n카메라 또는 갤러리 버튼으로 다시 시도해 주세요.',
      );
    });
  });

  testWidgets(
    '동의 안내에서 취소하면 Gemini API를 호출하지 않고 업로드 화면에 그대로 머문다',
    (tester) async {
      final tempImage = await tester.runAsync(
        () => File(
          '${Directory.systemTemp.path}/consent_cancel_test.jpg',
        ).writeAsBytes([0, 1, 2, 3]),
      );
      addTearDown(() => tester.runAsync(() => tempImage!.delete()));

      const pickerChannel = MethodChannel('plugins.flutter.io/image_picker');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        pickerChannel,
        (call) async => call.method == 'pickImage' ? tempImage!.path : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          pickerChannel,
          null,
        ),
      );

      var callCount = 0;
      final mockClient = MockClient((request) async {
        callCount += 1;
        return http.Response('{}', 200);
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

      await tester.tap(find.text('갤러리'));
      await tester.pump();

      expect(find.text('영수증 이미지 전송 안내'), findsOneWidget);
      expect(
        find.textContaining('Google Gemini 서비스로 전송됩니다'),
        findsOneWidget,
      );

      await tester.tap(find.text('취소'));
      await tester.pump();

      // 다이얼로그가 닫히고 업로드 화면에 그대로 머문다.
      expect(find.text('영수증 이미지 전송 안내'), findsNothing);
      expect(find.byType(ReceiptUploadScreen), findsOneWidget);
      expect(find.text('영수증을 분석하는 중입니다...'), findsNothing);

      // Gemini API는 한 번도 호출되지 않았다.
      expect(callCount, 0);
    },
  );

  testWidgets('동의하면 기존 분석 흐름이 실제로 시작된다', (tester) async {
    final tempImage = await tester.runAsync(
      () => File(
        '${Directory.systemTemp.path}/consent_accept_test.jpg',
      ).writeAsBytes([0, 1, 2, 3]),
    );
    addTearDown(() => tester.runAsync(() => tempImage!.delete()));

    const pickerChannel = MethodChannel('plugins.flutter.io/image_picker');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pickerChannel,
      (call) async => call.method == 'pickImage' ? tempImage!.path : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        pickerChannel,
        null,
      ),
    );

    final mockClient = MockClient((request) async => http.Response('{}', 200));
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

    await tester.tap(find.text('갤러리'));
    await tester.pump();
    await tester.tap(find.text('동의하고 분석'));
    await tester.pump();

    // 동의 후에만 기존 분석 흐름(분석 중 상태)이 시작된다.
    expect(find.text('영수증 이미지 전송 안내'), findsNothing);
    expect(find.text('영수증을 분석하는 중입니다...'), findsOneWidget);
  });
}

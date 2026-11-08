// 실제 Gemini API를 호출하지 않고, 저장된 영수증 상세 화면에서
// '이 영수증으로 정산하기' 버튼이 참여자 입력 화면으로 바로 이동하며
// 개인 주문 분류를 보존하는지 검증하는 테스트.
import 'dart:convert';
import 'dart:io';

import 'package:fair_split/models/settlement_models.dart';
import 'package:fair_split/screens/participant_input_screen.dart';
import 'package:fair_split/screens/receipt_detail_screen.dart';
import 'package:fair_split/services/receipt_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 1x1 투명 PNG(가장 작은 유효 이미지). Image.file이 디코딩 오류 없이
// 렌더링할 수 있도록 실제 이미지 바이트를 쓴다.
const _minimalPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    '+A8AAQUBAScY42YAAAAASUVORK5CYII=';

void main() {
  testWidgets(
    '저장된 영수증 상세에서 정산하기 버튼을 누르면 Gemini 재호출 없이 '
    '참여자 입력 화면으로 이동하고, 개인 주문 분류가 보존된다',
    (tester) async {
      // testWidgets 안에서는 가짜 비동기(FakeAsync) 타이머가 돌기 때문에,
      // 실제 파일 I/O 같은 진짜 비동기 작업은 tester.runAsync()로 감싸야
      // Future가 끝까지 진행된다. 감싸지 않으면 awai가 영영 끝나지 않는다
      // (receipt_flow_test.dart의 무한 대기 문제와 같은 원인).
      final tempImage = await tester.runAsync(
        () => File(
          '${Directory.systemTemp.path}/fake_receipt_detail_test.png',
        ).writeAsBytes(base64Decode(_minimalPngBase64)),
      );
      addTearDown(
        () => tester.runAsync(() async {
          try {
            await tempImage!.delete();
          } catch (_) {
            // 이미지 디코더가 아직 파일을 들고 있을 수 있다. 임시 디렉터리에
            // 남는 테스트용 파일 하나는 테스트 결과에 영향이 없다.
          }
        }),
      );

      // 영수증 수정 화면에서 저장될 때와 같은 방식으로 분석 결과를 만든다.
      final workingSet = ReceiptWorkingSet(
        items: [
          SettlementItem(
            id: 'a',
            name: '삼겹살',
            price: 18000,
            quantity: 1,
            category: ItemCategory.food,
          ),
          SettlementItem(
            id: 'b',
            name: '생맥주(막내)',
            price: 8000,
            quantity: 1,
            category: ItemCategory.personalOrder,
          ),
        ],
        totalAmount: 26000,
      );
      final analysis = toArchivedReceiptAnalysis(workingSet);

      final receipt = StoredReceipt(
        id: 'test-id',
        analysis: analysis,
        imageFile: tempImage!,
        savedAt: DateTime(2026, 11, 5),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ReceiptDetailScreen(
            receipt: receipt,
            storage: ReceiptStorageService(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('이 영수증으로 정산하기'), findsOneWidget);

      await tester.tap(find.text('이 영수증으로 정산하기'));
      await tester.pump(); // 버튼 탭 반영
      await tester.pump(const Duration(milliseconds: 300)); // 화면 전환 애니메이션

      expect(find.byType(ParticipantInputScreen), findsOneWidget);
      // 개인 주문으로 분류했던 항목이 다시 '개인 주문 배정' 섹션에 나타난다.
      expect(find.text('개인 주문 배정'), findsOneWidget);
      // push된 화면 아래에 이전 상세 화면도 여전히 남아 있으므로, 새 화면
      // 안으로 범위를 좁혀서 찾는다.
      expect(
        find.descendant(
          of: find.byType(ParticipantInputScreen),
          matching: find.textContaining('생맥주(막내)'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    '사진 없이 직접 입력한 영수증은 상세 화면에서 이미지 대신 안내 문구를 보여주고, '
    '재정산도 Gemini 재호출 없이 그대로 동작한다',
    (tester) async {
      final workingSet = ReceiptWorkingSet(
        items: [
          SettlementItem(
            id: 'a',
            name: '아메리카노',
            price: 4500,
            quantity: 2,
            category: ItemCategory.food,
          ),
        ],
        totalAmount: 9000,
      );
      final analysis = toArchivedReceiptAnalysis(workingSet);

      final receipt = StoredReceipt(
        id: 'manual-test-id',
        analysis: analysis,
        imageFile: null,
        savedAt: DateTime(2026, 11, 5),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ReceiptDetailScreen(
            receipt: receipt,
            storage: ReceiptStorageService(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('직접 입력한 영수증'), findsOneWidget);
      expect(find.byType(Image), findsNothing);

      await tester.tap(find.text('이 영수증으로 정산하기'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 일반('음식') 항목은 참여자 입력 화면에 개별로 나열되지 않으므로,
      // 화면 자체가 저장된 데이터로 정상 진입했는지만 확인한다.
      expect(find.byType(ParticipantInputScreen), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ParticipantInputScreen),
          matching: find.text('참여자'),
        ),
        findsOneWidget,
      );
    },
  );
}

// 실제 Gemini API 호출 없이, 이미 분석된 결과(ReceiptAnalysis)를 바로
// ReceiptEditScreen에 주입해 수정 화면의 계산 로직만 검증하는 테스트.
import 'package:fair_split/models/settlement_models.dart';
import 'package:fair_split/screens/receipt_edit_screen.dart';
import 'package:fair_split/services/gemini_receipt_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('수량을 바꾸면 줄 합계와 항목 합계가 즉시 갱신되고, 중복으로 곱해지지 않는다', (
    tester,
  ) async {
    const analysis = ReceiptAnalysis(
      items: [
        ReceiptItem(
          name: '삼겹살',
          price: 18000,
          quantity: 1,
          category: ReceiptItemCategory.food,
        ),
      ],
      totalAmount: 18000,
    );

    ReceiptWorkingSet? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await Navigator.of(context).push<ReceiptWorkingSet>(
                  MaterialPageRoute(
                    builder: (context) =>
                        const ReceiptEditScreen(analysis: analysis),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 초기 단가는 18000(= 18000원 / 수량 1)이고, 줄 합계·항목 합계 모두
    // 18,000원이다.
    expect(find.text('줄 합계 18,000원'), findsOneWidget);
    expect(find.text('18,000원'), findsOneWidget);

    // TextField 순서: 메뉴명(0), 단가(1), 수량(2), 영수증 총액(3).
    final textFields = find.byType(TextField);

    // 수량을 2로 바꾼다. 단가(18000)는 그대로 두고 수량만 바꿨으므로
    // 줄 합계는 18000 * 2 = 36,000원이어야 한다(가격을 중복으로 곱하지 않음).
    await tester.enterText(textFields.at(2), '2');
    await tester.pump();

    expect(find.text('줄 합계 36,000원'), findsOneWidget);
    expect(find.text('36,000원'), findsOneWidget);

    // 영수증 총액은 자동으로 바뀌지 않고, 항목 합계와 달라졌다는 경고가 뜬다.
    expect(find.textContaining('항목 합계와 영수증 총액이'), findsOneWidget);

    // 단가도 바꿔 보면 줄 합계가 다시 갱신된다.
    await tester.enterText(textFields.at(1), '10000');
    await tester.pump();

    expect(find.text('줄 합계 20,000원'), findsOneWidget);
    expect(find.text('20,000원'), findsOneWidget);

    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.items.single.price, 20000);
    expect(result!.items.single.quantity, 2);
    // 영수증 총액 입력 필드는 사용자가 손대지 않았으므로 원본 그대로 유지된다.
    expect(result!.totalAmount, 18000);
  });

  testWidgets('Gemini가 분류한 주류 항목은 메뉴명 키워드로 등급이 보정된다', (tester) async {
    const analysis = ReceiptAnalysis(
      items: [
        // Gemini가 '하이볼'을 일반 주류로 잘못 분류했다고 가정한다.
        ReceiptItem(
          name: '하이볼',
          price: 12000,
          quantity: 1,
          category: ReceiptItemCategory.regularAlcohol,
        ),
        ReceiptItem(
          name: '삼겹살',
          price: 18000,
          quantity: 1,
          category: ReceiptItemCategory.food,
        ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(home: ReceiptEditScreen(analysis: analysis)),
    );
    await tester.pump();

    // '하이볼'은 메뉴명으로 '고가주류'로 보정되어 표시된다.
    expect(find.text('고가주류'), findsOneWidget);
    expect(find.text('일반주류'), findsNothing);
    // '음식'으로 분류된 항목은 보정 대상이 아니므로 그대로 유지된다.
    expect(find.text('음식'), findsOneWidget);
  });
}

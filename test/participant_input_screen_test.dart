// 개인 주문 수량을 여러 참여자에게 나눠 배정하는 참여자 입력 화면의
// 검증 로직을 테스트한다. Gemini를 호출하지 않고, 이미 만들어진
// ReceiptWorkingSet을 바로 주입한다.
//
// pumpAndSettle()은 쓰지 않는다: 이름 입력란에 포커스가 가면 커서 깜빡임
// 타이머가 계속 새 프레임을 요구해 "더 그릴 프레임이 없는" 상태가 영영 오지
// 않는다(receipt_flow_test.dart의 무한 대기 문제와 같은 종류). 대신 필요한
// 만큼만 명시적으로 pump한다.
import 'package:fair_split/models/settlement_models.dart';
import 'package:fair_split/screens/participant_input_screen.dart';
import 'package:fair_split/screens/settlement_result_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 수량 증가(+)/감소(-) IconButton은 참여자 행마다 하나씩 반복되므로,
/// [participantIndex]번째 참여자 행의 버튼을 가리킨다.
Finder _incrementButton(int participantIndex) =>
    find.widgetWithIcon(IconButton, Icons.add_circle_outline).at(participantIndex);
Finder _decrementButton(int participantIndex) =>
    find.widgetWithIcon(IconButton, Icons.remove_circle_outline).at(participantIndex);

void main() {
  testWidgets(
    '개인 주문 수량이 다 배정되지 않으면 정산을 진행할 수 없고, 다 배정하면 진행할 수 있다',
    (tester) async {
      // 기본 테스트 화면(800x600)보다 내용이 길어 '정산하기' 버튼이 ListView
      // 뷰포트 밖으로 밀려나면 기본 Finder가 찾지 못한다. 화면을 충분히
      // 키워 스크롤 없이 모든 위젯이 뷰포트 안에 들어오게 한다.
      await tester.binding.setSurfaceSize(const Size(1080, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

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
            name: '파인애플맥주',
            price: 13500,
            quantity: 3,
            category: ItemCategory.personalOrder,
          ),
        ],
        totalAmount: 31500,
      );

      await tester.pumpWidget(
        MaterialApp(home: ParticipantInputScreen(workingSet: workingSet)),
      );
      await tester.pump();

      // 참여자 두 명의 이름을 입력한다.
      await tester.enterText(find.byType(TextField).first, '참여자1');
      await tester.pump();
      await tester.tap(find.text('참여자 추가'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(1), '참여자2');
      await tester.pump();

      FilledButton findSettleButton() => tester.widget<FilledButton>(
        find.ancestor(of: find.text('정산하기'), matching: find.byType(FilledButton)),
      );

      // 아직 아무도 배정하지 않았으므로 비활성화되고, 안내 문구가 보인다.
      expect(findSettleButton().onPressed, isNull);
      expect(
        find.textContaining('수량이 다 배정되지 않은 개인 주문이 있습니다'),
        findsOneWidget,
      );
      expect(find.text('배정 수량 0/3개 — 모두 배정해야 합니다'), findsOneWidget);

      // 참여자1에게 1개를 배정한다.
      await tester.tap(_incrementButton(0));
      await tester.pump();
      expect(find.text('배정 수량 1/3개 — 모두 배정해야 합니다'), findsOneWidget);
      expect(findSettleButton().onPressed, isNull);

      // 참여자2에게 2개를 배정한다(+ 두 번).
      await tester.tap(_incrementButton(1));
      await tester.pump();
      await tester.tap(_incrementButton(1));
      await tester.pump();

      // 3개(총수량)가 모두 배정되면 완료로 표시되고 버튼이 활성화된다.
      expect(find.text('배정 완료 (3/3개)'), findsOneWidget);
      expect(
        find.textContaining('수량이 다 배정되지 않은 개인 주문이 있습니다'),
        findsNothing,
      );
      expect(findSettleButton().onPressed, isNotNull);

      // 13,500원을 1개:2개로 나누면 4,500원/9,000원이 정확히 맞아야 한다.
      expect(find.text('4,500원'), findsOneWidget);
      expect(find.text('9,000원'), findsOneWidget);

      await tester.tap(find.text('정산하기'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SettlementResultScreen), findsOneWidget);
    },
  );

  testWidgets('이미 가득 배정된 항목에서는 + 버튼이 더 이상 늘어나지 않게 비활성화된다', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final workingSet = ReceiptWorkingSet(
      items: [
        SettlementItem(
          id: 'a',
          name: '할맥 500ml',
          price: 9400,
          quantity: 2,
          category: ItemCategory.personalOrder,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: ParticipantInputScreen(workingSet: workingSet)),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, '참여자1');
    await tester.pump();
    await tester.tap(find.text('참여자 추가'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), '참여자2');
    await tester.pump();

    // 참여자1에게 2개(전체 수량)를 모두 배정한다.
    await tester.tap(_incrementButton(0));
    await tester.pump();
    await tester.tap(_incrementButton(0));
    await tester.pump();

    expect(find.text('배정 완료 (2/2개)'), findsOneWidget);

    // 더 늘릴 수량이 없으므로 두 참여자 모두 + 버튼이 비활성화된다.
    final incrementFor0 = tester.widget<IconButton>(_incrementButton(0));
    final incrementFor1 = tester.widget<IconButton>(_incrementButton(1));
    expect(incrementFor0.onPressed, isNull);
    expect(incrementFor1.onPressed, isNull);

    // 참여자1의 - 버튼으로 1개를 돌려주면 다시 배정할 수 있는 수량이 생긴다.
    await tester.tap(_decrementButton(0));
    await tester.pump();

    expect(find.text('배정 수량 1/2개 — 모두 배정해야 합니다'), findsOneWidget);
    final incrementAfterDecrement = tester.widget<IconButton>(_incrementButton(1));
    expect(incrementAfterDecrement.onPressed, isNotNull);
  });

  testWidgets('수량이 1개인 개인 주문도 참여자 한 명에게 자연스럽게 배정할 수 있다', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final workingSet = ReceiptWorkingSet(
      items: [
        SettlementItem(
          id: 'a',
          name: '생맥주(막내)',
          price: 8000,
          quantity: 1,
          category: ItemCategory.personalOrder,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: ParticipantInputScreen(workingSet: workingSet)),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, '참여자1');
    await tester.pump();

    FilledButton findSettleButton() => tester.widget<FilledButton>(
      find.ancestor(of: find.text('정산하기'), matching: find.byType(FilledButton)),
    );

    expect(findSettleButton().onPressed, isNull);

    await tester.tap(_incrementButton(0));
    await tester.pump();

    expect(find.text('배정 완료 (1/1개)'), findsOneWidget);
    expect(findSettleButton().onPressed, isNotNull);
  });

  testWidgets('참여자를 삭제하면 그 참여자에게 배정된 개인 주문 수량이 함께 풀린다', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final workingSet = ReceiptWorkingSet(
      items: [
        SettlementItem(
          id: 'a',
          name: '생맥주(막내)',
          price: 8000,
          quantity: 1,
          category: ItemCategory.personalOrder,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: ParticipantInputScreen(workingSet: workingSet)),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).at(0), '참여자1');
    await tester.pump();

    await tester.tap(find.text('참여자 추가'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), '참여자2');
    await tester.pump();

    // 참여자2에게 1개(전체 수량)를 배정한다.
    await tester.tap(_incrementButton(1));
    await tester.pump();

    FilledButton findSettleButton() => tester.widget<FilledButton>(
      find.ancestor(of: find.text('정산하기'), matching: find.byType(FilledButton)),
    );

    expect(findSettleButton().onPressed, isNotNull);

    // 참여자2를 삭제하면 그 배정이 함께 풀려 다시 경고가 보인다.
    // (+/- 배정 버튼도 IconButton이라, 삭제 버튼은 툴팁으로 특정한다.)
    await tester.tap(find.byTooltip('참여자 삭제').last);
    await tester.pump();

    expect(
      find.textContaining('수량이 다 배정되지 않은 개인 주문이 있습니다'),
      findsOneWidget,
    );
    expect(findSettleButton().onPressed, isNull);
  });
}

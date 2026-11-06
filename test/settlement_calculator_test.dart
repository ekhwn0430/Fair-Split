// 개인 주문 비용이 배정 수량에 비례해 정확히 나뉘는지, 그리고 배정되지
// 않은 수량이 다른 참여자에게 자동으로 분배되지 않는지 계산 로직만
// 단독으로 검증하는 테스트. Gemini를 호출하지 않는다.
import 'package:fair_split/models/settlement_models.dart';
import 'package:fair_split/services/settlement_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final calculator = DemoSettlementCalculator();

  test('담당자 한 명에게 전부 배정된 개인 주문은 그 담당자에게만 전액 부과된다', () {
    final result = calculator.calculate(
      items: [
        SettlementItem(
          id: 'a',
          name: '생맥주(막내)',
          price: 8000,
          quantity: 1,
          category: ItemCategory.personalOrder,
          assignments: const [
            PersonalOrderAssignment(participantId: 'p1', quantity: 1),
          ],
        ),
      ],
      participants: const [
        Participant(id: 'p1', name: '철수'),
        Participant(id: 'p2', name: '영희'),
      ],
    );

    final p1 = result.breakdowns.firstWhere((b) => b.participantId == 'p1');
    final p2 = result.breakdowns.firstWhere((b) => b.participantId == 'p2');

    expect(p1.personalOrderShare, 8000);
    expect(p2.personalOrderShare, 0);
    expect(result.personalOrderTotal, 8000);
  });

  test('할맥 500ml 2잔(9,400원)을 한 참여자가 모두 배정받으면 전액을 부담한다', () {
    final result = calculator.calculate(
      items: [
        SettlementItem(
          id: 'a',
          name: '할맥 500ml',
          price: 9400,
          quantity: 2,
          category: ItemCategory.personalOrder,
          assignments: const [
            PersonalOrderAssignment(participantId: 'p1', quantity: 2),
          ],
        ),
      ],
      participants: const [
        Participant(id: 'p1', name: '참여자1'),
        Participant(id: 'p2', name: '참여자2'),
      ],
    );

    final p1 = result.breakdowns.firstWhere((b) => b.participantId == 'p1');
    expect(p1.personalOrderShare, 9400);
    expect(result.personalOrderTotal, 9400);
    expect(result.isBalanced, isTrue);
  });

  test(
    '파인애플맥주 3잔(13,500원)을 참여자2가 1잔, 참여자3이 2잔 배정받으면 '
    '수량에 비례해 4,500원/9,000원으로 정확히 나뉜다',
    () {
      final result = calculator.calculate(
        items: [
          SettlementItem(
            id: 'a',
            name: '파인애플맥주',
            price: 13500,
            quantity: 3,
            category: ItemCategory.personalOrder,
            assignments: const [
              PersonalOrderAssignment(participantId: 'p2', quantity: 1),
              PersonalOrderAssignment(participantId: 'p3', quantity: 2),
            ],
          ),
        ],
        participants: const [
          Participant(id: 'p1', name: '참여자1'),
          Participant(id: 'p2', name: '참여자2'),
          Participant(id: 'p3', name: '참여자3'),
        ],
      );

      final p1 = result.breakdowns.firstWhere((b) => b.participantId == 'p1');
      final p2 = result.breakdowns.firstWhere((b) => b.participantId == 'p2');
      final p3 = result.breakdowns.firstWhere((b) => b.participantId == 'p3');

      expect(p1.personalOrderShare, 0);
      expect(p2.personalOrderShare, 4500);
      expect(p3.personalOrderShare, 9000);
      expect(result.personalOrderTotal, 13500);
      expect(result.isBalanced, isTrue);
    },
  );

  test(
    '나눠떨어지지 않는 금액도 참여자별 합계가 항목 총액과 정확히 같다(원 단위 나머지 처리)',
    () {
      // 10,000원을 3개로 나누면 1개당 3333.33...원이라 그대로는 나눠지지
      // 않는다. 나머지 1원씩을 앞에서부터 보정해 합계가 정확히 맞아야 한다.
      final result = calculator.calculate(
        items: [
          SettlementItem(
            id: 'a',
            name: '나눠마시는 술',
            price: 10000,
            quantity: 3,
            category: ItemCategory.personalOrder,
            assignments: const [
              PersonalOrderAssignment(participantId: 'p1', quantity: 1),
              PersonalOrderAssignment(participantId: 'p2', quantity: 2),
            ],
          ),
        ],
        participants: const [
          Participant(id: 'p1', name: '참여자1'),
          Participant(id: 'p2', name: '참여자2'),
        ],
      );

      final p1 = result.breakdowns.firstWhere((b) => b.participantId == 'p1');
      final p2 = result.breakdowns.firstWhere((b) => b.participantId == 'p2');

      // 1개당 단가: [3334, 3333, 3333] (나머지 1원은 첫 단위에 붙는다).
      expect(p1.personalOrderShare, 3334);
      expect(p2.personalOrderShare, 6666);
      expect(p1.personalOrderShare + p2.personalOrderShare, 10000);
      expect(result.personalOrderTotal, 10000);
      expect(result.isBalanced, isTrue);
    },
  );

  test(
    '일부 수량만 배정된(방어적 상황) 개인 주문은 배정되지 않은 수량만큼 '
    '다른 참여자에게 자동으로 분배되지 않는다',
    () {
      // 참여자 입력 화면이 전량 배정을 강제하지만, 계산 로직 자체도
      // 방어적으로 배정되지 않은 수량을 자동 분배하지 않아야 한다.
      final result = calculator.calculate(
        items: [
          SettlementItem(
            id: 'a',
            name: '파인애플맥주',
            price: 13500,
            quantity: 3,
            category: ItemCategory.personalOrder,
            assignments: const [
              PersonalOrderAssignment(participantId: 'p2', quantity: 1),
              // 나머지 2잔은 배정되지 않은 상태.
            ],
          ),
        ],
        participants: const [
          Participant(id: 'p1', name: '참여자1'),
          Participant(id: 'p2', name: '참여자2'),
        ],
      );

      final p2 = result.breakdowns.firstWhere((b) => b.participantId == 'p2');
      expect(p2.personalOrderShare, 4500);
      // 배정되지 않은 2잔의 금액(9,000원)은 누구의 몫에도 더해지지 않아,
      // 항목 합계와 참여자별 합계가 어긋나며 드러난다.
      expect(result.personalOrderTotal, 13500);
      expect(result.isBalanced, isFalse);
    },
  );
}

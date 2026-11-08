// FairSettlementCalculator 단위 테스트. 기댓값은 같은 알고리즘의 파이썬
// 참조 구현(docs/calculator_reference.py)으로 따로 계산해 교차 확인했다.
import 'dart:math';

import 'package:fair_split/models/settlement_models.dart';
import 'package:fair_split/services/fair_settlement_calculator.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';

SettlementItem _item(
  String id,
  int price,
  int quantity,
  ItemCategory category, [
  Map<String, int> assignments = const {},
]) {
  return SettlementItem(
    id: id,
    name: id,
    price: price,
    quantity: quantity,
    category: category,
    assignments: [
      for (final entry in assignments.entries)
        PersonalOrderAssignment(participantId: entry.key, quantity: entry.value),
    ],
  );
}

ParticipantBreakdown _of(SettlementResult result, String id) =>
    result.breakdowns.firstWhere((b) => b.participantId == id);

void main() {
  // 19:00 시작, 22:00 결제. 기환 180분, 지인 150분(19:30 도착),
  // 상혁 120분(21:00 퇴장), 민수 120분(20:00 도착). 지인만 술을 안 마심.
  final start = DateTime(2026, 11, 7, 19, 0);
  final end = DateTime(2026, 11, 7, 22, 0);
  final participants = [
    Participant(id: 'hwan', name: '기환', arrivedAt: start, drankAlcohol: true),
    const Participant(
      id: 'jiin',
      name: '지인',
      joinTime: TimeOfDay(hour: 19, minute: 30),
    ),
    const Participant(
      id: 'hyuk',
      name: '상혁',
      leaveTime: TimeOfDay(hour: 21, minute: 0),
      drankAlcohol: true,
    ),
    Participant(
      id: 'minsu',
      name: '민수',
      arrivedAt: DateTime(2026, 11, 7, 20, 0),
      drankAlcohol: true,
    ),
  ];
  final items = [
    _item('삼겹살', 54000, 3, ItemCategory.food),
    _item('된장찌개', 7000, 1, ItemCategory.food),
    _item('참이슬', 20000, 4, ItemCategory.regularAlcohol),
    _item('하이볼', 18000, 2, ItemCategory.premiumAlcohol,
        {'jiin': 1, 'minsu': 1}),
    _item('콜라', 4000, 2, ItemCategory.personalOrder, {'jiin': 2}),
  ];

  group('실제 술자리 시나리오 (할인 3,000원, 100원 단위, 룰렛 당첨 민수)', () {
    final result = FairSettlementCalculator(
      startedAt: start,
      endedAt: end,
      remainderPayerId: 'minsu',
    ).calculate(
      items: items,
      participants: participants,
      receiptTotalAmount: 100000,
    );

    test('참석 시간을 도착·퇴장 기록으로 계산한다', () {
      expect(_of(result, 'hwan').attendedMinutes, 180);
      expect(_of(result, 'jiin').attendedMinutes, 150);
      expect(_of(result, 'hyuk').attendedMinutes, 120);
      expect(_of(result, 'minsu').attendedMinutes, 120);
      expect(result.isTimeWeighted, isTrue);
    });

    test('음식은 전원 시간 비례, 소주·맥주는 음주자끼리 시간 비례', () {
      expect(_of(result, 'hwan').foodShare, 19263);
      expect(_of(result, 'jiin').foodShare, 16053);
      expect(_of(result, 'hyuk').foodShare, 12842);
      expect(_of(result, 'minsu').foodShare, 12842);
      expect(_of(result, 'hwan').regularAlcoholShare, 8572);
      expect(_of(result, 'jiin').regularAlcoholShare, 0);
      expect(_of(result, 'hyuk').regularAlcoholShare, 5714);
      expect(_of(result, 'minsu').regularAlcoholShare, 5714);
    });

    test('고가 주류·개인 주문은 주문한 사람만 부담한다', () {
      expect(_of(result, 'jiin').premiumAlcoholShare, 9000);
      expect(_of(result, 'minsu').premiumAlcoholShare, 9000);
      expect(_of(result, 'hwan').premiumAlcoholShare, 0);
      expect(_of(result, 'jiin').personalOrderShare, 4000);
    });

    test('할인은 각자 부담 비율대로 나눈다', () {
      expect(_of(result, 'hwan').discountShare, -811);
      expect(_of(result, 'jiin').discountShare, -846);
      expect(_of(result, 'hyuk').discountShare, -540);
      expect(_of(result, 'minsu').discountShare, -803);
      expect(result.discountTotal, -3000);
    });

    test('100원 단위로 내리고 나머지는 룰렛 당첨자가 낸다', () {
      expect(_of(result, 'hwan').total, 27000);
      expect(_of(result, 'jiin').total, 28200);
      expect(_of(result, 'hyuk').total, 18000);
      expect(_of(result, 'minsu').total, 26800);
      expect(result.remainder, 100);
      expect(result.remainderPayerId, 'minsu');
    });

    test('부담액 합계 = 실제 결제 금액', () {
      expect(result.participantsGrandTotal, 100000);
      expect(result.isBalanced, isTrue);
    });
  });

  group('예외 입력은 정산을 막는다', () {
    test('술 항목이 있는데 음주자가 0명이면 계산하지 않는다', () {
      final calculator = FairSettlementCalculator();
      expect(
        () => calculator.calculate(
          items: [_item('참이슬', 5000, 1, ItemCategory.regularAlcohol)],
          participants: const [Participant(id: 'a', name: 'A')],
        ),
        throwsA(isA<SettlementInputException>()),
      );
    });

    test('음식 항목이 있는데 먹은 사람이 0명이면 계산하지 않는다', () {
      final problems = FairSettlementCalculator.validate(
        items: [_item('삼겹살', 18000, 1, ItemCategory.food)],
        participants: const [Participant(id: 'a', name: 'A', ateFood: false)],
      );
      expect(problems, hasLength(1));
    });

    test('고가 주류도 주문자를 모두 지정해야 한다', () {
      final problems = FairSettlementCalculator.validate(
        items: [_item('하이볼', 18000, 2, ItemCategory.premiumAlcohol, {'a': 1})],
        participants: const [Participant(id: 'a', name: 'A')],
      );
      expect(problems.single, contains('2개 중 1개'));
    });

    test('술 항목이 없으면 아무도 안 마셔도 정산된다', () {
      final result = FairSettlementCalculator().calculate(
        items: [_item('삼겹살', 18000, 1, ItemCategory.food)],
        participants: const [
          Participant(id: 'a', name: 'A'),
          Participant(id: 'b', name: 'B'),
        ],
      );
      expect(result.participantsGrandTotal, 18000);
      expect(_of(result, 'a').regularAlcoholShare, 0);
    });
  });

  group('시간 처리', () {
    test('자정을 넘긴 술자리: 23:30 도착, 01:30 결제면 120분', () {
      final result = FairSettlementCalculator(
        startedAt: DateTime(2026, 11, 7, 23, 0),
        endedAt: DateTime(2026, 11, 8, 1, 30),
        roundingUnit: 1,
      ).calculate(
        items: [_item('치킨', 30000, 1, ItemCategory.food)],
        participants: const [
          Participant(id: 'a', name: 'A'),
          Participant(
            id: 'b',
            name: 'B',
            joinTime: TimeOfDay(hour: 23, minute: 30),
          ),
        ],
      );
      expect(_of(result, 'a').attendedMinutes, 150);
      expect(_of(result, 'b').attendedMinutes, 120);
      expect(_of(result, 'a').total, 16667);
      expect(_of(result, 'b').total, 13333);
    });

    test('결제 시각이 없으면 시간 가중치 없이 1/n 한다', () {
      final result = FairSettlementCalculator(roundingUnit: 1).calculate(
        items: [_item('치킨', 30000, 1, ItemCategory.food)],
        participants: const [
          Participant(id: 'a', name: 'A'),
          Participant(id: 'b', name: 'B', joinTime: TimeOfDay(hour: 21, minute: 0)),
        ],
      );
      expect(result.isTimeWeighted, isFalse);
      expect(_of(result, 'a').total, 15000);
      expect(_of(result, 'b').total, 15000);
    });
  });

  test('같은 룰렛 시드면 화면을 다시 그려도 당첨자가 같다', () {
    String? winner(int seed) => FairSettlementCalculator(rouletteSeed: seed)
        .calculate(
          items: [_item('치킨', 20000, 1, ItemCategory.food)],
          participants: const [
            Participant(id: 'a', name: 'A'),
            Participant(id: 'b', name: 'B'),
            Participant(id: 'c', name: 'C'),
          ],
        )
        .remainderPayerId;
    expect(winner(42), winner(42));
  });

  test('무작위 입력 500개에서 공정성 성질이 항상 성립한다', () {
    final rng = Random(7);
    final categories = ItemCategory.values;
    var settled = 0;
    for (var trial = 0; trial < 500; trial++) {
      final n = rng.nextInt(6) + 1;
      final people = [
        for (var k = 0; k < n; k++)
          Participant(
            id: 'p$k',
            name: 'P$k',
            ateFood: rng.nextDouble() < 0.85,
            drankAlcohol: rng.nextDouble() < 0.6,
            joinTime: TimeOfDay(hour: 19 + rng.nextInt(3), minute: rng.nextInt(60)),
          ),
      ];
      final itemCount = rng.nextInt(8) + 1;
      final generated = [
        for (var k = 0; k < itemCount; k++)
          () {
            final category = categories[rng.nextInt(categories.length)];
            final quantity = rng.nextInt(3) + 1;
            final assignments = <String, int>{};
            if (category == ItemCategory.premiumAlcohol ||
                category == ItemCategory.personalOrder) {
              for (var q = 0; q < quantity; q++) {
                final who = people[rng.nextInt(n)].id;
                assignments[who] = (assignments[who] ?? 0) + 1;
              }
            }
            return _item('i$k', (rng.nextInt(60) + 1) * 500 + rng.nextInt(9),
                quantity, category, assignments);
          }(),
      ];
      final itemsTotal = generated.fold<int>(0, (s, i) => s + i.price);
      final receipt = rng.nextBool() ? itemsTotal : itemsTotal * 9 ~/ 10;

      if (FairSettlementCalculator.validate(
              items: generated, participants: people)
          .isNotEmpty) {
        continue;
      }
      final result = FairSettlementCalculator(
        startedAt: DateTime(2026, 11, 7, 19),
        endedAt: DateTime(2026, 11, 7, 23),
        rouletteSeed: trial,
      ).calculate(
        items: generated,
        participants: people,
        receiptTotalAmount: receipt,
      );
      settled++;

      // 총액 보존
      expect(result.participantsGrandTotal, receipt);
      for (final p in people) {
        final b = _of(result, p.id);
        // 비음주자 술값 0원, 안 먹은 사람 음식값 0원
        if (!p.drankAlcohol) expect(b.regularAlcoholShare, 0);
        if (!p.ateFood) expect(b.foodShare, 0);
        // 음수 없음, 당첨자 외에는 100원 단위
        expect(b.total, greaterThanOrEqualTo(0));
        if (p.id != result.remainderPayerId) expect(b.total % 100, 0);
      }
      // 룰렛 추가 부담은 (인원수 × 100원) 미만
      expect(result.remainder, lessThan(100 * n));
    }
    expect(settled, greaterThan(100));
  });
}

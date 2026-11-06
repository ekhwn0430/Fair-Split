import '../models/settlement_models.dart';

/// 참여자별 최종 부담액을 계산하는 인터페이스.
///
/// 실제 참여 시간·음주량 가중치 계산 로직은 팀원이 이 인터페이스를
/// 구현해 [DemoSettlementCalculator] 대신 주입하면 된다.
abstract class SettlementCalculator {
  SettlementResult calculate({
    required List<SettlementItem> items,
    required List<Participant> participants,
    int? receiptTotalAmount,
  });
}

/// 중간발표 데모용 임시 계산 로직.
///
/// 실제 정산 수식이 아니다. 참여 시간이나 음주량 가중치를 전혀 쓰지 않고,
/// 분류별(음식/일반주류/고가주류) 합계를 해당 분류에 해당하는 참여자 수로
/// 단순 n분의 1 한다. 개인 주문은 배정된 수량에 비례해 참여자들이 나눠
/// 부담한다. 팀원이 실제 계산 로직을 완성하면 [SettlementCalculator]를
/// 구현하는 다른 클래스로 교체한다.
class DemoSettlementCalculator implements SettlementCalculator {
  @override
  SettlementResult calculate({
    required List<SettlementItem> items,
    required List<Participant> participants,
    int? receiptTotalAmount,
  }) {
    if (participants.isEmpty) {
      return SettlementResult(
        breakdowns: const [],
        foodTotal: 0,
        regularAlcoholTotal: 0,
        premiumAlcoholTotal: 0,
        personalOrderTotal: 0,
        receiptTotalAmount: receiptTotalAmount,
      );
    }

    final foodTotal = _sumOf(items, ItemCategory.food);
    final regularAlcoholTotal = _sumOf(items, ItemCategory.regularAlcohol);
    final premiumAlcoholTotal = _sumOf(items, ItemCategory.premiumAlcohol);

    // 음식을 먹지 않았어도 음료수를 마셨으면 음식비 분담 대상으로 본다.
    // (음료는 Gemini 분류상 '음식'에 포함되기 때문.)
    final foodEaters =
        participants.where((p) => p.ateFood || p.drankBeverage).toList();
    final alcoholDrinkers = participants.where((p) => p.drankAlcohol).toList();

    // 음주자가 0명이어도(C4) 비용이 사라지지 않도록, 해당 분류를 부담할
    // 사람이 아무도 없으면 전체 참여자에게 n분의 1로 돌린다. 데모 한정
    // 안전장치이며 실제 계산 로직에서는 다르게 처리될 수 있다.
    final foodShares = _splitEvenly(
      foodTotal,
      foodEaters.isEmpty ? participants : foodEaters,
      participants,
    );
    final regularAlcoholShares = _splitEvenly(
      regularAlcoholTotal,
      alcoholDrinkers.isEmpty ? participants : alcoholDrinkers,
      participants,
    );
    final premiumAlcoholShares = _splitEvenly(
      premiumAlcoholTotal,
      alcoholDrinkers.isEmpty ? participants : alcoholDrinkers,
      participants,
    );

    final personalOrderShares = <String, int>{
      for (final participant in participants) participant.id: 0,
    };
    var personalOrderTotal = 0;

    // 참여자 입력 화면에서 개인 주문 전체 수량 배정을 강제하므로, 이
    // 시점에는 모든 수량이 참여자에게 배정돼 있어야 한다. 혹시 일부
    // 수량이 배정되지 않은 채로 넘어와도 다른 참여자에게 자동으로
    // 나누지 않는다(배정되지 않은 금액은 누구의 몫에도 더해지지 않아
    // [SettlementResult.isBalanced]가 false가 되어 드러난다).
    for (final item in items) {
      if (item.category != ItemCategory.personalOrder) continue;
      personalOrderTotal += item.price;

      // 줄 합계를 수량 단위(1개당 금액)로 나눈 뒤, 배정 순서대로 필요한
      // 개수만큼씩 이어서 묶어 참여자 몫을 계산한다. 배정 수량의 합이
      // item.quantity와 같다면(= 전부 배정됨) 참여자별 몫의 합은 항상
      // item.price와 정확히 같다.
      final unitPrices = splitAmountByQuantity(item.price, item.quantity);
      var cursor = 0;
      for (final assignment in item.assignments) {
        final share = unitPrices
            .skip(cursor)
            .take(assignment.quantity)
            .fold(0, (sum, unitPrice) => sum + unitPrice);
        cursor += assignment.quantity;

        final participantId = assignment.participantId;
        if (personalOrderShares.containsKey(participantId)) {
          personalOrderShares[participantId] =
              personalOrderShares[participantId]! + share;
        }
      }
    }

    final breakdowns = [
      for (final participant in participants)
        ParticipantBreakdown(
          participantId: participant.id,
          participantName: participant.name,
          foodShare: foodShares[participant.id] ?? 0,
          regularAlcoholShare: regularAlcoholShares[participant.id] ?? 0,
          premiumAlcoholShare: premiumAlcoholShares[participant.id] ?? 0,
          personalOrderShare: personalOrderShares[participant.id] ?? 0,
        ),
    ];

    return SettlementResult(
      breakdowns: breakdowns,
      foodTotal: foodTotal,
      regularAlcoholTotal: regularAlcoholTotal,
      premiumAlcoholTotal: premiumAlcoholTotal,
      personalOrderTotal: personalOrderTotal,
      receiptTotalAmount: receiptTotalAmount,
    );
  }

  int _sumOf(List<SettlementItem> items, ItemCategory category) {
    return items
        .where((item) => item.category == category)
        .fold(0, (sum, item) => sum + item.price);
  }

  /// [amount]를 [payers] 각자에게 n분의 1로 나눈 뒤, [allParticipants] 전원을
  /// 키로 갖는 맵으로 돌려준다(부담이 없는 사람은 0원).
  Map<String, int> _splitEvenly(
    int amount,
    List<Participant> payers,
    List<Participant> allParticipants,
  ) {
    final shares = <String, int>{
      for (final participant in allParticipants) participant.id: 0,
    };

    if (amount == 0 || payers.isEmpty) return shares;

    final amounts = _splitAmountEvenly(amount, payers.length);
    for (var i = 0; i < payers.length; i++) {
      shares[payers[i].id] = amounts[i];
    }
    return shares;
  }

  /// [amount]를 [count]명에게 1원 단위까지 정확히 나눈다. 나머지는 앞사람부터
  /// 1원씩 더 받으며, 반환값의 합은 항상 [amount]와 같다.
  List<int> _splitAmountEvenly(int amount, int count) {
    if (count <= 0) return const [];
    final base = amount ~/ count;
    final remainder = amount % count;
    return List.generate(count, (index) => base + (index < remainder ? 1 : 0));
  }
}

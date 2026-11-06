// 정산(참여자 입력 ~ 결과 화면) 흐름에서 쓰는 데이터 모델.
//
// Gemini 분석 결과(ReceiptAnalysis/ReceiptItem/ReceiptItemCategory, 분류 3종)와는
// 별개로, 정산 화면은 '개인 주문'을 포함한 4종 분류([ItemCategory])를 쓴다.
// gemini_receipt_service.dart는 읽기만 하고 수정하지 않는다.
import 'package:flutter/material.dart' show TimeOfDay;

import '../services/gemini_receipt_service.dart';

int _localIdCounter = 0;

/// 영수증 품목/참여자 id로 쓸 새 로컬 id를 발급한다.
String generateLocalId() {
  _localIdCounter += 1;
  return '${DateTime.now().microsecondsSinceEpoch}_$_localIdCounter';
}

/// 정산 화면에서 쓰는 품목 분류. Gemini가 내놓는 3종 분류와 달리
/// '개인 주문'이 추가된 정산 전용 분류다.
enum ItemCategory {
  food,
  regularAlcohol,
  premiumAlcohol,
  personalOrder;

  String get label {
    switch (this) {
      case ItemCategory.food:
        return '음식';
      case ItemCategory.regularAlcohol:
        return '일반주류';
      case ItemCategory.premiumAlcohol:
        return '고가주류';
      case ItemCategory.personalOrder:
        return '개인 주문';
    }
  }
}

/// Gemini의 3종 분류를 정산용 [ItemCategory]로 변환한다.
ItemCategory fromGeminiCategory(ReceiptItemCategory category) {
  switch (category) {
    case ReceiptItemCategory.food:
      return ItemCategory.food;
    case ReceiptItemCategory.regularAlcohol:
      return ItemCategory.regularAlcohol;
    case ReceiptItemCategory.premiumAlcohol:
      return ItemCategory.premiumAlcohol;
  }
}

/// '개인 주문' 항목의 수량 중 일부를 특정 참여자에게 배정한 내역.
///
/// 같은 메뉴를 여러 참여자가 수량을 나눠 주문했을 때(예: 파인애플맥주 3잔
/// 중 2잔은 참여자 A, 1잔은 참여자 B) 품목 하나에 여러 배정이 함께 있을 수
/// 있다.
class PersonalOrderAssignment {
  const PersonalOrderAssignment({
    required this.participantId,
    required this.quantity,
  });

  final String participantId;
  final int quantity;
}

/// 정산 화면에서 다루는 영수증 품목 한 줄.
class SettlementItem {
  SettlementItem({
    required this.id,
    required this.name,
    required this.price,
    required this.quantity,
    required this.category,
    List<PersonalOrderAssignment>? assignments,
  }) : assignments = assignments ?? const [];

  final String id;
  final String name;

  /// 단가가 아니라 해당 품목 줄의 합계 금액.
  final int price;
  final int quantity;
  final ItemCategory category;

  /// [ItemCategory.personalOrder]일 때, 수량을 나눠 부담할 참여자별 배정
  /// 내역. 그 외 분류에서는 항상 빈 목록이다.
  final List<PersonalOrderAssignment> assignments;

  /// 지금까지 배정된 수량의 합.
  int get assignedQuantity =>
      assignments.fold(0, (sum, assignment) => sum + assignment.quantity);

  /// 품목의 전체 수량이 참여자들에게 정확히 다 배정됐는지.
  /// 개인 주문이 아니면 항상 true다(배정이 필요 없으므로).
  bool get isFullyAssigned =>
      category != ItemCategory.personalOrder || assignedQuantity == quantity;

  SettlementItem copyWith({
    String? name,
    int? price,
    int? quantity,
    ItemCategory? category,
    List<PersonalOrderAssignment>? assignments,
  }) {
    return SettlementItem(
      id: id,
      name: name ?? this.name,
      price: price ?? this.price,
      quantity: quantity ?? this.quantity,
      category: category ?? this.category,
      assignments: assignments ?? this.assignments,
    );
  }
}

/// [amount]를 [count]개로 1원 단위까지 정확히 나눈다. 나머지는 앞에서부터
/// 1원씩 더 받으며, 반환값의 합은 항상 [amount]와 같다.
///
/// '개인 주문' 품목의 줄 합계를 수량 단위로 나눠, 참여자별 배정 수량에
/// 비례한 금액을 계산하는 데 쓴다(음식/일반 주류/고가 주류를 참여자 수로
/// 나누는 기존 로직과는 별개다).
List<int> splitAmountByQuantity(int amount, int count) {
  if (count <= 0) return const [];
  final base = amount ~/ count;
  final remainder = amount % count;
  return List.generate(count, (index) => base + (index < remainder ? 1 : 0));
}

/// Gemini 분석(혹은 수정) 결과를 정산 화면으로 넘기기 위한 중간 결과물.
///
/// 영수증 수정 화면과 직접 입력 화면이 공통으로 돌려주는 타입이다.
class ReceiptWorkingSet {
  const ReceiptWorkingSet({required this.items, this.totalAmount, this.paidAt});

  final List<SettlementItem> items;
  final int? totalAmount;
  final DateTime? paidAt;
}

/// [ReceiptWorkingSet]을 로컬 보관함(ReceiptStorageService) 저장용
/// [ReceiptAnalysis]로 변환한다.
///
/// 로컬 보관함은 Gemini 분류 3종만 지원하므로, category에는 '개인 주문'을
/// '음식'으로 저장한다. 다만 [ReceiptItem.isPersonalOrder]에 실제 분류를
/// 별도로 남겨 두어, 저장된 영수증으로 다시 정산할 때
/// ([fromArchivedReceiptAnalysis]) '개인 주문' 분류를 복원할 수 있게 한다.
ReceiptAnalysis toArchivedReceiptAnalysis(ReceiptWorkingSet workingSet) {
  return ReceiptAnalysis(
    items: [
      for (final item in workingSet.items)
        ReceiptItem(
          name: item.name,
          price: item.price,
          quantity: item.quantity,
          category: _toGeminiCategory(item.category),
          isPersonalOrder: item.category == ItemCategory.personalOrder,
        ),
    ],
    paidAt: workingSet.paidAt,
    totalAmount: workingSet.totalAmount,
  );
}

/// 저장된 영수증([ReceiptAnalysis])을 Gemini를 다시 호출하지 않고
/// [ReceiptWorkingSet]으로 되돌린다. 저장된 사진은 그대로 두고, 메뉴명·가격
/// (항목 합계)·수량·분류('개인 주문' 포함)를 그대로 가져와 참여자 입력
/// 화면으로 바로 이동할 수 있게 한다.
///
/// 참여자 배정([SettlementItem.assignments])은 매 정산마다 새로 입력하는
/// 참여자에 종속되므로 복원하지 않는다.
ReceiptWorkingSet fromArchivedReceiptAnalysis(ReceiptAnalysis analysis) {
  return ReceiptWorkingSet(
    items: [
      for (final item in analysis.items)
        SettlementItem(
          id: generateLocalId(),
          name: item.name,
          price: item.price,
          quantity: item.quantity,
          category: item.isPersonalOrder
              ? ItemCategory.personalOrder
              : fromGeminiCategory(item.category),
        ),
    ],
    totalAmount: analysis.totalAmount,
    paidAt: analysis.paidAt,
  );
}

ReceiptItemCategory _toGeminiCategory(ItemCategory category) {
  switch (category) {
    case ItemCategory.food:
    case ItemCategory.personalOrder:
      return ReceiptItemCategory.food;
    case ItemCategory.regularAlcohol:
      return ReceiptItemCategory.regularAlcohol;
    case ItemCategory.premiumAlcohol:
      return ReceiptItemCategory.premiumAlcohol;
  }
}

/// 정산에 참여하는 사람 한 명.
///
/// 1차 모임 하나만 다루는 MVP 버전이라 모임 구분 없이 참여자 한 명당
/// 참여 시간/음식·음주·음료 여부를 한 번씩만 가진다.
class Participant {
  const Participant({
    required this.id,
    required this.name,
    this.joinTime,
    this.ateFood = true,
    this.drankAlcohol = false,
    this.drankBeverage = false,
  });

  final String id;
  final String name;
  final TimeOfDay? joinTime;
  final bool ateFood;
  final bool drankAlcohol;
  final bool drankBeverage;
}

/// 참여자 한 명의 정산 결과 상세.
class ParticipantBreakdown {
  const ParticipantBreakdown({
    required this.participantId,
    required this.participantName,
    required this.foodShare,
    required this.regularAlcoholShare,
    required this.premiumAlcoholShare,
    required this.personalOrderShare,
  });

  final String participantId;
  final String participantName;
  final int foodShare;
  final int regularAlcoholShare;
  final int premiumAlcoholShare;
  final int personalOrderShare;

  int get total =>
      foodShare + regularAlcoholShare + premiumAlcoholShare + personalOrderShare;
}

/// 정산 계산 전체 결과.
class SettlementResult {
  const SettlementResult({
    required this.breakdowns,
    required this.foodTotal,
    required this.regularAlcoholTotal,
    required this.premiumAlcoholTotal,
    required this.personalOrderTotal,
    required this.receiptTotalAmount,
  });

  final List<ParticipantBreakdown> breakdowns;
  final int foodTotal;
  final int regularAlcoholTotal;
  final int premiumAlcoholTotal;
  final int personalOrderTotal;

  /// 영수증(혹은 직접 입력)에 적힌 총액. 없으면 비교 없이 항목 합계만 쓴다.
  final int? receiptTotalAmount;

  int get itemsGrandTotal =>
      foodTotal + regularAlcoholTotal + premiumAlcoholTotal + personalOrderTotal;

  int get participantsGrandTotal =>
      breakdowns.fold(0, (sum, breakdown) => sum + breakdown.total);

  /// 참여자별 부담액 합계가 항목 합계와 일치하는지.
  bool get isBalanced => participantsGrandTotal == itemsGrandTotal;
}

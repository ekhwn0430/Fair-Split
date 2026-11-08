// Gemini를 호출하지 않고 보관함 저장/복원 변환(toArchivedReceiptAnalysis /
// fromArchivedReceiptAnalysis)만 단독으로 검증하는 테스트.
import 'package:fair_split/models/settlement_models.dart';
import 'package:fair_split/services/gemini_receipt_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('toArchivedReceiptAnalysis / fromArchivedReceiptAnalysis', () {
    test('개인 주문 분류를 보관함에 저장했다가 다시 정산할 때 그대로 복원된다', () {
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
            quantity: 2,
            category: ItemCategory.personalOrder,
            assignments: const [
              PersonalOrderAssignment(participantId: 'p1', quantity: 2),
            ],
          ),
        ],
        totalAmount: 34000,
        paidAt: DateTime(2026, 11, 5, 20, 30),
      );

      final archived = toArchivedReceiptAnalysis(workingSet);

      // 로컬 보관함은 Gemini 3종 분류만 지원하므로 '개인 주문'은 '음식'으로
      // 저장되지만, isPersonalOrder에 실제 분류가 별도로 남는다.
      expect(archived.items[0].isPersonalOrder, isFalse);
      expect(archived.items[1].category, ReceiptItemCategory.food);
      expect(archived.items[1].isPersonalOrder, isTrue);
      // 가격(항목 합계)과 수량은 그대로 보존된다(중복으로 곱하지 않음).
      expect(archived.items[1].price, 8000);
      expect(archived.items[1].quantity, 2);

      final restored = fromArchivedReceiptAnalysis(archived);

      expect(restored.items[0].category, ItemCategory.food);
      expect(restored.items[1].category, ItemCategory.personalOrder);
      expect(restored.items[1].price, 8000);
      expect(restored.items[1].quantity, 2);
      expect(restored.totalAmount, 34000);
      expect(restored.paidAt, DateTime(2026, 11, 5, 20, 30));

      // 참여자 배정은 매 정산마다 새로 입력하는 참여자에 종속되므로
      // 저장된 영수증을 다시 정산할 때는 복원하지 않는다.
      expect(restored.items[1].assignments, isEmpty);
    });

    test('isPersonalOrder 필드가 없는 기존 저장 데이터도 호환된다', () {
      final legacyAnalysis = ReceiptAnalysis.fromJson({
        'items': [
          {
            'name': '소주',
            'price': 4000,
            'quantity': 1,
            'category': 'regular_alcohol',
          },
        ],
        'paidAt': null,
        'totalAmount': 4000,
      });

      expect(legacyAnalysis.items.single.isPersonalOrder, isFalse);

      final restored = fromArchivedReceiptAnalysis(legacyAnalysis);

      expect(restored.items.single.category, ItemCategory.regularAlcohol);
      expect(restored.items.single.price, 4000);
    });
  });
}

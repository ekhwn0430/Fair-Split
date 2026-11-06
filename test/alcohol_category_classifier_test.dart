// 메뉴명만으로 일반/고가 주류를 구분하는 로컬 분류 규칙 단독 테스트.
// Gemini를 호출하지 않는다.
import 'package:fair_split/services/alcohol_category_classifier.dart';
import 'package:fair_split/services/gemini_receipt_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('classifyAlcoholByName', () {
    test('소주·병맥주·막걸리·청하는 일반 주류로 분류한다', () {
      expect(classifyAlcoholByName('소주'), ReceiptItemCategory.regularAlcohol);
      expect(classifyAlcoholByName('병맥주'), ReceiptItemCategory.regularAlcohol);
      expect(classifyAlcoholByName('막걸리'), ReceiptItemCategory.regularAlcohol);
      expect(classifyAlcoholByName('청하'), ReceiptItemCategory.regularAlcohol);
      expect(classifyAlcoholByName('참이슬 소주'), ReceiptItemCategory.regularAlcohol);
    });

    test('생맥주·하이볼·양주 등은 고가 주류로 분류한다', () {
      expect(classifyAlcoholByName('생맥주'), ReceiptItemCategory.premiumAlcohol);
      expect(classifyAlcoholByName('하이볼'), ReceiptItemCategory.premiumAlcohol);
      expect(classifyAlcoholByName('양주'), ReceiptItemCategory.premiumAlcohol);
      expect(classifyAlcoholByName('위스키'), ReceiptItemCategory.premiumAlcohol);
      expect(classifyAlcoholByName('와인'), ReceiptItemCategory.premiumAlcohol);
      expect(classifyAlcoholByName('생맥주 500cc'), ReceiptItemCategory.premiumAlcohol);
    });

    test("'생맥주'처럼 일반 주류 키워드('맥주')를 포함해도 고가 주류로 우선 분류한다", () {
      // '생맥주'는 '맥주'라는 글자를 포함하지만 '병맥주'와는 다른 메뉴이므로
      // 고가 주류로 먼저 매칭돼야 한다.
      expect(classifyAlcoholByName('생맥주'), ReceiptItemCategory.premiumAlcohol);
      expect(classifyAlcoholByName('병맥주'), ReceiptItemCategory.regularAlcohol);
    });

    test('이름만으로 확실히 판단할 수 없는 메뉴는 null을 돌려준다', () {
      expect(classifyAlcoholByName('삼겹살'), isNull);
      expect(classifyAlcoholByName('맥주'), isNull);
      expect(classifyAlcoholByName(''), isNull);
      expect(classifyAlcoholByName('   '), isNull);
    });
  });
}

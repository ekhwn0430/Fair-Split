import 'gemini_receipt_service.dart';

/// 메뉴명만으로 '일반 주류'와 '고가 주류'를 구분하는 로컬 보정 규칙.
///
/// Gemini 응답의 주류 분류(소주·병맥주 등은 일반 주류, 생맥주·하이볼·양주
/// 등은 고가 주류)가 메뉴명과 어긋나는 경우를 메뉴명 키워드로 보정하기
/// 위한 함수다. Gemini API 모델 설정이나 응답 JSON 구조는 건드리지 않고,
/// 분석 결과를 화면에 표시하기 전에 로컬에서만 적용한다.
///
/// 이름만으로 확실히 판단할 수 있는 메뉴만 분류하고, 알 수 없는 메뉴는
/// null을 돌려준다. 호출하는 쪽은 이 경우 Gemini가 준 분류를 그대로 쓰고,
/// 사용자가 수정 화면에서 직접 바꿀 수 있게 둬야 한다.
ReceiptItemCategory? classifyAlcoholByName(String name) {
  final normalized = name.trim();
  if (normalized.isEmpty) return null;

  // 고가 주류 키워드를 먼저 확인한다. '생맥주'처럼 일반 주류 키워드인
  // '맥주'를 포함하는 복합어가 있을 수 있어, 더 구체적인 고가 주류
  // 키워드를 먼저 매칭해야 '일반 주류'로 잘못 보정되지 않는다.
  for (final keyword in _premiumAlcoholKeywords) {
    if (normalized.contains(keyword)) return ReceiptItemCategory.premiumAlcohol;
  }

  for (final keyword in _regularAlcoholKeywords) {
    if (normalized.contains(keyword)) return ReceiptItemCategory.regularAlcohol;
  }

  return null;
}

/// Gemini 응답의 system instruction(gemini_receipt_service.dart)에 적힌
/// 고가 주류 예시와 맞춘 키워드 목록.
const _premiumAlcoholKeywords = [
  '생맥주',
  '하이볼',
  '와인',
  '샴페인',
  '위스키',
  '양주',
  '코냑',
  '사케',
  '고량주',
];

/// Gemini 응답의 system instruction에 적힌 일반 주류 예시와 맞춘 키워드
/// 목록. '맥주'처럼 '생맥주'와도 겹치는 단어는 넣지 않는다.
const _regularAlcoholKeywords = ['소주', '병맥주', '막걸리', '청하'];

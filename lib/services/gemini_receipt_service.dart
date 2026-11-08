
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

/// 영수증 항목의 분류.
enum ReceiptItemCategory {
  food('food', '음식'),
  regularAlcohol('regular_alcohol', '일반주류'),
  premiumAlcohol('premium_alcohol', '고가주류');

  const ReceiptItemCategory(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static ReceiptItemCategory fromApiValue(String value) {
    for (final category in values) {
      if (category.apiValue == value) {
        return category;
      }
    }

    throw const FormatException('알 수 없는 메뉴 분류입니다.');
  }
}

/// 영수증 메뉴 한 줄.
class ReceiptItem {
  const ReceiptItem({
    required this.name,
    required this.price,
    required this.quantity,
    required this.category,
    this.isPersonalOrder = false,
  });

  factory ReceiptItem.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final price = json['price'];
    final quantity = json['quantity'];
    final category = json['category'];
    final isPersonalOrder = json['isPersonalOrder'];

    if (name is! String ||
        name.trim().isEmpty ||
        price is! num ||
        quantity is! num ||
        category is! String) {
      throw const FormatException(
        '영수증 메뉴 데이터 형식이 올바르지 않습니다.',
      );
    }

    if (!price.isFinite ||
        !quantity.isFinite ||
        price < 0 ||
        quantity <= 0 ||
        price != price.truncateToDouble() ||
        quantity != quantity.truncateToDouble()) {
      throw const FormatException(
        '영수증 메뉴의 가격 또는 수량이 올바르지 않습니다.',
      );
    }

    return ReceiptItem(
      name: name.trim(),
      price: price.toInt(),
      quantity: quantity.toInt(),
      category: ReceiptItemCategory.fromApiValue(category),
      // 기존에 저장된 영수증(이 필드가 없던 버전)은 모두 개인 주문이 아니었던
      // 것으로 간주한다.
      isPersonalOrder: isPersonalOrder == true,
    );
  }

  final String name;

  /// 단가가 아니라 해당 메뉴 줄의 합계 금액.
  final int price;

  final int quantity;
  final ReceiptItemCategory category;

  /// 정산 화면에서 '개인 주문'으로 지정됐던 항목인지.
  ///
  /// Gemini는 이 분류를 모르므로(3종 분류만 추출) 항상 false로 응답하며,
  /// 로컬 보관함에 저장할 때 정산 화면의 분류를 보존하기 위해서만 쓰인다.
  final bool isPersonalOrder;

  Map<String, dynamic> toJson() => {
        'name': name,
        'price': price,
        'quantity': quantity,
        'category': category.apiValue,
        'isPersonalOrder': isPersonalOrder,
      };
}

/// 영수증 전체 분석 결과.
class ReceiptAnalysis {
  const ReceiptAnalysis({
    required this.items,
    this.paidAt,
    this.totalAmount,
  });

  factory ReceiptAnalysis.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];

    if (rawItems is! List || rawItems.isEmpty) {
      throw const FormatException(
        '영수증에서 메뉴를 찾지 못했습니다.',
      );
    }

    final items = <ReceiptItem>[];

    for (final item in rawItems) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException(
          '영수증 메뉴 데이터가 잘못되었습니다.',
        );
      }

      items.add(ReceiptItem.fromJson(item));
    }

    DateTime? paidAt;

    final rawPaidAt = json['paidAt'];
    if (rawPaidAt is String && rawPaidAt.isNotEmpty) {
      paidAt = DateTime.tryParse(rawPaidAt);
    }

    int? totalAmount;

    final rawTotalAmount = json['totalAmount'];
    if (rawTotalAmount != null) {
      if (rawTotalAmount is! num ||
          !rawTotalAmount.isFinite ||
          rawTotalAmount < 0 ||
          rawTotalAmount != rawTotalAmount.truncateToDouble()) {
        throw const FormatException(
          '최종 결제 금액이 잘못되었습니다.',
        );
      }

      totalAmount = rawTotalAmount.toInt();
    }

    return ReceiptAnalysis(
      items: items,
      paidAt: paidAt,
      totalAmount: totalAmount,
    );
  }

  final List<ReceiptItem> items;
  final DateTime? paidAt;
  final int? totalAmount;

  Map<String, dynamic> toJson() => {
        'items': items.map((item) => item.toJson()).toList(),
        'paidAt': paidAt?.toIso8601String(),
        'totalAmount': totalAmount,
      };
}

/// 사용자에게 표시할 안전한 오류.
class ReceiptAnalysisException implements Exception {
  const ReceiptAnalysisException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Gemini를 이용한 영수증 분석 서비스.
///
/// 현재는 무료 등급 확인을 위해 모델 하나만 호출한다.
/// 실패하더라도 다른 모델을 자동 호출하지 않는다.
class GeminiReceiptService {
  GeminiReceiptService({
    required String apiKey,
    String modelName = defaultModelName,
    String fallbackModelName = defaultModelName,
  }) : _model = _buildModel(apiKey, modelName);

  /// 기존 테스트 코드와의 호환성을 유지한다.
  GeminiReceiptService.withModel(this._model);

  static const defaultModelName = 'gemini-3.1-flash-lite';

  /// 기존 코드에서 참조할 가능성이 있어 이름을 유지한다.
  /// 실제 자동 폴백에는 사용하지 않는다.
  static const fallbackModelName = defaultModelName;

  final GenerativeModel _model;

  static const _instructions = '''
당신은 한국 음식점 영수증 분석 도구입니다.

이미지에 실제로 보이는 내용만 추출하세요.
읽을 수 없는 정보는 추측하지 마세요.

추출 규칙:
- items에는 주문 메뉴만 포함합니다.
- 소계, 합계, 부가세, 할인, 결제수단은 제외합니다.
- name은 영수증에 적힌 메뉴명입니다.
- price는 해당 메뉴 줄의 합계 금액입니다.
- quantity는 수량이며 표시가 없으면 1입니다.
- paidAt은 YYYY-MM-DDTHH:mm:ss 형식입니다.
- 결제 시각을 읽을 수 없으면 null입니다.
- totalAmount는 영수증의 최종 결제 금액입니다.
- 할인된 금액이 있으면 최종 결제 금액을 사용합니다.
- 최종 결제 금액을 읽을 수 없으면 null입니다.
- 보이지 않는 금액을 임의로 계산하지 마세요.

분류 기준:
food:
음식, 안주, 탄산음료, 커피, 주스 등 무알코올 메뉴

regular_alcohol:
소주, 병맥주, 막걸리, 청하 등 일반 주류

premium_alcohol:
생맥주, 하이볼, 와인, 샴페인, 위스키,
양주, 코냑, 사케, 고량주 등 고가 주류

반드시 지정된 JSON 형식으로 응답하세요.
''';

  static const _prompt =
      '이 영수증에서 메뉴, 수량, 금액, 결제 시각, '
      '최종 결제 금액을 추출하고 메뉴를 분류해 주세요.';

  static final _responseSchema = Schema.object(
    properties: {
      'items': Schema.array(
        items: Schema.object(
          properties: {
            'name': Schema.string(
              description: '영수증에 적힌 메뉴명',
            ),
            'price': Schema.integer(
              description: '해당 메뉴 줄의 합계 금액',
            ),
            'quantity': Schema.integer(
              description: '메뉴 수량',
            ),
            'category': Schema.enumString(
              enumValues: [
                'food',
                'regular_alcohol',
                'premium_alcohol',
              ],
            ),
          },
          requiredProperties: [
            'name',
            'price',
            'quantity',
            'category',
          ],
        ),
      ),
      'paidAt': Schema.string(
        description: '결제 시각',
        nullable: true,
      ),
      'totalAmount': Schema.integer(
        description: '최종 결제 금액',
        nullable: true,
      ),
    },
    requiredProperties: [
      'items',
      'paidAt',
      'totalAmount',
    ],
  );

  static GenerativeModel _buildModel(
    String apiKey,
    String modelName,
  ) {
    return GenerativeModel(
      model: modelName,
      apiKey: apiKey,
      systemInstruction: Content.system(_instructions),
      generationConfig: GenerationConfig(
        temperature: 0,
        responseMimeType: 'application/json',
        responseSchema: _responseSchema,
      ),
    );
  }

  /// 영수증 이미지를 Gemini로 분석한다.
  ///
  /// API 요청은 최대 한 번만 수행한다.
  /// 오류가 발생하면 재시도하거나 유료 모델로 전환하지 않는다.
  Future<ReceiptAnalysis> analyzeReceipt(
    Uint8List imageBytes, {
    String mimeType = 'image/jpeg',
  }) async {
    if (imageBytes.isEmpty) {
      throw const ReceiptAnalysisException(
        '이미지 파일이 비어 있습니다.',
      );
    }

    if (mimeType != 'image/jpeg' &&
        mimeType != 'image/png' &&
        mimeType != 'image/webp') {
      throw const ReceiptAnalysisException(
        '지원하지 않는 이미지 형식입니다.',
      );
    }

    debugPrint('[Gemini] 무료 등급 모델 1회 분석 시작');

    try {
      final response = await _model.generateContent([
        Content.multi([
          TextPart(_prompt),
          DataPart(mimeType, imageBytes),
        ]),
      ]);

      final text = response.text;

      if (text == null || text.trim().isEmpty) {
        throw const FormatException(
          'Gemini 응답이 비어 있습니다.',
        );
      }

      final cleaned = _stripMarkdownCodeBlock(text);
      final decoded = jsonDecode(cleaned);

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException(
          'Gemini 응답이 JSON 객체가 아닙니다.',
        );
      }

      final analysis = ReceiptAnalysis.fromJson(decoded);

      debugPrint('[Gemini] 영수증 분석 성공');

      return analysis;
    } catch (error) {
      final safeMessage = _safeErrorMessage(error);

      // API 키나 요청 URL이 포함될 수 있는 원본 오류는 출력하지 않는다.
      debugPrint('[Gemini] 분석 실패: $safeMessage');

      throw ReceiptAnalysisException(safeMessage);
    }
  }

  /// 오류 원문을 외부에 노출하지 않고 종류만 분류한다.
  static String _safeErrorMessage(Object error) {
    if (error is FormatException) {
      return '영수증 데이터 해석에 실패했습니다.';
    }

    final message = error.toString().toLowerCase();

    if (message.contains('429') ||
        message.contains('resource_exhausted') ||
        message.contains('quota')) {
      return '무료 API 사용 한도에 도달했습니다. '
          '추가 호출 없이 직접 입력을 이용해 주세요.';
    }

    if (message.contains('404') ||
        message.contains('not found') ||
        message.contains('no longer available')) {
      return '현재 API에서 해당 모델을 사용할 수 없습니다.';
    }

    if (message.contains('403') ||
        message.contains('permission_denied')) {
      return 'API 접근 권한이 없습니다.';
    }

    if (message.contains('401') ||
        message.contains('api key not valid')) {
      return 'API 키 인증에 실패했습니다.';
    }

    if (message.contains('400') ||
        message.contains('invalid_argument')) {
      return 'Gemini 요청 형식이 올바르지 않습니다.';
    }

    if (message.contains('503') ||
        message.contains('unavailable')) {
      return 'Gemini 서버 또는 모델에 연결할 수 없습니다.';
    }

    if (message.contains('timeout') ||
        message.contains('socketexception') ||
        message.contains('clientexception')) {
      return '네트워크 연결에 실패했습니다.';
    }

    return '영수증 분석 중 오류가 발생했습니다.';
  }

  /// Gemini가 코드 블록으로 응답한 경우 JSON 부분만 추출한다.
  static String _stripMarkdownCodeBlock(String text) {
    final trimmed = text.trim();

    final pattern = RegExp(
      r'^```[a-zA-Z]*\s*([\s\S]*?)\s*```$',
    );

    final match = pattern.firstMatch(trimmed);

    return match != null
        ? match.group(1)!.trim()
        : trimmed;
  }
}

import 'package:flutter/material.dart';

import '../models/settlement_models.dart';
import '../services/fair_settlement_calculator.dart';
import '../services/settlement_calculator.dart';

/// 참여자별 정산 결과를 보여주는 화면.
///
/// 실제 계산은 [SettlementCalculator] 인터페이스를 통해 이루어지며, 기본값은
/// 참석 시간·음주 여부·개인 주문을 반영하는 [FairSettlementCalculator]다.
class SettlementResultScreen extends StatelessWidget {
  SettlementResultScreen({
    super.key,
    required this.items,
    required this.participants,
    this.receiptTotalAmount,
    SettlementCalculator? calculator,
  }) : calculator = calculator ?? FairSettlementCalculator();

  final List<SettlementItem> items;
  final List<Participant> participants;
  final int? receiptTotalAmount;
  final SettlementCalculator calculator;

  @override
  Widget build(BuildContext context) {
    final SettlementResult result;
    try {
      result = calculator.calculate(
        items: items,
        participants: participants,
        receiptTotalAmount: receiptTotalAmount,
      );
    } on SettlementInputException catch (error) {
      return Scaffold(
        appBar: AppBar(title: const Text('정산 결과')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: _WarningBanner(message: error.message),
        ),
      );
    }

    final theme = Theme.of(context);
    final hasReceiptMismatch = result.discountTotal != 0;
    String nameOf(String? id) => result.breakdowns
        .firstWhere(
          (b) => b.participantId == id,
          orElse: () => result.breakdowns.first,
        )
        .participantName;

    return Scaffold(
      appBar: AppBar(title: const Text('정산 결과')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _InfoBanner(
              message: result.isTimeWeighted
                  ? '음식·소주·맥주는 먹은 사람끼리 참석 시간에 비례해, '
                      '고가 주류·개인 주문은 주문한 사람이 부담합니다.'
                  : '결제 시각 또는 시작 시각이 없어 참석 시간 가중치 없이 '
                      '먹은 사람끼리 똑같이 나눴습니다.',
            ),
            const SizedBox(height: 16),
            Text('분류별 합계', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            _AmountRow(label: '음식비', amount: result.foodTotal),
            _AmountRow(label: '일반 주류비', amount: result.regularAlcoholTotal),
            _AmountRow(label: '고가 주류비', amount: result.premiumAlcoholTotal),
            _AmountRow(label: '개인 주문비', amount: result.personalOrderTotal),
            const Divider(),
            _AmountRow(label: '항목 합계', amount: result.itemsGrandTotal),
            if (hasReceiptMismatch)
              _AmountRow(
                label: result.discountTotal < 0 ? '할인' : '추가 금액',
                amount: result.discountTotal,
              ),
            _AmountRow(
              label: '결제 금액',
              amount: result.payableTotal,
              emphasize: true,
            ),
            if (hasReceiptMismatch) ...[
              const SizedBox(height: 8),
              _InfoBanner(
                message: '영수증 총액과 항목 합계의 차이 '
                    '${_formatWon(result.discountTotal)}원을 각자 부담 비율대로 '
                    '나눠 반영했습니다. 할인이 아니라 인식 오류라면 영수증 확인 '
                    '화면에서 항목을 고쳐 주세요.',
              ),
            ],
            if (result.remainder > 0) ...[
              const SizedBox(height: 8),
              _InfoBanner(
                message: '🎰 각자 ${_formatWon(result.roundingUnit)}원 단위로 '
                    '내리고 남은 ${_formatWon(result.remainder)}원은 룰렛 당첨자 '
                    '${nameOf(result.remainderPayerId)}님이 냅니다.',
              ),
            ],
            const SizedBox(height: 24),
            Text('참여자별 부담액', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (result.breakdowns.isEmpty)
              const Text('참여자가 없습니다.')
            else
              for (final breakdown in result.breakdowns)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                breakdown.attendedMinutes == null
                                    ? breakdown.participantName
                                    : '${breakdown.participantName} · '
                                        '${_formatMinutes(breakdown.attendedMinutes!)}',
                                style: theme.textTheme.titleSmall,
                              ),
                              Text(
                                '${_formatWon(breakdown.total)}원',
                                style: theme.textTheme.titleSmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          _BreakdownLine(label: '음식', amount: breakdown.foodShare),
                          _BreakdownLine(
                            label: '일반주류',
                            amount: breakdown.regularAlcoholShare,
                          ),
                          _BreakdownLine(
                            label: '고가주류',
                            amount: breakdown.premiumAlcoholShare,
                          ),
                          _BreakdownLine(
                            label: '개인 주문',
                            amount: breakdown.personalOrderShare,
                          ),
                          _BreakdownLine(
                            label: '할인·추가 금액',
                            amount: breakdown.discountShare,
                          ),
                          _BreakdownLine(
                            label: breakdown.participantId ==
                                    result.remainderPayerId
                                ? '단위 정리 + 룰렛 당첨'
                                : '단위 정리',
                            amount: breakdown.roundingAdjustment,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            const SizedBox(height: 8),
            _AmountRow(
              label: '참여자 부담액 합계',
              amount: result.participantsGrandTotal,
              emphasize: true,
            ),
            const SizedBox(height: 4),
            Text(
              result.isBalanced
                  ? '전체 결제 금액과 참여자 부담액 합계가 일치합니다.'
                  : '참여자 부담액 합계가 결제 금액과 다릅니다. 계산 로직을 확인해 주세요.',
              style: TextStyle(
                color: result.isBalanced
                    ? theme.colorScheme.primary
                    : theme.colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: colors.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colors.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber, color: colors.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(color: colors.onErrorContainer)),
          ),
        ],
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.amount,
    this.emphasize = false,
  });

  final String label;
  final int amount;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final style = emphasize
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyMedium;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text('${_formatWon(amount)}원', style: style),
        ],
      ),
    );
  }
}

class _BreakdownLine extends StatelessWidget {
  const _BreakdownLine({required this.label, required this.amount});

  final String label;
  final int amount;

  @override
  Widget build(BuildContext context) {
    if (amount == 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            '${_formatWon(amount)}원',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatMinutes(int minutes) =>
    minutes >= 60 ? '${minutes ~/ 60}시간 ${minutes % 60}분' : '$minutes분';

String _formatWon(int amount) =>
    amount.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');

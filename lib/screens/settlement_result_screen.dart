import 'package:flutter/material.dart';

import '../models/settlement_models.dart';
import '../services/settlement_calculator.dart';

/// 참여자별 정산 결과를 보여주는 화면.
///
/// 실제 계산은 [SettlementCalculator] 인터페이스를 통해 이루어진다. 지금은
/// [DemoSettlementCalculator]가 중간발표용 임시 계산을 담당하며, 실제
/// 참여 시간·음주량 가중치 계산은 팀원이 이 인터페이스를 구현해 교체할 예정이다.
class SettlementResultScreen extends StatelessWidget {
  SettlementResultScreen({
    super.key,
    required this.items,
    required this.participants,
    this.receiptTotalAmount,
    SettlementCalculator? calculator,
  }) : calculator = calculator ?? DemoSettlementCalculator();

  final List<SettlementItem> items;
  final List<Participant> participants;
  final int? receiptTotalAmount;
  final SettlementCalculator calculator;

  @override
  Widget build(BuildContext context) {
    final result = calculator.calculate(
      items: items,
      participants: participants,
      receiptTotalAmount: receiptTotalAmount,
    );

    final theme = Theme.of(context);
    final hasReceiptMismatch = result.receiptTotalAmount != null &&
        result.receiptTotalAmount != result.itemsGrandTotal;

    return Scaffold(
      appBar: AppBar(title: const Text('정산 결과')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _InfoBanner(
              message: '데모 계산 결과입니다. 시간·음주량 가중치 없이 분류별 합계를 '
                  '해당 인원수로 단순 n분의 1 한 값이며, 실제 정산 수식이 아닙니다.',
            ),
            const SizedBox(height: 16),
            Text('분류별 합계', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            _AmountRow(label: '음식비', amount: result.foodTotal),
            _AmountRow(label: '일반 주류비', amount: result.regularAlcoholTotal),
            _AmountRow(label: '고가 주류비', amount: result.premiumAlcoholTotal),
            _AmountRow(label: '개인 주문비', amount: result.personalOrderTotal),
            const Divider(),
            _AmountRow(
              label: '항목 합계',
              amount: result.itemsGrandTotal,
              emphasize: true,
            ),
            if (hasReceiptMismatch) ...[
              const SizedBox(height: 8),
              _WarningBanner(
                message: '영수증 총액(${_formatWon(result.receiptTotalAmount!)}원)과 '
                    '항목 합계가 다릅니다. 할인이나 봉사료가 있었는지 확인해 주세요.',
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
                                breakdown.participantName,
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
                  : '참여자 부담액 합계가 항목 합계와 다릅니다. 계산 로직을 확인해 주세요.',
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

String _formatWon(int amount) =>
    amount.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');

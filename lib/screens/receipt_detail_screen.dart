import 'package:flutter/material.dart';

import '../models/settlement_models.dart';
import '../services/gemini_receipt_service.dart';
import '../services/receipt_storage_service.dart';
import 'participant_input_screen.dart';

/// 저장된 영수증의 원본 사진과 분석 결과를 보여주는 화면.
///
/// Gemini API를 다시 호출하지 않고, 저장된 데이터만 읽어서 보여준다.
class ReceiptDetailScreen extends StatefulWidget {
  const ReceiptDetailScreen({
    super.key,
    required this.receipt,
    required this.storage,
  });

  final StoredReceipt receipt;
  final ReceiptStorageService storage;

  @override
  State<ReceiptDetailScreen> createState() => _ReceiptDetailScreenState();
}

class _ReceiptDetailScreenState extends State<ReceiptDetailScreen> {
  bool _isDeleting = false;
  String? _errorMessage;

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('영수증 삭제'),
        content: const Text('이 영수증을 삭제하시겠습니까? 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isDeleting = true;
      _errorMessage = null;
    });

    try {
      await widget.storage.delete(widget.receipt.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isDeleting = false;
        _errorMessage = error is ReceiptStorageException
            ? error.message
            : '영수증을 삭제하지 못했습니다.';
      });
    }
  }

  void _settleWithThisReceipt() {
    // Gemini를 다시 호출하지 않고, 저장된 분석 결과(사진·메뉴·가격·수량·분류)
    // 그대로 참여자 입력 화면으로 넘긴다. 저장된 원본 데이터는 건드리지 않는다.
    final workingSet = fromArchivedReceiptAnalysis(widget.receipt.analysis);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ParticipantInputScreen(workingSet: workingSet),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final analysis = widget.receipt.analysis;
    final theme = Theme.of(context);
    final imageFile = widget.receipt.imageFile;
    final itemsTotal = analysis.items.fold<int>(
      0,
      (sum, item) => sum + item.price,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('영수증 상세'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '삭제',
            onPressed: _isDeleting ? null : _confirmDelete,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (imageFile != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(imageFile),
              )
            else
              Container(
                height: 120,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.edit_note, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text(
                      '직접 입력한 영수증',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            if (analysis.paidAt != null) ...[
              Text(
                '결제 시각  ${_formatDateTime(analysis.paidAt!)}',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
            ],
            for (final item in analysis.items) ...[
              _ReadOnlyItemRow(item: item),
              const SizedBox(height: 12),
            ],
            const Divider(),
            _AmountRow(label: '항목 합계', amount: itemsTotal),
            if (analysis.totalAmount != null)
              _AmountRow(label: '영수증 총액', amount: analysis.totalAmount!),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _isDeleting ? null : _settleWithThisReceipt,
              icon: const Icon(Icons.calculate_outlined),
              label: const Text('이 영수증으로 정산하기'),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: TextStyle(color: theme.colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ],
            if (_isDeleting) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyItemRow extends StatelessWidget {
  const _ReadOnlyItemRow({required this.item});

  final ReceiptItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.name, style: theme.textTheme.bodyLarge),
              Text(
                '수량 ${item.quantity} · ${item.category.label}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Text('${_formatWon(item.price)}원'),
      ],
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({required this.label, required this.amount});

  final String label;
  final int amount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label), Text('${_formatWon(amount)}원')],
      ),
    );
  }
}

String _formatWon(int amount) =>
    amount.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');

String _formatDateTime(DateTime value) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)} '
      '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}

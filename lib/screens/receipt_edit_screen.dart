import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/settlement_models.dart';
import '../services/alcohol_category_classifier.dart';
import '../services/gemini_receipt_service.dart';

/// 영수증 분석 결과를 확인하고 메뉴명, 단가, 수량, 분류를 고치거나
/// 항목을 추가·삭제하는 화면.
///
/// 확인 버튼을 누르면 정산 화면에서 쓸 [ReceiptWorkingSet]을 돌려주며
/// 닫힌다. 뒤로 가면 null을 돌려준다. 총액을 비워 두면 결과의 총액은 null이다.
class ReceiptEditScreen extends StatefulWidget {
  const ReceiptEditScreen({super.key, required this.analysis});

  final ReceiptAnalysis analysis;

  @override
  State<ReceiptEditScreen> createState() => _ReceiptEditScreenState();
}

class _ReceiptEditScreenState extends State<ReceiptEditScreen> {
  late List<_EditableItem> _items;
  late final TextEditingController _totalText;

  @override
  void initState() {
    super.initState();
    _items = [
      for (final item in widget.analysis.items)
        _EditableItem(
          id: generateLocalId(),
          name: item.name,
          // Gemini가 돌려주는 item.price는 단가가 아니라 해당 줄의 합계
          // 금액이므로, 화면에서 수량과 함께 다룰 단가는 합계를 수량으로
          // 나누어 역산한다(보통 영수증은 단가 × 수량이 합계와 정확히
          // 맞아떨어진다). 나머지가 있으면(= 나누어떨어지지 않으면) 수정
          // 화면의 '항목 합계와 영수증 총액 차액' 경고로 드러난다.
          unitPrice: '${(item.price / item.quantity).round()}',
          quantity: '${item.quantity}',
          category: fromGeminiCategory(_resolveCategory(item)),
        )..addListener(_onChanged),
    ];
    _totalText = TextEditingController(
      text: widget.analysis.totalAmount?.toString() ?? '',
    )..addListener(_onChanged);
  }

  /// Gemini가 이미 '주류'로 분류한 항목만, 메뉴명으로 일반/고가 주류 등급을
  /// 보정한다. '음식'으로 분류된 항목은 이름에 우연히 비슷한 글자가 섞여
  /// 있어도 건드리지 않는다(음식을 주류로 잘못 바꾸는 위험을 피하기 위함).
  /// 메뉴명만으로 확신할 수 없으면 Gemini의 분류를 그대로 쓰고, 사용자가
  /// 화면에서 직접 바꿀 수 있다.
  ReceiptItemCategory _resolveCategory(ReceiptItem item) {
    if (item.category == ReceiptItemCategory.food) return item.category;
    return classifyAlcoholByName(item.name) ?? item.category;
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.dispose();
    }
    _totalText.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  void _addItem() {
    setState(() {
      _items.add(
        _EditableItem(
          id: generateLocalId(),
          name: '',
          unitPrice: '',
          quantity: '1',
          category: ItemCategory.food,
        )..addListener(_onChanged),
      );
    });
  }

  void _removeItem(_EditableItem item) {
    setState(() {
      _items.remove(item);
      item.dispose();
    });
  }

  int get _itemsTotal =>
      _items.fold(0, (sum, item) => sum + (item.lineTotal ?? 0));

  int? get _totalAmount => int.tryParse(_totalText.text);

  bool get _isValid => _items.every((item) => item.isValid);

  void _confirm() {
    Navigator.of(context).pop(
      ReceiptWorkingSet(
        items: [for (final item in _items) item.toSettlementItem()],
        totalAmount: _totalAmount,
        paidAt: widget.analysis.paidAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final paidAt = widget.analysis.paidAt;

    return Scaffold(
      appBar: AppBar(title: const Text('영수증 확인')),
      body: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            Expanded(
              child: _items.isEmpty
                  ? const Center(child: Text('추가된 메뉴가 없습니다. 항목을 추가해 주세요.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length + (paidAt == null ? 0 : 1),
                      separatorBuilder: (_, _) => const Divider(height: 24),
                      itemBuilder: (context, index) {
                        if (paidAt != null && index == 0) {
                          return Text(
                            '결제 시각  ${_formatDateTime(paidAt)}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          );
                        }
                        final itemIndex = paidAt == null ? index : index - 1;
                        final item = _items[itemIndex];
                        return _ItemRow(
                          item: item,
                          onDelete: () => _removeItem(item),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addItem,
                  icon: const Icon(Icons.add),
                  label: const Text('항목 추가'),
                ),
              ),
            ),
            // 키보드가 열려도 입력 칸이 보이도록 요약은 화면의 절반까지만 차지한다.
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: constraints.maxHeight / 2),
              child: _Summary(
                itemsTotal: _itemsTotal,
                totalText: _totalText,
                totalAmount: _totalAmount,
                // 합계 차액 경고가 떠 있어도 확인할 수 있다. 할인이나 봉사료가 있으면
                // 항목이 정확해도 합계와 총액이 다를 수 있기 때문이다.
                onConfirm: _isValid && _items.isNotEmpty ? _confirm : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 수정 중인 품목 한 줄의 입력 상태. 가격은 단가로 입력받고, 수량을 곱해
/// 항목 합계를 계산한다(저장되는 [SettlementItem.price]는 단가가 아니라
/// 항목 합계이며, 수량으로 다시 곱하지 않는다).
class _EditableItem {
  _EditableItem({
    required this.id,
    required String name,
    required String unitPrice,
    required String quantity,
    required ItemCategory category,
  }) : name = TextEditingController(text: name),
       unitPriceText = TextEditingController(text: unitPrice),
       quantityText = TextEditingController(text: quantity),
       category = ValueNotifier<ItemCategory>(category);

  final String id;
  final TextEditingController name;
  final TextEditingController unitPriceText;
  final TextEditingController quantityText;
  final ValueNotifier<ItemCategory> category;

  int? get unitPrice => int.tryParse(unitPriceText.text);
  int? get quantity => int.tryParse(quantityText.text);
  int? get lineTotal =>
      unitPrice != null && quantity != null ? unitPrice! * quantity! : null;

  bool get isNameValid => name.text.trim().isNotEmpty;
  bool get isUnitPriceValid => unitPrice != null && unitPrice! >= 0;
  bool get isQuantityValid => quantity != null && quantity! > 0;
  bool get isValid => isNameValid && isUnitPriceValid && isQuantityValid;

  void addListener(VoidCallback listener) {
    name.addListener(listener);
    unitPriceText.addListener(listener);
    quantityText.addListener(listener);
    category.addListener(listener);
  }

  SettlementItem toSettlementItem() => SettlementItem(
    id: id,
    name: name.text.trim(),
    price: lineTotal!,
    quantity: quantity!,
    category: category.value,
  );

  void dispose() {
    name.dispose();
    unitPriceText.dispose();
    quantityText.dispose();
    category.dispose();
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.onDelete});

  final _EditableItem item;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: item.name,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: '메뉴명',
                  border: const OutlineInputBorder(),
                  errorText: item.isNameValid ? null : '메뉴명을 입력하세요',
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '항목 삭제',
              onPressed: onDelete,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 104,
              child: TextField(
                controller: item.unitPriceText,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.end,
                inputFormatters: _amountInputFormatters,
                decoration: InputDecoration(
                  labelText: '단가',
                  suffixText: '원',
                  border: const OutlineInputBorder(),
                  errorText: item.isUnitPriceValid ? null : '단가를 입력하세요',
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 64,
              child: TextField(
                controller: item.quantityText,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.end,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                decoration: InputDecoration(
                  labelText: '수량',
                  border: const OutlineInputBorder(),
                  errorText: item.isQuantityValid ? null : '수량을 입력하세요',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ValueListenableBuilder<ItemCategory>(
                valueListenable: item.category,
                builder: (context, category, _) {
                  return DropdownButtonFormField<ItemCategory>(
                    initialValue: category,
                    decoration: const InputDecoration(
                      labelText: '분류',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final value in ItemCategory.values)
                        DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) item.category.value = value;
                    },
                  );
                },
              ),
            ),
          ],
        ),
        if (item.lineTotal != null) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '줄 합계 ${_formatWon(item.lineTotal!)}원',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.itemsTotal,
    required this.totalText,
    required this.totalAmount,
    required this.onConfirm,
  });

  final int itemsTotal;
  final TextEditingController totalText;
  final int? totalAmount;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final total = totalAmount;

    return Material(
      elevation: 4,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AmountRow(label: '항목 합계', amount: itemsTotal),
              const SizedBox(height: 12),
              TextField(
                controller: totalText,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.end,
                inputFormatters: _amountInputFormatters,
                decoration: InputDecoration(
                  labelText: '영수증 총액',
                  suffixText: '원',
                  border: const OutlineInputBorder(),
                  helperText: total == null ? '총액을 입력하면 항목 합계와 비교합니다.' : null,
                  helperMaxLines: 2,
                ),
              ),
              if (total != null && total != itemsTotal) ...[
                const SizedBox(height: 8),
                _MismatchWarning(difference: (total - itemsTotal).abs()),
              ],
              const SizedBox(height: 12),
              FilledButton(onPressed: onConfirm, child: const Text('다음')),
            ],
          ),
        ),
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({required this.label, required this.amount});

  final String label;
  final int amount;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      children: [Text(label), Text('${_formatWon(amount)}원')],
    );
  }
}

class _MismatchWarning extends StatelessWidget {
  const _MismatchWarning({required this.difference});

  final int difference;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Semantics(
      liveRegion: true,
      child: Container(
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
              child: Text(
                '항목 합계와 영수증 총액이 ${_formatWon(difference)}원 다릅니다. '
                '메뉴명과 가격을 확인해 주세요.',
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final _amountInputFormatters = <TextInputFormatter>[
  FilteringTextInputFormatter.digitsOnly,
  LengthLimitingTextInputFormatter(10),
];

String _formatWon(int amount) =>
    amount.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');

String _formatDateTime(DateTime value) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)} '
      '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}

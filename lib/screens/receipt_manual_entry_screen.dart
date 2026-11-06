import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/settlement_models.dart';

/// 영수증 사진 없이 메뉴를 직접 입력해 정산 품목을 만드는 화면.
///
/// 확인을 누르면 [ReceiptWorkingSet]을 돌려주며 닫힌다. 원본 사진이 없는
/// 영수증을 로컬 보관함(ReceiptStorageService)에 저장하는 일은 이 화면을
/// 호출한 쪽(ReceiptUploadScreen)이 담당한다.
class ReceiptManualEntryScreen extends StatefulWidget {
  const ReceiptManualEntryScreen({super.key});

  @override
  State<ReceiptManualEntryScreen> createState() =>
      _ReceiptManualEntryScreenState();
}

class _ReceiptManualEntryScreenState extends State<ReceiptManualEntryScreen> {
  final List<_ManualItem> _items = [];
  late final TextEditingController _totalText;

  @override
  void initState() {
    super.initState();
    _totalText = TextEditingController()..addListener(_onChanged);
    _addItem();
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
      _items.add(_ManualItem(id: generateLocalId())..addListener(_onChanged));
    });
  }

  void _removeItem(_ManualItem item) {
    setState(() {
      _items.remove(item);
      item.dispose();
    });
  }

  int get _itemsTotal =>
      _items.fold(0, (sum, item) => sum + (item.lineTotal ?? 0));

  int? get _totalAmount => int.tryParse(_totalText.text);

  bool get _isValid => _items.isNotEmpty && _items.every((item) => item.isValid);

  void _confirm() {
    Navigator.of(context).pop(
      ReceiptWorkingSet(
        items: [for (final item in _items) item.toSettlementItem()],
        totalAmount: _totalAmount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('직접 입력')),
      body: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            Expanded(
              child: _items.isEmpty
                  ? const Center(child: Text('항목을 추가해 주세요.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const Divider(height: 24),
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return _ManualItemRow(
                          item: item,
                          onDelete: _items.length > 1
                              ? () => _removeItem(item)
                              : null,
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
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: constraints.maxHeight / 2),
              child: Material(
                elevation: 4,
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _AmountRow(label: '항목 합계', amount: _itemsTotal),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _totalText,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.end,
                          inputFormatters: _amountInputFormatters,
                          decoration: InputDecoration(
                            labelText: '영수증 총액 (선택)',
                            suffixText: '원',
                            border: const OutlineInputBorder(),
                            helperText: _totalAmount == null
                                ? '총액을 입력하면 항목 합계와 비교합니다.'
                                : null,
                            helperMaxLines: 2,
                          ),
                        ),
                        if (_totalAmount != null &&
                            _totalAmount != _itemsTotal) ...[
                          const SizedBox(height: 8),
                          _MismatchWarning(
                            difference: (_totalAmount! - _itemsTotal).abs(),
                          ),
                        ],
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _isValid ? _confirm : null,
                          child: const Text('다음'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 직접 입력 중인 품목 한 줄의 입력 상태. 가격은 단가로 입력받고,
/// 수량을 곱해 줄 합계를 계산한다(저장되는 [SettlementItem.price]는 줄 합계).
class _ManualItem {
  _ManualItem({required this.id})
    : name = TextEditingController(),
      unitPriceText = TextEditingController(),
      quantityText = TextEditingController(text: '1'),
      category = ValueNotifier<ItemCategory>(ItemCategory.food);

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

class _ManualItemRow extends StatelessWidget {
  const _ManualItemRow({required this.item, required this.onDelete});

  final _ManualItem item;
  final VoidCallback? onDelete;

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

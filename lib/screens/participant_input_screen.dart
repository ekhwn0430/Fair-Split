import 'package:flutter/material.dart';

import '../models/settlement_models.dart';
import 'settlement_result_screen.dart';

/// 참여자를 입력하고, 개인 주문 항목을 참여자에게 배정하는 화면.
///
/// 1차 모임 하나만 다루며(1차·2차 확장은 추후 과제), 최소 1명 이상의
/// 참여자가 있어야 다음 단계(정산 결과)로 이동할 수 있다.
class ParticipantInputScreen extends StatefulWidget {
  const ParticipantInputScreen({super.key, required this.workingSet});

  final ReceiptWorkingSet workingSet;

  @override
  State<ParticipantInputScreen> createState() => _ParticipantInputScreenState();
}

class _ParticipantInputScreenState extends State<ParticipantInputScreen> {
  final List<_EditableParticipant> _participants = [];
  late List<SettlementItem> _items;

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.workingSet.items);
    _addParticipant();
  }

  @override
  void dispose() {
    for (final participant in _participants) {
      participant.dispose();
    }
    super.dispose();
  }

  void _onChanged() => setState(() {});

  void _addParticipant() {
    setState(() {
      _participants.add(
        _EditableParticipant(id: generateLocalId())..addListener(_onChanged),
      );
    });
  }

  void _removeParticipant(_EditableParticipant participant) {
    setState(() {
      _participants.remove(participant);
      participant.dispose();
      // 삭제된 참여자에게 배정돼 있던 개인 주문 수량은 배정을 해제한다.
      _items = [
        for (final item in _items)
          item.copyWith(
            assignments: [
              for (final assignment in item.assignments)
                if (assignment.participantId != participant.id) assignment,
            ],
          ),
      ];
    });
  }

  /// [item]에서 [participantId]에게 배정된 수량을 가져온다. 배정이 없으면 0.
  int _assignedQuantityOf(SettlementItem item, String participantId) {
    for (final assignment in item.assignments) {
      if (assignment.participantId == participantId) return assignment.quantity;
    }
    return 0;
  }

  /// [item]에서 [participantId]의 배정 수량을 [quantity]로 바꾼다
  /// (0이면 배정을 지운다). 참여자 목록 순서대로 배정을 다시 쌓아,
  /// 배정 내역이 항상 같은 순서를 유지하게 한다(1원 나머지 분배가
  /// 매번 같은 참여자부터 적용되도록).
  void _setAssignedQuantity(SettlementItem item, String participantId, int quantity) {
    setState(() {
      final current = {
        for (final assignment in item.assignments)
          assignment.participantId: assignment.quantity,
      };
      if (quantity <= 0) {
        current.remove(participantId);
      } else {
        current[participantId] = quantity;
      }

      final newAssignments = [
        for (final participant in _participants)
          if (current.containsKey(participant.id))
            PersonalOrderAssignment(
              participantId: participant.id,
              quantity: current[participant.id]!,
            ),
      ];

      _items = [
        for (final existing in _items)
          existing.id == item.id
              ? existing.copyWith(assignments: newAssignments)
              : existing,
      ];
    });
  }

  void _incrementAssignment(SettlementItem item, String participantId) {
    final remaining = item.quantity - item.assignedQuantity;
    if (remaining <= 0) return;
    _setAssignedQuantity(
      item,
      participantId,
      _assignedQuantityOf(item, participantId) + 1,
    );
  }

  void _decrementAssignment(SettlementItem item, String participantId) {
    final current = _assignedQuantityOf(item, participantId);
    if (current <= 0) return;
    _setAssignedQuantity(item, participantId, current - 1);
  }

  List<SettlementItem> get _personalOrderItems => _items
      .where((item) => item.category == ItemCategory.personalOrder)
      .toList();

  /// '개인 주문'은 수량이 전부 배정되지 않으면 비용을 누구에게도 자동으로
  /// 나눠서는 안 되므로, 정산으로 넘어가기 전에 품목마다 전체 수량이 현재
  /// 참여자들에게 정확히 다 배정됐는지 검증한다. 참여자를 삭제하거나(위
  /// _removeParticipant) 품목 수량이 달라져도 이 조건은 매번 새로
  /// 계산되므로 항상 최신 상태를 반영한다.
  bool get _allPersonalOrdersAssigned {
    final participantIds = _participants.map((p) => p.id).toSet();
    return _personalOrderItems.every((item) {
      final validAssignedQuantity = item.assignments
          .where((assignment) => participantIds.contains(assignment.participantId))
          .fold(0, (sum, assignment) => sum + assignment.quantity);
      return validAssignedQuantity == item.quantity;
    });
  }

  bool get _isValid =>
      _participants.isNotEmpty &&
      _participants.every((p) => p.isValid) &&
      _allPersonalOrdersAssigned;

  Future<void> _pickJoinTime(_EditableParticipant participant) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: participant.joinTime.value ?? TimeOfDay.now(),
    );
    if (picked != null) {
      participant.joinTime.value = picked;
    }
  }

  void _goToResult() {
    final participants = [for (final p in _participants) p.toParticipant()];

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SettlementResultScreen(
          items: _items,
          participants: participants,
          receiptTotalAmount: widget.workingSet.totalAmount,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final personalOrderItems = _personalOrderItems;

    return Scaffold(
      appBar: AppBar(title: const Text('참여자 입력')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('참여자', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final participant in _participants)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ParticipantCard(
                  participant: participant,
                  onDelete: _participants.length > 1
                      ? () => _removeParticipant(participant)
                      : null,
                  onPickJoinTime: () => _pickJoinTime(participant),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addParticipant,
                icon: const Icon(Icons.person_add_alt),
                label: const Text('참여자 추가'),
              ),
            ),
            if (personalOrderItems.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('개인 주문 배정', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                '아래 항목은 분담하지 않고, 수량만큼 담당 참여자에게 나눠 부담합니다.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              for (final item in personalOrderItems)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _PersonalOrderAssignmentCard(
                    item: item,
                    participants: _participants,
                    onIncrement: (participantId) =>
                        _incrementAssignment(item, participantId),
                    onDecrement: (participantId) =>
                        _decrementAssignment(item, participantId),
                  ),
                ),
              if (!_allPersonalOrdersAssigned)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '수량이 다 배정되지 않은 개인 주문이 있습니다. '
                    '모든 개인 주문의 수량을 참여자에게 전부 배정해야 정산을 진행할 수 있습니다.',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
            const SizedBox(height: 16),
            if (!_isValid && (_participants.isEmpty || !_participants.every((p) => p.isValid)))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '참여자를 1명 이상 추가하고 이름을 입력해야 다음 단계로 이동할 수 있습니다.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            FilledButton(
              onPressed: _isValid ? _goToResult : null,
              child: const Text('정산하기'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 입력 중인 참여자 한 명의 상태.
class _EditableParticipant {
  _EditableParticipant({required this.id})
    : name = TextEditingController(),
      joinTime = ValueNotifier<TimeOfDay?>(null),
      ateFood = ValueNotifier<bool>(true),
      drankAlcohol = ValueNotifier<bool>(false),
      drankBeverage = ValueNotifier<bool>(false);

  final String id;
  final TextEditingController name;
  final ValueNotifier<TimeOfDay?> joinTime;
  final ValueNotifier<bool> ateFood;
  final ValueNotifier<bool> drankAlcohol;
  final ValueNotifier<bool> drankBeverage;

  bool get isValid => name.text.trim().isNotEmpty;

  void addListener(VoidCallback listener) {
    name.addListener(listener);
    joinTime.addListener(listener);
    ateFood.addListener(listener);
    drankAlcohol.addListener(listener);
    drankBeverage.addListener(listener);
  }

  Participant toParticipant() => Participant(
    id: id,
    name: name.text.trim(),
    joinTime: joinTime.value,
    ateFood: ateFood.value,
    drankAlcohol: drankAlcohol.value,
    drankBeverage: drankBeverage.value,
  );

  void dispose() {
    name.dispose();
    joinTime.dispose();
    ateFood.dispose();
    drankAlcohol.dispose();
    drankBeverage.dispose();
  }
}

class _ParticipantCard extends StatelessWidget {
  const _ParticipantCard({
    required this.participant,
    required this.onDelete,
    required this.onPickJoinTime,
  });

  final _EditableParticipant participant;
  final VoidCallback? onDelete;
  final VoidCallback onPickJoinTime;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: participant.name,
                    decoration: InputDecoration(
                      labelText: '이름',
                      border: const OutlineInputBorder(),
                      errorText: participant.isValid ? null : '이름을 입력하세요',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '참여자 삭제',
                  onPressed: onDelete,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<TimeOfDay?>(
              valueListenable: participant.joinTime,
              builder: (context, time, _) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: onPickJoinTime,
                    icon: const Icon(Icons.schedule),
                    label: Text(
                      time == null
                          ? '참여 시간 선택 (선택)'
                          : '참여 시간  ${time.format(context)}',
                    ),
                  ),
                );
              },
            ),
            ValueListenableBuilder<bool>(
              valueListenable: participant.ateFood,
              builder: (context, value, _) => CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('음식 섭취'),
                value: value,
                onChanged: (checked) => participant.ateFood.value = checked ?? false,
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: participant.drankAlcohol,
              builder: (context, value, _) => CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('음주 여부'),
                value: value,
                onChanged: (checked) =>
                    participant.drankAlcohol.value = checked ?? false,
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: participant.drankBeverage,
              builder: (context, value, _) => CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('음료수 섭취'),
                value: value,
                onChanged: (checked) =>
                    participant.drankBeverage.value = checked ?? false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 개인 주문 품목 한 건을 참여자별 수량으로 나눠 배정하는 카드.
///
/// 같은 메뉴의 여러 수량을 여러 참여자가 나눠 가질 수 있어, 참여자마다
/// +/- 버튼으로 배정 수량을 조절한다. 배정된 수량의 합이 품목 전체
/// 수량과 같아져야 완료로 표시된다.
class _PersonalOrderAssignmentCard extends StatelessWidget {
  const _PersonalOrderAssignmentCard({
    required this.item,
    required this.participants,
    required this.onIncrement,
    required this.onDecrement,
  });

  final SettlementItem item;
  final List<_EditableParticipant> participants;
  final ValueChanged<String> onIncrement;
  final ValueChanged<String> onDecrement;

  int _quantityFor(String participantId) {
    for (final assignment in item.assignments) {
      if (assignment.participantId == participantId) return assignment.quantity;
    }
    return 0;
  }

  /// 참여자별로 배정받을 금액을 미리 계산한다. 정산 계산기
  /// ([DemoSettlementCalculator])와 같은 방식(수량 단위로 나눈 금액을
  /// 배정 순서대로 이어 붙이는 방식)으로 계산하므로, 여기서 보여주는
  /// 금액과 실제 정산 결과가 항상 같다.
  Map<String, int> _shareByParticipant() {
    final unitPrices = splitAmountByQuantity(item.price, item.quantity);
    final shares = <String, int>{};
    var cursor = 0;
    for (final assignment in item.assignments) {
      final share = unitPrices
          .skip(cursor)
          .take(assignment.quantity)
          .fold(0, (sum, unitPrice) => sum + unitPrice);
      cursor += assignment.quantity;
      shares[assignment.participantId] = share;
    }
    return shares;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final assignedQuantity = item.assignedQuantity;
    final isComplete = assignedQuantity == item.quantity;
    final hasCapacity = assignedQuantity < item.quantity;
    final shares = _shareByParticipant();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${item.name} · ${_formatWon(item.price)}원 · ${item.quantity}개',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            for (final participant in participants)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        participant.name.text.trim().isEmpty
                            ? '(이름 없음)'
                            : participant.name.text.trim(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      tooltip: '수량 줄이기',
                      onPressed: _quantityFor(participant.id) > 0
                          ? () => onDecrement(participant.id)
                          : null,
                    ),
                    SizedBox(
                      width: 24,
                      child: Text(
                        '${_quantityFor(participant.id)}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      tooltip: '수량 늘리기',
                      onPressed: hasCapacity
                          ? () => onIncrement(participant.id)
                          : null,
                    ),
                    SizedBox(
                      width: 72,
                      child: Text(
                        '${_formatWon(shares[participant.id] ?? 0)}원',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Text(
              isComplete
                  ? '배정 완료 ($assignedQuantity/${item.quantity}개)'
                  : '배정 수량 $assignedQuantity/${item.quantity}개 — 모두 배정해야 합니다',
              style: TextStyle(
                color: isComplete ? theme.colorScheme.primary : theme.colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatWon(int amount) =>
    amount.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');

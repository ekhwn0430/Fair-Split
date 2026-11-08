import 'dart:math';

import 'package:flutter/material.dart';

import '../models/settlement_models.dart';
import '../services/fair_settlement_calculator.dart';
import 'settlement_result_screen.dart';

/// 참여자를 입력하고, 개인 주문 항목을 참여자에게 배정하는 화면.
///
/// 1차 모임 하나만 다루며(1차·2차 확장은 추후 과제), 최소 1명 이상의
/// 참여자가 있어야 다음 단계(정산 결과)로 이동할 수 있다.
class ParticipantInputScreen extends StatefulWidget {
  const ParticipantInputScreen({
    super.key,
    required this.workingSet,
    this.initialParticipants = const [],
    this.startedAt,
    this.personalOrderHints = const {},
  });

  final ReceiptWorkingSet workingSet;

  /// 모임방에서 넘어온 참여자(이름·도착 시각·체크 항목). 비어 있으면 빈
  /// 참여자 한 명으로 시작한다.
  final List<Participant> initialParticipants;

  /// 모임방의 '술자리 시작' 기록. 없으면 이 화면에서 시작 시각을 고른다.
  final DateTime? startedAt;

  /// 참여자 id → 모임방에서 본인이 적은 개인 주문 메뉴명. 영수증 항목명과
  /// 맞으면 그 사람에게 1개씩 미리 배정한다(총무가 수정 가능).
  final Map<String, List<String>> personalOrderHints;

  @override
  State<ParticipantInputScreen> createState() => _ParticipantInputScreenState();
}

class _ParticipantInputScreenState extends State<ParticipantInputScreen> {
  final List<_EditableParticipant> _participants = [];
  late List<SettlementItem> _items;
  TimeOfDay? _startTime;

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.workingSet.items);
    if (widget.initialParticipants.isEmpty) {
      _addParticipant();
    } else {
      for (final participant in widget.initialParticipants) {
        _participants.add(
          _EditableParticipant.from(participant)..addListener(_onChanged),
        );
      }
      _items = prefillAssignments(
        _items,
        [for (final p in widget.initialParticipants) p.id],
        widget.personalOrderHints,
      );
    }
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

  /// 주문한 사람에게 배정해야 하는 항목(개인 주문 + 고가 주류).
  List<SettlementItem> get _personalOrderItems => _items
      .where(
        (item) =>
            item.category == ItemCategory.personalOrder ||
            item.category == ItemCategory.premiumAlcohol,
      )
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

  /// 음식·술 항목이 있는데 부담할 사람이 아무도 체크되지 않은 경우처럼
  /// 정산을 막아야 하는 문제. 개인 주문 미배정 문제는 아래에서 따로 보여준다.
  List<String> get _checkProblems {
    if (_participants.isEmpty) return const [];
    return FairSettlementCalculator.validate(
      items: _items,
      participants: [for (final p in _participants) p.toParticipant()],
    ).where((problem) => !problem.contains('배정됐습니다')).toList();
  }

  bool get _isValid =>
      _participants.isNotEmpty &&
      _participants.every((p) => p.isValid) &&
      _allPersonalOrdersAssigned &&
      _checkProblems.isEmpty;

  DateTime? get _sessionStart {
    final fixed = widget.startedAt;
    if (fixed != null) return fixed;
    final time = _startTime;
    final end = widget.workingSet.paidAt;
    if (time == null || end == null) return null;
    return resolveTimeOfDay(time, end);
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime ?? TimeOfDay.now(),
    );
    if (picked != null) setState(() => _startTime = picked);
  }

  Future<void> _pickLeaveTime(_EditableParticipant participant) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: participant.leaveTime.value ?? TimeOfDay.now(),
    );
    if (picked != null) {
      participant.leaveTime.value = picked;
    }
  }

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

    // 룰렛 시드는 화면 이동 시 한 번만 정한다. 결과 화면을 다시 그려도
    // 당첨자가 바뀌지 않는다.
    final calculator = FairSettlementCalculator(
      startedAt: _sessionStart,
      endedAt: widget.workingSet.paidAt,
      rouletteSeed: Random().nextInt(1 << 31),
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SettlementResultScreen(
          items: _items,
          participants: participants,
          receiptTotalAmount: widget.workingSet.totalAmount,
          calculator: calculator,
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
            _SessionTimeCard(
              paidAt: widget.workingSet.paidAt,
              fixedStart: widget.startedAt,
              startTime: _startTime,
              onPickStart: _pickStartTime,
            ),
            const SizedBox(height: 16),
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
                  onPickLeaveTime: () => _pickLeaveTime(participant),
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
                '고가 주류·개인 주문·음료수는 나눠 내지 않고, 주문한 사람이 '
                '수량만큼 부담합니다.',
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
            for (final problem in _checkProblems)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  problem,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
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
      leaveTime = ValueNotifier<TimeOfDay?>(null),
      ateFood = ValueNotifier<bool>(true),
      drankAlcohol = ValueNotifier<bool>(false),
      drankBeverage = ValueNotifier<bool>(false);

  /// 모임방에서 넘어온 참여자로 채운다. 서버의 정확한 도착·퇴장 시각은
  /// 그대로 넘기고, 화면에는 시:분으로 보여준다.
  _EditableParticipant.from(Participant participant)
    : id = participant.id,
      name = TextEditingController(text: participant.name),
      joinTime = ValueNotifier<TimeOfDay?>(
        participant.joinTime ??
            (participant.arrivedAt == null
                ? null
                : TimeOfDay.fromDateTime(participant.arrivedAt!)),
      ),
      leaveTime = ValueNotifier<TimeOfDay?>(
        participant.leaveTime ??
            (participant.leftAt == null
                ? null
                : TimeOfDay.fromDateTime(participant.leftAt!)),
      ),
      ateFood = ValueNotifier<bool>(participant.ateFood),
      drankAlcohol = ValueNotifier<bool>(participant.drankAlcohol),
      drankBeverage = ValueNotifier<bool>(participant.drankBeverage),
      _serverArrivedAt = participant.arrivedAt,
      _serverLeftAt = participant.leftAt;

  final String id;
  final TextEditingController name;
  final ValueNotifier<TimeOfDay?> joinTime;
  final ValueNotifier<TimeOfDay?> leaveTime;
  DateTime? _serverArrivedAt;
  DateTime? _serverLeftAt;
  final ValueNotifier<bool> ateFood;
  final ValueNotifier<bool> drankAlcohol;
  final ValueNotifier<bool> drankBeverage;

  bool get isValid => name.text.trim().isNotEmpty;

  void addListener(VoidCallback listener) {
    name.addListener(listener);
    joinTime.addListener(listener);
    leaveTime.addListener(listener);
    // 총무가 시각을 직접 고치면 서버 기록 대신 고친 값을 쓴다.
    joinTime.addListener(() => _serverArrivedAt = null);
    leaveTime.addListener(() => _serverLeftAt = null);
    ateFood.addListener(listener);
    drankAlcohol.addListener(listener);
    drankBeverage.addListener(listener);
  }

  Participant toParticipant() => Participant(
    id: id,
    name: name.text.trim(),
    joinTime: joinTime.value,
    leaveTime: leaveTime.value,
    arrivedAt: _serverArrivedAt,
    leftAt: _serverLeftAt,
    ateFood: ateFood.value,
    drankAlcohol: drankAlcohol.value,
    drankBeverage: drankBeverage.value,
  );

  void dispose() {
    name.dispose();
    joinTime.dispose();
    leaveTime.dispose();
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
    required this.onPickLeaveTime,
  });

  final _EditableParticipant participant;
  final VoidCallback? onDelete;
  final VoidCallback onPickJoinTime;
  final VoidCallback onPickLeaveTime;

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
                          ? '도착 시각 (비우면 시작부터)'
                          : '도착  ${time.format(context)}',
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 4),
            ValueListenableBuilder<TimeOfDay?>(
              valueListenable: participant.leaveTime,
              builder: (context, time, _) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: onPickLeaveTime,
                    icon: const Icon(Icons.logout),
                    label: Text(
                      time == null
                          ? '먼저 간 경우 퇴장 시각 (비우면 끝까지)'
                          : '퇴장  ${time.format(context)}',
                    ),
                  ),
                );
              },
            ),
            ValueListenableBuilder<bool>(
              valueListenable: participant.ateFood,
              builder: (context, value, _) => CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('음식 먹음'),
                value: value,
                onChanged: (checked) => participant.ateFood.value = checked ?? false,
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: participant.drankAlcohol,
              builder: (context, value, _) => CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('소주·맥주 마심'),
                value: value,
                onChanged: (checked) =>
                    participant.drankAlcohol.value = checked ?? false,
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

/// 술자리 시작·종료 시각. 종료는 영수증 결제 시각이고, 시작은 모임방
/// 기록이 있으면 그 값을, 없으면 총무가 고른 값을 쓴다.
class _SessionTimeCard extends StatelessWidget {
  const _SessionTimeCard({
    required this.paidAt,
    required this.fixedStart,
    required this.startTime,
    required this.onPickStart,
  });

  final DateTime? paidAt;
  final DateTime? fixedStart;
  final TimeOfDay? startTime;
  final VoidCallback onPickStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final end = paidAt;
    final start = fixedStart;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('술자리 시간', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (start != null)
              Text('시작  ${TimeOfDay.fromDateTime(start).format(context)} '
                  '(모임방 기록)')
            else
              OutlinedButton.icon(
                onPressed: onPickStart,
                icon: const Icon(Icons.play_arrow),
                label: Text(
                  startTime == null
                      ? '시작 시각 (비우면 가장 이른 도착)'
                      : '시작  ${startTime!.format(context)}',
                ),
              ),
            const SizedBox(height: 4),
            Text(
              end == null
                  ? '결제 시각이 없어 참석 시간 가중치 없이 계산합니다.'
                  : '종료  ${TimeOfDay.fromDateTime(end).format(context)} '
                      '(영수증 결제 시각)',
              style: end == null
                  ? TextStyle(color: theme.colorScheme.onSurfaceVariant)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// 참여자가 모임방에 적은 개인 주문 메뉴명을 영수증 항목과 맞춰, 배정되지
/// 않은 수량을 1개씩 미리 배정한다. 이름이 서로 포함 관계면(공백 무시) 같은
/// 메뉴로 본다. 수량을 넘겨 배정하지는 않는다.
List<SettlementItem> prefillAssignments(
  List<SettlementItem> items,
  List<String> participantOrder,
  Map<String, List<String>> hints,
) {
  String normalize(String value) => value.replaceAll(' ', '').toLowerCase();

  SettlementItem prefill(SettlementItem item) {
    if (item.category != ItemCategory.personalOrder &&
        item.category != ItemCategory.premiumAlcohol) {
      return item;
    }
    final itemName = normalize(item.name);
    final counts = {
      for (final a in item.assignments) a.participantId: a.quantity,
    };
    var remaining = item.quantity - item.assignedQuantity;
    for (final participantId in participantOrder) {
      for (final hint in hints[participantId] ?? const <String>[]) {
        final hintName = normalize(hint);
        if (remaining <= 0 || hintName.isEmpty) continue;
        if (!itemName.contains(hintName) && !hintName.contains(itemName)) {
          continue;
        }
        counts[participantId] = (counts[participantId] ?? 0) + 1;
        remaining -= 1;
      }
    }
    return item.copyWith(
      assignments: [
        for (final participantId in participantOrder)
          if ((counts[participantId] ?? 0) > 0)
            PersonalOrderAssignment(
              participantId: participantId,
              quantity: counts[participantId]!,
            ),
      ],
    );
  }

  return [for (final item in items) prefill(item)];
}

String _formatWon(int amount) =>
    amount.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');

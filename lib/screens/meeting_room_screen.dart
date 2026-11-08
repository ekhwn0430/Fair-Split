import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fair_split/config.dart';
import 'package:fair_split/models/settlement_models.dart';
import 'package:fair_split/screens/receipt_upload_screen.dart';
import 'package:fair_split/services/auth_service.dart';
import 'package:fair_split/services/gemini_receipt_service.dart';
import 'package:fair_split/services/receipt_storage_service.dart';

class MeetingRoomScreen extends StatefulWidget {
  final String meetingId;
  final String meetingName;
  final bool isHost;
  final String? guestId;
  final String? guestName;

  const MeetingRoomScreen({
    super.key,
    required this.meetingId,
    required this.meetingName,
    required this.isHost,
    this.guestId,
    this.guestName,
  });

  @override
  State<MeetingRoomScreen> createState() => _MeetingRoomScreenState();
}

class _MeetingRoomScreenState extends State<MeetingRoomScreen> {
  final _authService = AuthService();
  final _db = FirebaseFirestore.instance;
  bool _arrived = false;
  bool _left = false;
  bool _isLoading = false;

  bool _eatFood = true;
  bool _drinkAlcohol = false;
  bool _drinkSoftDrink = false;
  int _softDrinkCount = 1;

  // 개인 주문 목록 (이름, 금액)
  final List<Map<String, dynamic>> _personalOrders = [];
  final _orderNameController = TextEditingController();
  final _orderPriceController = TextEditingController();

  String get _myId =>
      widget.guestId ?? _authService.currentUser?.uid ?? 'unknown';

  void _showAddOrderDialog() {
    _orderNameController.clear();
    _orderPriceController.clear();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('개인 주문 추가'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _orderNameController,
              decoration: const InputDecoration(
                labelText: '메뉴 이름',
                hintText: '예) 하이볼, 양주',
                prefixIcon: Icon(Icons.restaurant_menu, size: 20),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _orderPriceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '금액 (원)',
                hintText: '예) 9000',
                prefixIcon: Icon(Icons.attach_money, size: 20),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              final name = _orderNameController.text.trim();
              final price = int.tryParse(_orderPriceController.text.trim());
              if (name.isEmpty || price == null || price <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('이름과 금액을 올바르게 입력해주세요')),
                );
                return;
              }
              setState(() {
                _personalOrders.add({'name': name, 'price': price});
              });
              Navigator.pop(context);
            },
            child: const Text('추가'),
          ),
        ],
      ),
    );
  }

  Future<void> _arrive() async {
    setState(() => _isLoading = true);
    final totalPersonal = _personalOrders.fold<int>(
        0, (sum, order) => sum + (order['price'] as int));

    await _db.collection('meetings').doc(widget.meetingId).update({
      'members.$_myId.arrivedAt': FieldValue.serverTimestamp(),
      'members.$_myId.eatFood': _eatFood,
      'members.$_myId.drinkAlcohol': _drinkAlcohol,
      'members.$_myId.drinkSoftDrink': _drinkSoftDrink,
      'members.$_myId.softDrinkCount': _drinkSoftDrink ? _softDrinkCount : 0,
      'members.$_myId.personalOrders': _personalOrders,
      'members.$_myId.personalTotal': totalPersonal,
    });
    setState(() {
      _arrived = true;
      _isLoading = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('도착 완료! 정보가 총무에게 전달됐어요 😊')),
      );
    }
  }

  /// 먼저 자리를 뜨는 참여자의 퇴장 시각을 기록한다. 기록이 없으면
  /// 결제 시각까지 있었던 것으로 계산한다.
  Future<void> _leave() async {
    await _db.collection('meetings').doc(widget.meetingId).update({
      'members.$_myId.leftAt': FieldValue.serverTimestamp(),
    });
    setState(() => _left = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('퇴장 시간이 기록됐어요. 조심히 가세요!')),
      );
    }
  }

  /// 총무: 모임방 기록(참여자·도착/퇴장·체크·개인 주문)을 가지고 영수증
  /// 정산 화면으로 이동한다. 참여자 입력을 총무가 다시 하지 않아도 된다.
  void _openSettlement(Map<String, dynamic> data) {
    if (geminiApiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('GEMINI_API_KEY가 없어 영수증 인식을 쓸 수 없습니다. '
              '직접 입력은 영수증 화면에서 가능합니다.'),
        ),
      );
    }

    DateTime? toDate(Object? value) =>
        value is Timestamp ? value.toDate() : null;

    final members = data['members'] as Map<String, dynamic>? ?? {};
    final participants = <Participant>[];
    final hints = <String, List<String>>{};
    for (final entry in members.entries) {
      final member = entry.value as Map<String, dynamic>;
      participants.add(
        Participant(
          id: entry.key,
          name: (member['name'] ?? '').toString(),
          arrivedAt: toDate(member['arrivedAt']),
          leftAt: toDate(member['leftAt']),
          ateFood: member['eatFood'] as bool? ?? true,
          drankAlcohol: member['drinkAlcohol'] as bool? ?? false,
          drankBeverage: member['drinkSoftDrink'] as bool? ?? false,
        ),
      );
      final orders = member['personalOrders'] as List<dynamic>? ?? const [];
      hints[entry.key] = [
        for (final order in orders)
          if (order is Map && order['name'] != null) order['name'].toString(),
      ];
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceiptUploadScreen(
          service: GeminiReceiptService(apiKey: geminiApiKey),
          storage: ReceiptStorageService(),
          initialParticipants: participants,
          startedAt: toDate(data['startedAt']),
          personalOrderHints: hints,
        ),
      ),
    );
  }

  Future<void> _startMeeting() async {
    await _db.collection('meetings').doc(widget.meetingId).update({
      'startedAt': FieldValue.serverTimestamp(),
      'status': 'started',
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('술자리 시작! 시작 시간이 기록됐어요 🍻')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(widget.meetingName),
        backgroundColor: Colors.white,
        actions: [
          if (widget.guestId != null)
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF3D7EFF).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                '게스트',
                style: TextStyle(
                  color: Color(0xFF3D7EFF),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _db.collection('meetings').doc(widget.meetingId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final members = data['members'] as Map<String, dynamic>? ?? {};
          final status = data['status'] ?? 'waiting';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 상태 배너
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: status == 'started'
                        ? const Color(0xFF1D9E75)
                        : Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        status == 'started'
                            ? Icons.local_bar
                            : Icons.hourglass_top,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        status == 'started'
                            ? '술자리 진행 중 🍻'
                            : '참여자 대기 중...',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 총무 전용: 시작 버튼
                if (widget.isHost && status != 'started') ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _startMeeting,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('술자리 시작!'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // 총무 전용: 영수증으로 정산
                if (widget.isHost && status == 'started') ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _openSettlement(data),
                      icon: const Icon(Icons.receipt_long),
                      label: const Text('영수증으로 정산하기'),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // 참여자: 도착 체크 + 체크박스
                if (!widget.isHost) ...[
                  const Text(
                    '내 정보 입력',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1B1B1B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '오늘 먹고 마실 것들을 선택해주세요',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),

                  // 기본 체크박스
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade100),
                    ),
                    child: Column(
                      children: [
                        CheckboxListTile(
                          title: const Text('🍖 음식 먹어요'),
                          subtitle: const Text('안주, 음식류 (시간 비례 분담)'),
                          value: _eatFood,
                          activeColor: const Color(0xFF1D9E75),
                          onChanged: _arrived
                              ? null
                              : (val) => setState(() => _eatFood = val!),
                        ),
                        const Divider(height: 1),
                        CheckboxListTile(
                          title: const Text('🍺 일반 주류 마셔요'),
                          subtitle: const Text('소주·병맥주 (음주자끼리 시간 비례 분담)'),
                          value: _drinkAlcohol,
                          activeColor: const Color(0xFF1D9E75),
                          onChanged: _arrived
                              ? null
                              : (val) =>
                              setState(() => _drinkAlcohol = val!),
                        ),
                        const Divider(height: 1),
                        CheckboxListTile(
                          title: const Text('🥤 음료수 마셔요'),
                          subtitle: const Text('콜라, 사이다 등'),
                          value: _drinkSoftDrink,
                          activeColor: const Color(0xFF1D9E75),
                          onChanged: _arrived
                              ? null
                              : (val) =>
                              setState(() => _drinkSoftDrink = val!),
                        ),
                        if (_drinkSoftDrink && !_arrived)
                          Padding(
                            padding:
                            const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Row(
                              children: [
                                const Text('음료수 개수:',
                                    style: TextStyle(fontSize: 14)),
                                const SizedBox(width: 16),
                                IconButton(
                                  onPressed: _softDrinkCount > 1
                                      ? () => setState(
                                          () => _softDrinkCount--)
                                      : null,
                                  icon: const Icon(
                                      Icons.remove_circle_outline),
                                  color: const Color(0xFF1D9E75),
                                ),
                                Text(
                                  '$_softDrinkCount',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () =>
                                      setState(() => _softDrinkCount++),
                                  icon:
                                  const Icon(Icons.add_circle_outline),
                                  color: const Color(0xFF1D9E75),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 개인 주문 섹션
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '💳 개인 주문',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1B1B1B),
                            ),
                          ),
                          Text(
                            '나만 먹는 것 (본인 전액 부담)',
                            style:
                            TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                      if (!_arrived)
                        TextButton.icon(
                          onPressed: _showAddOrderDialog,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('추가'),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF1D9E75),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (_personalOrders.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade100),
                      ),
                      child: const Text(
                        '개인 주문 없음',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    ...List.generate(_personalOrders.length, (i) {
                      final order = _personalOrders[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade100),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.receipt_outlined,
                                size: 18, color: Colors.grey),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                order['name'],
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500),
                              ),
                            ),
                            Text(
                              '${order['price']}원',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1D9E75),
                              ),
                            ),
                            if (!_arrived)
                              IconButton(
                                onPressed: () => setState(
                                        () => _personalOrders.removeAt(i)),
                                icon: const Icon(Icons.close,
                                    size: 18, color: Colors.grey),
                              ),
                          ],
                        ),
                      );
                    }),

                  if (_personalOrders.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '합계: ${_personalOrders.fold<int>(0, (s, o) => s + (o['price'] as int))}원',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1D9E75),
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _arrived || _isLoading ? null : _arrive,
                      icon: const Icon(Icons.check_circle_outline),
                      label: Text(_arrived ? '도착 완료 ✓' : '도착했어요!'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _arrived
                            ? Colors.grey
                            : const Color(0xFF1D9E75),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  if (_arrived) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _left ? null : _leave,
                        icon: const Icon(Icons.logout),
                        label: Text(_left ? '퇴장 기록됨' : '먼저 가요 (퇴장 기록)'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                ],

                // 참여자 현황
                const Text(
                  '참여자 현황',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1B1B1B),
                  ),
                ),
                const SizedBox(height: 12),
                ...members.entries.map((entry) {
                  final member = entry.value as Map<String, dynamic>;
                  final arrived = member['arrivedAt'] != null;
                  final eats = member['eatFood'] ?? true;
                  final drinks = member['drinkAlcohol'] ?? false;
                  final drinksSoft = member['drinkSoftDrink'] ?? false;
                  final softCount = member['softDrinkCount'] ?? 0;
                  final isGuest = member['isGuest'] ?? false;
                  final personalTotal = member['personalTotal'] ?? 0;
                  final personalOrders =
                      member['personalOrders'] as List<dynamic>? ?? [];

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade100),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          backgroundColor: arrived
                              ? const Color(0xFF1D9E75)
                              : Colors.grey.shade300,
                          radius: 20,
                          child: Text(
                            member['name'].toString().substring(0, 1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    member['name'],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                  if (isGuest) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF3D7EFF)
                                            .withValues(alpha: 0.1),
                                        borderRadius:
                                        BorderRadius.circular(10),
                                      ),
                                      child: const Text(
                                        '게스트',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Color(0xFF3D7EFF),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: [
                                  if (eats)
                                    _Tag(
                                        label: '🍖 음식',
                                        color: Colors.green),
                                  if (drinks)
                                    _Tag(
                                        label: '🍺 일반주류',
                                        color: Colors.orange),
                                  if (!drinks)
                                    _Tag(
                                        label: '🚫 비음주',
                                        color: Colors.grey),
                                  if (drinksSoft)
                                    _Tag(
                                        label: '🥤 음료수 ${softCount}잔',
                                        color: Colors.blue),
                                  if (personalOrders.isNotEmpty)
                                    _Tag(
                                        label:
                                        '💳 개인주문 ${personalTotal}원',
                                        color: Colors.deepPurple),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          arrived
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: arrived
                              ? const Color(0xFF1D9E75)
                              : Colors.grey,
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;

  const _Tag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: color),
      ),
    );
  }
}
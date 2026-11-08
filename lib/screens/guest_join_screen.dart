import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'meeting_room_screen.dart';

class GuestJoinScreen extends StatefulWidget {
  const GuestJoinScreen({super.key});

  @override
  State<GuestJoinScreen> createState() => _GuestJoinScreenState();
}

class _GuestJoinScreenState extends State<GuestJoinScreen> {
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  final _db = FirebaseFirestore.instance;
  bool _isLoading = false;

  Future<void> _guestJoin() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이름을 입력해주세요')),
      );
      return;
    }
    if (_codeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('참여 코드를 입력해주세요')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final code = _codeController.text.trim().toUpperCase();
      final name = _nameController.text.trim();
      final guestId = 'guest_${DateTime.now().millisecondsSinceEpoch}';

      final query = await _db
          .collection('meetings')
          .where('code', isEqualTo: code)
          .get();

      if (query.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('존재하지 않는 코드입니다')),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      final meetingDoc = query.docs.first;

      await _db.collection('meetings').doc(meetingDoc.id).update({
        'members.$guestId': {
          'name': '$name (게스트)',
          'joinedAt': FieldValue.serverTimestamp(),
          'arrivedAt': FieldValue.serverTimestamp(),
          'drinkAlcohol': false,
          'eatFood': true,
          'isGuest': true,
        }
      });

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MeetingRoomScreen(
              meetingId: meetingDoc.id,
              meetingName: meetingDoc['name'],
              isHost: false,
              guestId: guestId,
              guestName: '$name (게스트)',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('참여 실패: $e')),
        );
      }
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('게스트 참여'),
        backgroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            // 안내 배너
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF3D7EFF).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF3D7EFF).withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFF3D7EFF), size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '게스트는 이름만 입력하고 바로 참여할 수 있어요.\n계좌 정보 없이 음식·술 체크만 가능해요.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF3D7EFF),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              '이름',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF444444),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                hintText: '이름 입력',
                prefixIcon: Icon(Icons.person_outline, size: 20),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '참여 코드',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF444444),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(
                hintText: '6자리 코드 입력',
                prefixIcon: Icon(Icons.vpn_key_outlined, size: 20),
              ),
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _guestJoin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3D7EFF),
                ),
                child: _isLoading
                    ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
                    : const Text('게스트로 참여하기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
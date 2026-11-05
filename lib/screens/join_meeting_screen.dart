import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fair_split/services/auth_service.dart';
import 'meeting_room_screen.dart';

class JoinMeetingScreen extends StatefulWidget {
  const JoinMeetingScreen({super.key});

  @override
  State<JoinMeetingScreen> createState() => _JoinMeetingScreenState();
}

class _JoinMeetingScreenState extends State<JoinMeetingScreen> {
  final _codeController = TextEditingController();
  final _authService = AuthService();
  final _db = FirebaseFirestore.instance;
  bool _isLoading = false;

  Future<void> _joinMeeting() async {
    if (_codeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('참여 코드를 입력해주세요')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = _authService.currentUser;
      final profile = await _authService.getUserProfile();
      final code = _codeController.text.trim().toUpperCase();

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
        'members.${user!.uid}': {
          'name': profile!['name'],
          'joinedAt': FieldValue.serverTimestamp(),
          'arrivedAt': FieldValue.serverTimestamp(),
          'drinkAlcohol': false,
          'eatFood': true,
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${meetingDoc['name']} 모임에 참여했습니다!')),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MeetingRoomScreen(
              meetingId: meetingDoc.id,
              meetingName: meetingDoc['name'],
              isHost: false,
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
        title: const Text('모임 참여'),
        backgroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
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
                hintText: '6자리 코드 입력 (예: ABC123)',
                prefixIcon: Icon(Icons.vpn_key_outlined, size: 20),
              ),
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _joinMeeting,
                child: _isLoading
                    ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
                    : const Text('참여하기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fair_split/services/auth_service.dart';

class MyPageScreen extends StatefulWidget {
  const MyPageScreen({super.key});

  @override
  State<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends State<MyPageScreen> {
  final _authService = AuthService();
  final _db = FirebaseFirestore.instance;
  final _nameController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _accountHolderController = TextEditingController();
  bool _isLoading = false;
  bool _isEditing = false;
  Map<String, dynamic>? _profile;

  String _selectedBank = 'KB국민은행';

  final List<String> _majorBanks = [
    'KB국민은행', '신한은행', '우리은행', '하나은행', 'NH농협은행',
    'IBK기업은행', '카카오뱅크', '토스뱅크', '케이뱅크', 'SC제일은행',
    'Sh수협은행', 'iM뱅크',
  ];

  final List<String> _otherBanks = [
    'BNK부산은행', 'BNK경남은행', '광주은행', '전북은행', '제주은행',
    '지역농·축협', '우체국', '새마을금고', '신협', '저축은행',
    '산림조합', 'KDB산업은행',
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    final profile = await _authService.getUserProfile();
    if (profile != null) {
      setState(() {
        _profile = profile;
        _nameController.text = profile['name'] ?? '';
        final accountRaw = profile['accountNumber'] ?? '';
        final parts = accountRaw.split('|');
        if (parts.length == 3) {
          _selectedBank = parts[0];
          _accountHolderController.text = parts[1];
          _accountNumberController.text = parts[2];
        } else {
          _accountNumberController.text = accountRaw;
        }
      });
    }
    setState(() => _isLoading = false);
  }

  Future<void> _saveProfile() async {
    setState(() => _isLoading = true);
    try {
      final uid = _authService.currentUser!.uid;
      await _db.collection('users').doc(uid).update({
        'name': _nameController.text.trim(),
        'accountNumber':
        '$_selectedBank|${_accountHolderController.text.trim()}|${_accountNumberController.text.trim()}',
      });
      setState(() => _isEditing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('프로필이 저장됐어요!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 실패: $e')),
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
        title: const Text('마이페이지'),
        backgroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: () {
              if (_isEditing) {
                _saveProfile();
              } else {
                setState(() => _isEditing = true);
              }
            },
            child: Text(
              _isEditing ? '저장' : '수정',
              style: const TextStyle(
                color: Color(0xFF1D9E75),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 프로필 아바타
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: const Color(0xFF1D9E75),
                    child: Text(
                      _profile?['name']?.toString().substring(0, 1) ?? '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _profile?['email'] ?? '',
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // 이름
            _SectionTitle(title: '이름'),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              enabled: _isEditing,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.person_outline, size: 20),
                hintText: '이름 입력',
              ),
            ),
            const SizedBox(height: 24),

            // 계좌 정보
            _SectionTitle(title: '계좌 정보'),
            const SizedBox(height: 8),

            // 은행 선택
            DropdownButtonFormField<String>(
              initialValue: _selectedBank,
              decoration: const InputDecoration(
                labelText: '은행',
              ),
              items: [
                const DropdownMenuItem(
                  enabled: false,
                  value: null,
                  child: Text('── 주요 은행 ──',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                ),
                ..._majorBanks.map((bank) => DropdownMenuItem(
                  value: bank,
                  child: Text(bank),
                )),
                const DropdownMenuItem(
                  enabled: false,
                  value: null,
                  child: Text('── 추가 은행 ──',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                ),
                ..._otherBanks.map((bank) => DropdownMenuItem(
                  value: bank,
                  child: Text(bank),
                )),
              ],
              onChanged: _isEditing
                  ? (value) {
                if (value != null) {
                  setState(() => _selectedBank = value);
                }
              }
                  : null,
            ),
            const SizedBox(height: 12),

            // 예금주
            TextField(
              controller: _accountHolderController,
              enabled: _isEditing,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.person_outline, size: 20),
                hintText: '예금주 이름',
                labelText: '예금주',
              ),
            ),
            const SizedBox(height: 12),

            // 계좌번호
            TextField(
              controller: _accountNumberController,
              enabled: _isEditing,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.account_balance, size: 20),
                hintText: '계좌번호 (- 없이)',
                labelText: '계좌번호',
              ),
            ),
            const SizedBox(height: 32),

            // 저장 버튼
            if (_isEditing)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveProfile,
                  child: const Text('저장하기'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Color(0xFF444444),
      ),
    );
  }
}
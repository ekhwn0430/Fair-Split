import 'package:flutter/material.dart';
import 'package:fair_split/services/auth_service.dart';
import 'home_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _accountHolderController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;

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

  Future<void> _signup() async {
    if (_nameController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty ||
        _accountHolderController.text.trim().isEmpty ||
        _accountNumberController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('모든 항목을 입력해주세요')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final accountInfo = '$_selectedBank $_accountHolderController.text ${_accountNumberController.text.trim()}';
      await _authService.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        name: _nameController.text.trim(),
        accountNumber: '$_selectedBank|${_accountHolderController.text.trim()}|${_accountNumberController.text.trim()}',
      );
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('회원가입 실패: $e')),
        );
      }
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('회원가입'),
        backgroundColor: const Color(0xFF1D9E75),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                // 이름
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: '이름',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                // 이메일
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: '이메일',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                // 비밀번호
                TextField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: '비밀번호',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 24),
                // 계좌 등록 섹션
                const Row(
                  children: [
                    Icon(Icons.account_balance, color: Color(0xFF1D9E75)),
                    SizedBox(width: 8),
                    Text(
                      '계좌 등록',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1D9E75),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 은행 선택
                DropdownButtonFormField<String>(
                  value: _selectedBank,
                  decoration: const InputDecoration(
                    labelText: '은행 선택',
                    border: OutlineInputBorder(),
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
                  onChanged: (value) {
                    if (value != null) setState(() => _selectedBank = value);
                  },
                ),
                const SizedBox(height: 16),
                // 예금주
                TextField(
                  controller: _accountHolderController,
                  decoration: const InputDecoration(
                    labelText: '예금주',
                    hintText: '예금주 이름',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                // 계좌번호
                TextField(
                  controller: _accountNumberController,
                  decoration: const InputDecoration(
                    labelText: '계좌번호',
                    hintText: '계좌번호 입력 (- 없이)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _signup,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1D9E75),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('회원가입', style: TextStyle(fontSize: 18)),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
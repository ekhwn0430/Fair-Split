import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/settlement_models.dart';
import '../services/gemini_receipt_service.dart';
import '../services/receipt_storage_service.dart';
import 'participant_input_screen.dart';
import 'receipt_edit_screen.dart';
import 'receipt_list_screen.dart';
import 'receipt_manual_entry_screen.dart';

/// 영수증 이미지를 선택해 Gemini로 분석을 요청하는 시작 화면.
class ReceiptUploadScreen extends StatefulWidget {
  const ReceiptUploadScreen({
    super.key,
    required this.service,
    required this.storage,
  });

  final GeminiReceiptService service;
  final ReceiptStorageService storage;

  @override
  State<ReceiptUploadScreen> createState() => _ReceiptUploadScreenState();
}

class _ReceiptUploadScreenState extends State<ReceiptUploadScreen> {
  final _picker = ImagePicker();
  bool _isAnalyzing = false;
  String? _errorMessage;

  Future<void> _pickAndAnalyze(ImageSource source) async {
    final picked = await _picker.pickImage(source: source);
    if (picked == null) return;

    if (!mounted) return;
    final consented = await _confirmSendToGemini();
    if (!mounted || consented != true) return;

    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
    });

    try {
      final bytes = await picked.readAsBytes();
      final mimeType = _mimeTypeFor(picked.name);
      final analysis = await widget.service.analyzeReceipt(
        bytes,
        mimeType: mimeType,
      );
      if (!mounted) return;
      final workingSet = await Navigator.of(context).push<ReceiptWorkingSet>(
        MaterialPageRoute(
          builder: (context) => ReceiptEditScreen(analysis: analysis),
        ),
      );

      if (workingSet == null) return;

      try {
        await widget.storage.save(
          imageBytes: bytes,
          mimeType: mimeType,
          analysis: toArchivedReceiptAnalysis(workingSet),
        );
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _errorMessage = error is ReceiptStorageException
              ? error.message
              : '영수증을 저장하지 못했습니다.';
        });
      }

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ParticipantInputScreen(workingSet: workingSet),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = describeAnalysisFailure(error));
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  /// 영수증 사진을 Gemini API로 보내기 전에 사용자 동의를 받는다.
  /// 취소하면 null/false를 돌려주고, API는 호출되지 않는다.
  Future<bool?> _confirmSendToGemini() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('영수증 이미지 전송 안내'),
        content: const Text(
          '영수증 분석을 위해 선택한 이미지가 Google Gemini 서비스로 전송됩니다. '
          '개인정보가 포함된 영수증은 확인 후 진행해 주세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('동의하고 분석'),
          ),
        ],
      ),
    );
  }

  Future<void> _manualEntry() async {
    final workingSet = await Navigator.of(context).push<ReceiptWorkingSet>(
      MaterialPageRoute(
        builder: (context) => const ReceiptManualEntryScreen(),
      ),
    );

    if (workingSet == null || !mounted) return;

    // 사진이 없는 직접 입력 영수증도 보관함에 저장한다(사진/MIME 타입 없이).
    try {
      await widget.storage.save(analysis: toArchivedReceiptAnalysis(workingSet));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error is ReceiptStorageException
            ? error.message
            : '영수증을 저장하지 못했습니다.';
      });
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ParticipantInputScreen(workingSet: workingSet),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('영수증 업로드'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: '저장된 영수증',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) =>
                      ReceiptListScreen(storage: widget.storage),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: _isAnalyzing
                      ? const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('영수증을 분석하는 중입니다...'),
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.receipt_long,
                              size: 96,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              '영수증 사진을 선택하면\n메뉴와 금액을 자동으로 인식합니다.',
                              textAlign: TextAlign.center,
                            ),
                            if (_errorMessage != null) ...[
                              const SizedBox(height: 16),
                              Text(
                                _errorMessage!,
                                style: TextStyle(color: theme.colorScheme.error),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ],
                        ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isAnalyzing
                          ? null
                          : () => _pickAndAnalyze(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera),
                      label: const Text('카메라'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isAnalyzing
                          ? null
                          : () => _pickAndAnalyze(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library),
                      label: const Text('갤러리'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isAnalyzing ? null : _manualEntry,
                  icon: const Icon(Icons.edit_note),
                  label: const Text('직접 입력'),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '영수증 텍스트 인식을 위해 이미지 데이터가 Google Gemini API로 전송됩니다.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _mimeTypeFor(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.heic')) return 'image/heic';
  return 'image/jpeg';
}

/// 영수증 분석 실패 시 화면에 보여줄 한국어 안내문을 만든다.
///
/// [GeminiReceiptService]가 이미 네트워크 오류·API 한도 초과·응답 파싱
/// 실패 등 종류별로 구체적인 한국어 메시지([ReceiptAnalysisException.message])를
/// 만들어 두므로, 그 메시지를 그대로 쓰고 재시도 방법만 덧붙인다. 그 외의
/// 예기치 못한 오류는 일반적인 안내로 대체한다.
String describeAnalysisFailure(Object error) {
  final reason = error is ReceiptAnalysisException
      ? error.message
      : '영수증을 분석하지 못했습니다.';
  return '$reason\n카메라 또는 갤러리 버튼으로 다시 시도해 주세요.';
}

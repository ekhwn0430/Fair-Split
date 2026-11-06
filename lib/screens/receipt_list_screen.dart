import 'package:flutter/material.dart';

import '../services/receipt_storage_service.dart';
import 'receipt_detail_screen.dart';

/// 앱 내부에 저장된 영수증 목록을 보여주는 화면.
class ReceiptListScreen extends StatefulWidget {
  const ReceiptListScreen({super.key, required this.storage});

  final ReceiptStorageService storage;

  @override
  State<ReceiptListScreen> createState() => _ReceiptListScreenState();
}

class _ReceiptListScreenState extends State<ReceiptListScreen> {
  late Future<List<StoredReceipt>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.storage.loadAll();
  }

  void _reload() {
    setState(() {
      _future = widget.storage.loadAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('저장된 영수증')),
      body: FutureBuilder<List<StoredReceipt>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            final error = snapshot.error;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  error is ReceiptStorageException
                      ? error.message
                      : '저장된 영수증을 불러오지 못했습니다.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final receipts = snapshot.data ?? [];

          if (receipts.isEmpty) {
            return const Center(child: Text('저장된 영수증이 없습니다.'));
          }

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: receipts.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final receipt = receipts[index];
                final analysis = receipt.analysis;

                final imageFile = receipt.imageFile;

                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: imageFile != null
                          ? Image.file(
                              imageFile,
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              width: 56,
                              height: 56,
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              child: Icon(
                                Icons.edit_note,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                    ),
                    title: Text('메뉴 ${analysis.items.length}건'),
                    subtitle: Text(_formatDateTime(receipt.savedAt)),
                    trailing: analysis.totalAmount != null
                        ? Text('${_formatWon(analysis.totalAmount!)}원')
                        : null,
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => ReceiptDetailScreen(
                            receipt: receipt,
                            storage: widget.storage,
                          ),
                        ),
                      );
                      _reload();
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

String _formatWon(int amount) =>
    amount.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');

String _formatDateTime(DateTime value) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)} '
      '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}

// Gemini API를 호출하지 않고 ReceiptStorageService만 단독으로 검증하는 테스트.
// path_provider가 실제 앱 문서 디렉터리를 쓰지 않도록 PathProviderPlatform.instance를
// 테스트용 임시 디렉터리를 가리키는 가짜 구현으로 교체한다. 그래서 이 테스트는
// 실제 앱의 영수증 데이터를 건드리지 않는다.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fair_split/services/gemini_receipt_service.dart';
import 'package:fair_split/services/receipt_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.documentsPath);

  final String documentsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

void main() {
  late Directory tempDir;
  late ReceiptStorageService storage;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('receipt_storage_test_');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final originalPlatform = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    addTearDown(() => PathProviderPlatform.instance = originalPlatform);

    storage = ReceiptStorageService();
  });

  test('영수증 사진과 수정된 분석 결과를 저장하고, 조회한 뒤, 삭제할 수 있다', () async {
    final analysis = ReceiptAnalysis(
      items: const [
        ReceiptItem(
          name: '소주',
          price: 4000,
          quantity: 1,
          category: ReceiptItemCategory.regularAlcohol,
        ),
        ReceiptItem(
          name: '삼겹살',
          price: 18000,
          quantity: 1,
          category: ReceiptItemCategory.food,
        ),
      ],
      paidAt: DateTime(2026, 11, 5, 20, 30),
      totalAmount: 22000,
    );

    final imageBytes = Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0xD9]);

    final id = await storage.save(
      imageBytes: imageBytes,
      mimeType: 'image/jpeg',
      analysis: analysis,
    );

    expect(id, isNotEmpty);

    // 실제 앱 문서 디렉터리가 아니라 테스트용 임시 디렉터리 밑에 저장됐는지 확인한다.
    final savedImageFile = File('${tempDir.path}/receipts/$id.jpg');
    final savedJsonFile = File('${tempDir.path}/receipts/$id.json');
    expect(savedImageFile.existsSync(), isTrue);
    expect(savedJsonFile.existsSync(), isTrue);
    expect(savedImageFile.readAsBytesSync(), imageBytes);

    final loaded = await storage.loadAll();
    expect(loaded, hasLength(1));

    final stored = loaded.single;
    expect(stored.id, id);
    expect(stored.imageFile?.path, savedImageFile.path);
    expect(stored.analysis.totalAmount, 22000);
    expect(stored.analysis.items, hasLength(2));
    expect(stored.analysis.items[0].name, '소주');
    expect(stored.analysis.items[1].name, '삼겹살');
    expect(stored.analysis.paidAt, DateTime(2026, 11, 5, 20, 30));

    await storage.delete(id);

    expect(savedImageFile.existsSync(), isFalse);
    expect(savedJsonFile.existsSync(), isFalse);
    expect(await storage.loadAll(), isEmpty);
  });

  test('원본 사진의 실제 이미지 형식(PNG/WebP)에 맞는 확장자로 저장된다', () async {
    const analysis = ReceiptAnalysis(
      items: [
        ReceiptItem(
          name: '커피',
          price: 4500,
          quantity: 1,
          category: ReceiptItemCategory.food,
        ),
      ],
    );

    final pngId = await storage.save(
      imageBytes: Uint8List.fromList(const [1, 2, 3]),
      mimeType: 'image/png',
      analysis: analysis,
    );
    expect(File('${tempDir.path}/receipts/$pngId.png').existsSync(), isTrue);

    // 같은 밀리초에 저장되어 id가 겹치지 않도록 약간의 시간차를 둔다.
    await Future<void>.delayed(const Duration(milliseconds: 5));

    final webpId = await storage.save(
      imageBytes: Uint8List.fromList(const [4, 5, 6]),
      mimeType: 'image/webp',
      analysis: analysis,
    );
    expect(File('${tempDir.path}/receipts/$webpId.webp').existsSync(), isTrue);

    final loaded = await storage.loadAll();
    expect(loaded, hasLength(2));
  });

  test('저장소에 아무 것도 없으면 빈 목록을 반환한다', () async {
    expect(await storage.loadAll(), isEmpty);
  });

  test('사진 없는 직접 입력 영수증도 저장하고 조회·삭제할 수 있다', () async {
    const analysis = ReceiptAnalysis(
      items: [
        ReceiptItem(
          name: '아메리카노',
          price: 4500,
          quantity: 2,
          category: ReceiptItemCategory.food,
        ),
      ],
      totalAmount: 9000,
    );

    final id = await storage.save(analysis: analysis);

    final savedJsonFile = File('${tempDir.path}/receipts/$id.json');
    expect(savedJsonFile.existsSync(), isTrue);
    // 사진 바이트를 전달하지 않았으므로 이미지 파일은 만들어지지 않는다.
    expect(
      Directory('${tempDir.path}/receipts')
          .listSync()
          .whereType<File>()
          .where((f) => !f.path.endsWith('.json')),
      isEmpty,
    );

    final loaded = await storage.loadAll();
    expect(loaded, hasLength(1));
    expect(loaded.single.imageFile, isNull);
    expect(loaded.single.analysis.totalAmount, 9000);

    await storage.delete(id);
    expect(savedJsonFile.existsSync(), isFalse);
    expect(await storage.loadAll(), isEmpty);
  });

  test('사진 있는 영수증과 사진 없는 영수증이 섞여 있어도 둘 다 정상적으로 불러와진다', () async {
    const photoAnalysis = ReceiptAnalysis(
      items: [
        ReceiptItem(
          name: '삼겹살',
          price: 18000,
          quantity: 1,
          category: ReceiptItemCategory.food,
        ),
      ],
    );
    const manualAnalysis = ReceiptAnalysis(
      items: [
        ReceiptItem(
          name: '아메리카노',
          price: 4500,
          quantity: 1,
          category: ReceiptItemCategory.food,
        ),
      ],
    );

    final photoId = await storage.save(
      imageBytes: Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0xD9]),
      mimeType: 'image/jpeg',
      analysis: photoAnalysis,
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final manualId = await storage.save(analysis: manualAnalysis);

    final loaded = await storage.loadAll();
    expect(loaded, hasLength(2));

    final photoReceipt = loaded.firstWhere((r) => r.id == photoId);
    final manualReceipt = loaded.firstWhere((r) => r.id == manualId);

    expect(photoReceipt.imageFile, isNotNull);
    expect(manualReceipt.imageFile, isNull);

    // 기존 Gemini(사진) 영수증의 조회·삭제 기능이 직접 입력 영수증 추가로
    // 망가지지 않았는지 확인한다.
    await storage.delete(photoId);
    final afterDelete = await storage.loadAll();
    expect(afterDelete, hasLength(1));
    expect(afterDelete.single.id, manualId);
  });

  test(
    '예전 버전처럼 imageExtension 키 자체가 없는 JSON도 "사진 없음"으로 안전하게 읽힌다',
    () async {
      final dir = Directory('${tempDir.path}/receipts');
      await dir.create(recursive: true);

      await File('${dir.path}/legacy1.json').writeAsString(
        jsonEncode({
          'savedAt': DateTime(2026, 1, 1).toIso8601String(),
          'analysis': {
            'items': [
              {
                'name': '소주',
                'price': 4000,
                'quantity': 1,
                'category': 'regular_alcohol',
              },
            ],
            'paidAt': null,
            'totalAmount': null,
          },
        }),
      );

      final loaded = await storage.loadAll();
      expect(loaded, hasLength(1));
      expect(loaded.single.imageFile, isNull);
      expect(loaded.single.analysis.items.single.name, '소주');
    },
  );
}

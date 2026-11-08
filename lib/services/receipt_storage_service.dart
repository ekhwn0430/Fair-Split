import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'gemini_receipt_service.dart';

/// 앱 내부 저장소에 보관된 영수증 한 건.
///
/// [imageFile]은 사진으로 분석한 영수증일 때만 있고, 직접 입력한 영수증은
/// 원본 사진이 없으므로 null이다.
class StoredReceipt {
  const StoredReceipt({
    required this.id,
    required this.analysis,
    required this.imageFile,
    required this.savedAt,
  });

  final String id;
  final ReceiptAnalysis analysis;
  final File? imageFile;
  final DateTime savedAt;
}

/// 영수증 저장/조회/삭제 실패 시 사용자에게 보여줄 안전한 오류.
class ReceiptStorageException implements Exception {
  const ReceiptStorageException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 영수증 원본 사진과 수정된 분석 결과를 앱 내부 저장소(문서 디렉터리)에
/// 저장, 조회, 삭제한다. Gemini API는 호출하지 않는다.
class ReceiptStorageService {
  static const _folderName = 'receipts';

  Future<Directory> _receiptsDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${docsDir.path}/$_folderName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _extensionFor(String mimeType) {
    switch (mimeType) {
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      case 'image/jpeg':
      default:
        return 'jpg';
    }
  }

  String _idOf(FileSystemEntity entity) {
    final fileName = entity.uri.pathSegments.last;
    final dotIndex = fileName.indexOf('.');
    return dotIndex == -1 ? fileName : fileName.substring(0, dotIndex);
  }

  /// 영수증 원본 사진과 수정된 분석 결과를 같은 ID로 묶어 저장한다.
  ///
  /// [imageBytes]와 [mimeType]을 생략하면(직접 입력한 영수증) 사진 없이
  /// 분석 결과만 저장한다.
  ///
  /// 성공하면 저장된 영수증의 id를 반환한다.
  /// 저장 중 하나라도 실패하면 [ReceiptStorageException]을 던지며,
  /// 저장에 성공한 것처럼 처리하지 않는다.
  Future<String> save({
    Uint8List? imageBytes,
    String? mimeType,
    required ReceiptAnalysis analysis,
  }) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();

    try {
      final dir = await _receiptsDir();
      final jsonFile = File('${dir.path}/$id.json');

      String? extension;
      if (imageBytes != null && mimeType != null) {
        extension = _extensionFor(mimeType);
        final imageFile = File('${dir.path}/$id.$extension');
        await imageFile.writeAsBytes(imageBytes, flush: true);
      }

      await jsonFile.writeAsString(
        jsonEncode({
          'savedAt': DateTime.now().toIso8601String(),
          'imageExtension': extension,
          'analysis': analysis.toJson(),
        }),
        flush: true,
      );

      return id;
    } catch (_) {
      throw const ReceiptStorageException(
        '영수증을 저장하지 못했습니다. 다시 시도해 주세요.',
      );
    }
  }

  /// 저장된 모든 영수증을 최근 저장 순으로 반환한다.
  Future<List<StoredReceipt>> loadAll() async {
    try {
      final dir = await _receiptsDir();
      final receipts = <StoredReceipt>[];

      for (final entity in dir.listSync()) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;

        final decoded = jsonDecode(await entity.readAsString());
        if (decoded is! Map<String, dynamic>) continue;

        final analysisJson = decoded['analysis'];
        if (analysisJson is! Map<String, dynamic>) continue;

        // 사진 없이 저장된(직접 입력) 영수증은 imageExtension이 null이다.
        final extension = decoded['imageExtension'];
        if (extension != null && extension is! String) continue;

        final id = _idOf(entity);

        File? imageFile;
        if (extension is String) {
          final candidate = File('${dir.path}/$id.$extension');
          if (!await candidate.exists()) continue;
          imageFile = candidate;
        }

        final savedAtRaw = decoded['savedAt'];
        final savedAt = savedAtRaw is String
            ? DateTime.tryParse(savedAtRaw) ?? DateTime.fromMillisecondsSinceEpoch(0)
            : DateTime.fromMillisecondsSinceEpoch(0);

        receipts.add(
          StoredReceipt(
            id: id,
            analysis: ReceiptAnalysis.fromJson(analysisJson),
            imageFile: imageFile,
            savedAt: savedAt,
          ),
        );
      }

      receipts.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      return receipts;
    } catch (_) {
      throw const ReceiptStorageException('저장된 영수증을 불러오지 못했습니다.');
    }
  }

  /// id로 저장된 영수증(사진 파일 + JSON 파일)을 모두 삭제한다.
  Future<void> delete(String id) async {
    try {
      final dir = await _receiptsDir();

      for (final entity in dir.listSync()) {
        if (entity is File && _idOf(entity) == id) {
          await entity.delete();
        }
      }
    } catch (_) {
      throw const ReceiptStorageException('영수증을 삭제하지 못했습니다.');
    }
  }
}

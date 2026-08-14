import 'dart:io';

import 'package:college_project_app/features/attendance/import/image/image_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const validator = ImageValidator();
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('image_validator_test');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<File> makeFile(String name, List<int> bytes) async {
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes);
    return file;
  }

  group('ImageValidator', () {
    test('accepts a JPEG', () async {
      final file = await makeFile('a.jpg', [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
      final result = await validator.validate(file.path);
      expect(result.isValid, isTrue);
    });

    test('accepts a PNG', () async {
      final file = await makeFile('a.png', [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      final result = await validator.validate(file.path);
      expect(result.isValid, isTrue);
    });

    test('accepts a WEBP', () async {
      final file = await makeFile(
        'a.webp',
        [0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50],
      );
      final result = await validator.validate(file.path);
      expect(result.isValid, isTrue);
    });

    test('rejects a plain text file', () async {
      final file = await makeFile('a.txt', [0x68, 0x65, 0x6C, 0x6C, 0x6F]);
      final result = await validator.validate(file.path);
      expect(result.isValid, isFalse);
      expect(result.reason, contains('Unsupported image format'));
    });

    test('rejects an empty file', () async {
      final file = await makeFile('empty.png', const []);
      final result = await validator.validate(file.path);
      expect(result.isValid, isFalse);
      expect(result.reason, contains('empty'));
    });

    test('rejects a missing file', () async {
      final result = await validator.validate('${dir.path}${Platform.pathSeparator}nope.png');
      expect(result.isValid, isFalse);
    });

    test('rejects a very large file', () async {
      final file = await makeFile('huge.jpg', [0xFF, 0xD8, 0xFF, 0xE0]);
      final raf = await file.open(mode: FileMode.append);
      await raf.setPosition(ImageValidator.maxFileBytes + 1);
      await raf.writeByte(0);
      await raf.close();
      final result = await validator.validate(file.path);
      expect(result.isValid, isFalse);
      expect(result.reason, contains('too large'));
    });
  });
}
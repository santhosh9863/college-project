import 'dart:io';

import 'package:college_project_app/features/attendance/import/image/image_pick_service.dart';
import 'package:college_project_app/features/attendance/import/import_controller.dart';
import 'package:college_project_app/features/attendance/import/ocr/ocr_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/linways_fixtures.dart';

class _FakeOcr implements OcrService {
  _FakeOcr(this.text, {this.error});

  final String text;
  final Object? error;
  bool disposed = false;
  String? lastPath;

  @override
  Future<String> recognizeImage(String imagePath) async {
    lastPath = imagePath;
    if (error != null) throw error!;
    return text;
  }

  @override
  void dispose() {
    disposed = true;
  }
}

class _FakePicker implements ImagePickService {
  _FakePicker(this.result);

  final String? result;

  @override
  Future<String?> pickGalleryImage() async => result;
}

class _ThrowingPicker implements ImagePickService {
  @override
  Future<String?> pickGalleryImage() async =>
      throw const FileSystemException('permission denied');
}

Future<Directory> _tempDir() => Directory.systemTemp.createTemp('import_test');

Future<File> _writeJpeg(Directory dir, String name) async {
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes([
    0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46,
    0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01,
  ]);
  return file;
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await _tempDir();
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  LinwaysImportController buildController({
    required _FakeOcr ocr,
    required ImagePickService picker,
  }) =>
      LinwaysImportController(ocr: ocr, picker: picker);

  group('LinwaysImportController', () {
    test('successful import reaches preview and deletes the temp image', () async {
      final image = await _writeJpeg(dir, 'ok.jpg');
      final ocr = _FakeOcr(LinwaysFixtures.overallAttendance);
      final controller = buildController(ocr: ocr, picker: _FakePicker(image.path));

      await controller.startImport();

      expect(controller.step, ImportStep.preview);
      expect(controller.snapshot, isNotNull);
      expect(controller.snapshot!.overall.percentage.value, 80.0);
      expect(ocr.lastPath, image.path);
      expect(await image.exists(), isFalse, reason: 'temp image must be cleaned up');
      controller.dispose();
    });

    test('cancelled picker stays idle without error', () async {
      final ocr = _FakeOcr(LinwaysFixtures.overallAttendance);
      final controller = buildController(ocr: ocr, picker: _FakePicker(null));

      await controller.startImport();

      expect(controller.step, ImportStep.idle);
      expect(controller.errorMessage, isNull);
      expect(controller.snapshot, isNull);
      controller.dispose();
    });

    test('invalid image reports the reason and never calls OCR', () async {
      final file = File('${dir.path}${Platform.pathSeparator}bad.txt');
      await file.writeAsString('not an image at all');
      final ocr = _FakeOcr(LinwaysFixtures.overallAttendance);
      final controller = buildController(ocr: ocr, picker: _FakePicker(file.path));

      await controller.startImport();

      expect(controller.step, ImportStep.error);
      expect(controller.errorMessage, contains('Unsupported image format'));
      expect(ocr.lastPath, isNull);
      controller.dispose();
    });

    test('OCR failure reports a clear error', () async {
      final image = await _writeJpeg(dir, 'fail.jpg');
      final ocr = _FakeOcr('', error: OcrException('boom'));
      final controller = buildController(ocr: ocr, picker: _FakePicker(image.path));

      await controller.startImport();

      expect(controller.step, ImportStep.error);
      expect(controller.errorMessage, contains('Try a clearer screenshot'));
      controller.dispose();
    });

    test('empty OCR text reports a clear error', () async {
      final image = await _writeJpeg(dir, 'empty.jpg');
      final ocr = _FakeOcr('   \n  ');
      final controller = buildController(ocr: ocr, picker: _FakePicker(image.path));

      await controller.startImport();

      expect(controller.step, ImportStep.error);
      expect(controller.errorMessage, contains('No text was found'));
      controller.dispose();
    });

    test('unsupported screenshot reports no-attendance error', () async {
      final image = await _writeJpeg(dir, 'photo.jpg');
      final ocr = _FakeOcr(LinwaysFixtures.unsupported);
      final controller = buildController(ocr: ocr, picker: _FakePicker(image.path));

      await controller.startImport();

      expect(controller.step, ImportStep.error);
      expect(controller.errorMessage, contains('No attendance data'));
      controller.dispose();
    });

    test('dispose closes the OCR service', () {
      final ocr = _FakeOcr('');
      final controller = buildController(ocr: ocr, picker: _FakePicker(null));
      controller.dispose();
      expect(ocr.disposed, isTrue);
    });

    test('permission denied from picker surfaces as an error', () async {
      final ocr = _FakeOcr('');
      final controller = LinwaysImportController(
        ocr: ocr,
        picker: _ThrowingPicker(),
      );
      await controller.startImport();
      expect(controller.step, ImportStep.error);
      expect(controller.errorMessage, contains('photo picker'));
      controller.dispose();
    });
  });
}

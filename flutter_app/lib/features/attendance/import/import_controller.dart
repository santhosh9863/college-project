import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../data/models/community.dart';
import '../../../data/models/profile.dart';
import 'image/image_pick_service.dart';
import 'image/image_validator.dart';
import 'models/parsed_linways_snapshot.dart';
import 'models/validation_issue.dart';
import 'ocr/ocr_service.dart';
import 'parser/linways_ocr_parser.dart';
import 'validator/snapshot_validator.dart';

/// Steps of the screenshot import flow.
enum ImportStep {
  /// Waiting for the user to choose an image.
  idle,

  /// Image picker open / selection being validated.
  picking,

  /// OCR + parsing in flight.
  processing,

  /// Parsed snapshot ready for review (preview step).
  preview,

  /// A problem was reported (cancelled picker stays [idle]).
  error,
}

/// State machine for the Linways screenshot import flow.
///
/// Privacy: the picked image lives in the picker's temporary cache and is
/// deleted as soon as processing finishes. The parsed snapshot exists only in
/// memory ([snapshot]) — never persisted, uploaded, or logged.
class LinwaysImportController extends ChangeNotifier {
  LinwaysImportController({
    required OcrService ocr,
    required ImagePickService picker,
    LinwaysOcrParser? parser,
    SnapshotValidator? validator,
    ImageValidator? imageValidator,
    Profile? profile,
    Community? community,
  })  : _ocr = ocr,
        _picker = picker,
        _parser = parser ?? const LinwaysOcrParser(),
        _validator = validator ?? const SnapshotValidator(),
        _imageValidator = imageValidator ?? const ImageValidator(),
        _profile = profile,
        _community = community;

  final OcrService _ocr;
  final ImagePickService _picker;
  final LinwaysOcrParser _parser;
  final SnapshotValidator _validator;
  final ImageValidator _imageValidator;
  final Profile? _profile;
  final Community? _community;

  ImportStep _step = ImportStep.idle;
  ParsedLinwaysSnapshot? _snapshot;
  List<ValidationIssue> _issues = const [];
  String? _errorMessage;
  String? _tempImagePath;

  ImportStep get step => _step;
  ParsedLinwaysSnapshot? get snapshot => _snapshot;
  List<ValidationIssue> get issues => _issues;
  String? get errorMessage => _errorMessage;

  bool get hasErrors => _issues.any((i) => i.severity == ValidationSeverity.error);
  bool get isProcessing =>
      _step == ImportStep.picking || _step == ImportStep.processing;

  /// Runs the flow: pick → validate image → OCR → parse → validate → preview.
  /// A cancelled picker leaves the controller [idle] with no error.
  Future<void> startImport() async {
    if (isProcessing) return;

    _step = ImportStep.picking;
    _errorMessage = null;
    _snapshot = null;
    _issues = const [];
    notifyListeners();

    final String? path;
    try {
      path = await _picker.pickGalleryImage();
    } catch (_) {
      _fail('The photo picker could not be opened. Please try again.');
      return;
    }
    if (path == null) {
      _step = ImportStep.idle;
      notifyListeners();
      return;
    }

    _tempImagePath = path;
    _step = ImportStep.processing;
    notifyListeners();

    try {
      final validation = await _imageValidator.validate(path);
      if (!validation.isValid) {
        _fail(validation.reason!);
        return;
      }

      final text = await _ocr.recognizeImage(path);
      if (text.trim().isEmpty) {
        _fail('No text was found in this image. Please choose a clear Linways screenshot.');
        return;
      }

      final snapshot = _parser.parse(text);
      final issues = _validator.validate(
        snapshot,
        profile: _profile,
        community: _community,
      );

      if (!snapshot.hasAnyAttendance) {
        _fail(
          'No attendance data was found in this image. '
          'Make sure it is a Linways attendance or profile screenshot.',
        );
        return;
      }

      _snapshot = snapshot;
      _issues = issues;
      _step = ImportStep.preview;
      notifyListeners();
    } on OcrException {
      _fail("Couldn't read the text in this image. Try a clearer screenshot.");
    } catch (_) {
      _fail('The image could not be processed. Please try another screenshot.');
    } finally {
      _deleteTempImage();
    }
  }

  /// The caller (import screen) reads [snapshot] and applies it after the
  /// user confirms the preview; this controller keeps no further state.
  void confirm() => notifyListeners();

  void _fail(String message) {
    _errorMessage = message;
    _snapshot = null;
    _issues = const [];
    _step = ImportStep.error;
    notifyListeners();
  }

  void _deleteTempImage() {
    final path = _tempImagePath;
    _tempImagePath = null;
    if (path == null) return;
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // Best-effort cleanup only; never throws into the flow.
    }
  }

  @override
  void dispose() {
    _deleteTempImage();
    _ocr.dispose();
    super.dispose();
  }
}
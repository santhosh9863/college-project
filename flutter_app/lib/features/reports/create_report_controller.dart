import 'package:flutter/foundation.dart';

import '../../data/models/community.dart';
import '../../data/models/profile.dart';
import 'data/categories_repository.dart';
import 'data/models/report_category.dart';
import 'data/reports_repository.dart';

/// One evidence file waiting to be uploaded with a report.
class EvidenceDraft {
  const EvidenceDraft({
    required this.path,
    required this.fileName,
    required this.contentType,
  });

  final String path;
  final String fileName;
  final String contentType;
}

/// Create-report form state and submission. The student chooses only
/// title/description/category/priority (+optional evidence); reporter,
/// community and department snapshots come from the authenticated state and
/// are validated by RLS server-side.
class CreateReportController extends ChangeNotifier {
  CreateReportController({
    required ReportsRepository repository,
    required CategoriesRepository categoriesRepository,
    this.profile,
    this.community,
  })  : _repository = repository,
        _categoriesRepository = categoriesRepository {
    _loadCategories();
  }

  final ReportsRepository _repository;
  final CategoriesRepository _categoriesRepository;

  /// Authenticated student profile (identity snapshots; never user input).
  final Profile? profile;

  /// Derived community from login (display + community snapshot; never
  /// user input).
  final Community? community;

  String _title = '';
  String _description = '';
  String? _categoryId;
  String? _priority;
  final List<EvidenceDraft> _evidence = [];
  bool _submitting = false;
  String? _error;
  Object? _lastSubmitError;
  int _failedEvidenceCount = 0;
  Object? _lastEvidenceError;
  bool _categoriesFailed = false;
  List<ReportCategory> _categories = const [];

  String get title => _title;
  String get description => _description;
  String? get categoryId => _categoryId;
  String? get priority => _priority;
  List<EvidenceDraft> get evidence => List.unmodifiable(_evidence);
  bool get submitting => _submitting;
  String? get error => _error;

  /// Underlying failure of the last submit attempt. Debug builds surface
  /// its message in the UI; release builds always show the friendly text.
  Object? get lastSubmitError => _lastSubmitError;

  /// Evidence files that failed to attach during the last submit. The report
  /// itself was still created, so this is a partial success, not a failure.
  int get failedEvidenceCount => _failedEvidenceCount;

  /// Underlying error of the first failed evidence upload (debug builds only).
  Object? get lastEvidenceError => _lastEvidenceError;

  bool get categoriesFailed => _categoriesFailed;
  List<ReportCategory> get categories => _categories;

  void setTitle(String value) {
    _title = value;
    notifyListeners();
  }

  void setDescription(String value) {
    _description = value;
    notifyListeners();
  }

  void setCategoryId(String? value) {
    _categoryId = value;
    notifyListeners();
  }

  void setPriority(String? value) {
    _priority = value;
    notifyListeners();
  }

  void addEvidence(EvidenceDraft draft) {
    _evidence.add(draft);
    notifyListeners();
  }

  void removeEvidenceAt(int index) {
    if (index < 0 || index >= _evidence.length) return;
    _evidence.removeAt(index);
    notifyListeners();
  }

  /// First unmet requirement, or null when the form is valid.
  String? get validationMessage {
    if (_title.trim().isEmpty) return 'Add a short title.';
    if (_description.trim().isEmpty) return 'Describe the problem.';
    if (_categoryId == null) return 'Choose a category.';
    if (_priority == null) return 'Choose a priority.';
    return null;
  }

  bool get canSubmit => validationMessage == null && !_submitting;

  /// Creates the report (pending, community type) and uploads any evidence.
  /// Returns the new report id, or null with [error] set on failure.
  ///
  /// Creating the report and attaching evidence are two independent steps. A
  /// failed attachment does not undo the report and is not reported as a
  /// failed submission: the id is still returned and the shortfall is exposed
  /// via [failedEvidenceCount] so the caller can tell the user.
  Future<String?> submit() async {
    if (!canSubmit) return null;
    _submitting = true;
    _error = null;
    _lastSubmitError = null;
    _failedEvidenceCount = 0;
    _lastEvidenceError = null;
    notifyListeners();

    final reportId = await _createReport();
    if (reportId != null) {
      await _uploadEvidence(reportId);
    }

    _submitting = false;
    notifyListeners();
    return reportId;
  }

  /// The create step only. Sets [error] and returns null when the report could
  /// not be created at all.
  Future<String?> _createReport() async {
    try {
      final communityId = await _repository.fetchMyCommunityId();
      if (communityId == null) {
        _error =
            'Your community has not been assigned yet. Reports can be created once the college assigns your community.';
        return null;
      }
      final departmentId = profile?.departmentId;
      if (departmentId == null || departmentId.isEmpty) {
        _error = 'Your profile is missing department information. Sign out and sign back in.';
        return null;
      }

      return await _repository.createReport(
        title: _title,
        description: _description,
        categoryId: _categoryId!,
        priority: _priority!,
        departmentId: departmentId,
        communityId: communityId,
        semester: profile?.semester,
        section: profile?.section,
      );
    } catch (error) {
      _lastSubmitError = error;
      debugPrint('CreateReportController: report creation failed: $error');
      _error = kDebugMode
          ? 'Could not create the report. Details (debug): $error'
          : 'Could not create the report. Please try again.';
      return null;
    }
  }

  /// The evidence step. Each file is attempted independently so one bad upload
  /// cannot discard the files that already succeeded.
  Future<void> _uploadEvidence(String reportId) async {
    for (final draft in _evidence) {
      try {
        await _repository.uploadEvidence(
          reportId: reportId,
          filePath: draft.path,
          contentType: draft.contentType,
        );
      } catch (error) {
        _failedEvidenceCount++;
        _lastEvidenceError ??= error;
        debugPrint('CreateReportController: evidence upload failed '
            '(${draft.fileName}): ${error.runtimeType}: $error');
      }
    }
  }

  Future<void> retryCategories() => _loadCategories();

  Future<void> _loadCategories() async {
    _categoriesFailed = false;
    try {
      _categories = await _categoriesRepository.fetchAll();
    } catch (_) {
      _categoriesFailed = true;
    }
    notifyListeners();
  }
}

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
  bool _categoriesFailed = false;
  List<ReportCategory> _categories = const [];

  String get title => _title;
  String get description => _description;
  String? get categoryId => _categoryId;
  String? get priority => _priority;
  List<EvidenceDraft> get evidence => List.unmodifiable(_evidence);
  bool get submitting => _submitting;
  String? get error => _error;
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
  Future<String?> submit() async {
    if (!canSubmit) return null;
    _submitting = true;
    _error = null;
    notifyListeners();
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

      final reportId = await _repository.createReport(
        title: _title,
        description: _description,
        categoryId: _categoryId!,
        priority: _priority!,
        departmentId: departmentId,
        communityId: communityId,
        semester: profile?.semester,
        section: profile?.section,
      );

      for (final draft in _evidence) {
        await _repository.uploadEvidence(
          reportId: reportId,
          filePath: draft.path,
          contentType: draft.contentType,
        );
      }
      return reportId;
    } catch (error) {
      _error = 'Could not create the report. Please try again.';
      return null;
    } finally {
      _submitting = false;
      notifyListeners();
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

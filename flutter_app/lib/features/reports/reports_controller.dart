import 'package:flutter/foundation.dart';

import '../../data/models/community.dart';
import '../../data/models/profile.dart';
import 'create_report_controller.dart';
import 'data/categories_repository.dart';
import 'data/models/report.dart';
import 'data/models/report_category.dart';
import 'data/reports_repository.dart';
import 'report_detail_controller.dart';

enum ReportsStatus { loading, ready, error }

/// Community reports feed state: RLS-scoped list plus status/category/priority
/// filters, title search and own-reports view.
class ReportsController extends ChangeNotifier {
  ReportsController({
    required ReportsRepository repository,
    required CategoriesRepository categoriesRepository,
  })  : _repository = repository,
        _categoriesRepository = categoriesRepository {
    load();
    _loadCategories();
  }

  final ReportsRepository _repository;
  final CategoriesRepository _categoriesRepository;

  ReportsStatus _status = ReportsStatus.loading;
  List<Report> _reports = const [];
  Object? _error;

  List<ReportCategory> _categories = const [];
  bool _categoriesFailed = false;

  String _statusFilter = 'all';
  String? _categoryId;
  String? _priority;
  String _search = '';
  bool _mineOnly = false;

  ReportsStatus get status => _status;
  List<Report> get reports => _reports;
  Object? get error => _error;

  List<ReportCategory> get categories => _categories;
  bool get categoriesFailed => _categoriesFailed;

  String get statusFilter => _statusFilter;
  String? get categoryId => _categoryId;
  String? get priority => _priority;
  String get search => _search;
  bool get mineOnly => _mineOnly;

  bool get hasActiveFilters =>
      _statusFilter != 'all' ||
      _categoryId != null ||
      _priority != null ||
      _search.trim().isNotEmpty ||
      _mineOnly;

  /// Controller for opening one report's detail screen.
  ReportDetailController detailControllerFor(String reportId) =>
      ReportDetailController(repository: _repository, reportId: reportId);

  /// Controller for the create-report screen. Identity snapshots come from
  /// the authenticated state, never from user input.
  CreateReportController createReportController({
    Profile? profile,
    Community? community,
  }) =>
      CreateReportController(
        repository: _repository,
        categoriesRepository: _categoriesRepository,
        profile: profile,
        community: community,
      );

  Future<void> load() async {
    _status = ReportsStatus.loading;
    _error = null;
    notifyListeners();
    try {
      _reports = await _repository.fetchFeed(
        statusFilter: _statusFilter,
        categoryId: _categoryId,
        priority: _priority,
        search: _search,
        mineOnly: _mineOnly,
      );
      _status = ReportsStatus.ready;
    } catch (error) {
      _error = error;
      _status = ReportsStatus.error;
    }
    notifyListeners();
  }

  void setStatusFilter(String value) {
    if (_statusFilter == value) return;
    _statusFilter = value;
    load();
  }

  void setCategoryFilter(String? value) {
    if (_categoryId == value) return;
    _categoryId = value;
    load();
  }

  void setPriorityFilter(String? value) {
    if (_priority == value) return;
    _priority = value;
    load();
  }

  void setSearch(String value) {
    if (_search == value) return;
    _search = value;
    load();
  }

  void setMineOnly(bool value) {
    if (_mineOnly == value) return;
    _mineOnly = value;
    load();
  }

  void clearFilters() {
    _statusFilter = 'all';
    _categoryId = null;
    _priority = null;
    _search = '';
    _mineOnly = false;
    load();
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

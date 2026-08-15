import 'package:flutter/foundation.dart';

import '../reports/data/models/report.dart';
import '../reports/data/reports_repository.dart';
import 'data/staff_reports_repository.dart';
import 'staff_detail_controller.dart';

enum StaffQueueStatus { loading, ready, error }

/// Staff queue state: the D1-scoped routed feed with status/search
/// filters. RLS returns exactly the queue; the client only renders it.
class StaffQueueController extends ChangeNotifier {
  StaffQueueController({
    required StaffReportsRepository repository,
    ReportsRepository? detailRepository,
    String role = '',
  })  : _repository = repository,
        _detailRepository = detailRepository,
        _role = role {
    load();
  }

  final StaffReportsRepository _repository;
  final ReportsRepository? _detailRepository;
  final String _role;

  StaffQueueStatus _status = StaffQueueStatus.loading;
  List<Report> _reports = const [];
  Object? _error;

  String _statusFilter = 'all';
  String _search = '';

  StaffQueueStatus get status => _status;
  List<Report> get reports => _reports;
  Object? get error => _error;
  String get statusFilter => _statusFilter;
  String get search => _search;

  bool get hasActiveFilters => _statusFilter != 'all' || _search.trim().isNotEmpty;

  /// Controller for opening one report's staff detail screen.
  StaffDetailController detailControllerFor(String reportId) =>
      StaffDetailController(
        repository: _detailRepository ?? ReportsRepository(),
        staffRepository: _repository,
        reportId: reportId,
        role: _role,
      );

  Future<void> load() async {
    _status = StaffQueueStatus.loading;
    _error = null;
    notifyListeners();
    try {
      _reports = await _repository.fetchQueue(
        statusFilter: _statusFilter,
        search: _search,
      );
      _status = StaffQueueStatus.ready;
    } catch (error) {
      _error = error;
      _status = StaffQueueStatus.error;
    }
    notifyListeners();
  }

  void setStatusFilter(String value) {
    if (_statusFilter == value) return;
    _statusFilter = value;
    load();
  }

  void setSearch(String value) {
    if (_search == value) return;
    _search = value;
    load();
  }

  void clearFilters() {
    _statusFilter = 'all';
    _search = '';
    load();
  }
}

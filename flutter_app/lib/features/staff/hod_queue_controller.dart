import 'package:flutter/foundation.dart';

import '../reports/data/models/report.dart';
import '../reports/data/reports_repository.dart';
import 'data/staff_reports_repository.dart';
import 'hod_detail_controller.dart';

enum HodQueueStatus { loading, ready, error }

/// HOD department queue state: the D1-scoped routed feed with status/search
/// filters. RLS returns exactly the queue; the client only renders it.
class HodQueueController extends ChangeNotifier {
  HodQueueController({
    required StaffReportsRepository repository,
    ReportsRepository? detailRepository,
  })  : _repository = repository,
        _detailRepository = detailRepository {
    load();
  }

  final StaffReportsRepository _repository;
  final ReportsRepository? _detailRepository;

  HodQueueStatus _status = HodQueueStatus.loading;
  List<Report> _reports = const [];
  Object? _error;

  String _statusFilter = 'all';
  String _search = '';

  HodQueueStatus get status => _status;
  List<Report> get reports => _reports;
  Object? get error => _error;
  String get statusFilter => _statusFilter;
  String get search => _search;

  bool get hasActiveFilters => _statusFilter != 'all' || _search.trim().isNotEmpty;

  /// Controller for opening one report's staff detail screen.
  HodDetailController detailControllerFor(String reportId) =>
      HodDetailController(
        repository: _detailRepository ?? ReportsRepository(),
        staffRepository: _repository,
        reportId: reportId,
      );

  Future<void> load() async {
    _status = HodQueueStatus.loading;
    _error = null;
    notifyListeners();
    try {
      _reports = await _repository.fetchQueue(
        statusFilter: _statusFilter,
        search: _search,
      );
      _status = HodQueueStatus.ready;
    } catch (error) {
      _error = error;
      _status = HodQueueStatus.error;
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

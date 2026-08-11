import 'package:flutter/foundation.dart';

import 'data/report.dart';
import 'data/reports_repository.dart';

enum ReportsStatus { loading, ready, error }

/// Community reports list state (read-only dashboard projection).
class ReportsController extends ChangeNotifier {
  ReportsController({required ReportsRepository repository})
      : _repository = repository {
    load();
  }

  final ReportsRepository _repository;

  ReportsStatus _status = ReportsStatus.loading;
  List<Report> _reports = const [];
  Object? _error;

  ReportsStatus get status => _status;
  List<Report> get reports => _reports;
  Object? get error => _error;

  Future<void> load() async {
    _status = ReportsStatus.loading;
    _error = null;
    notifyListeners();
    try {
      _reports = await _repository.fetchCommunityReports();
      _status = ReportsStatus.ready;
    } catch (error) {
      _error = error;
      _status = ReportsStatus.error;
    }
    notifyListeners();
  }
}

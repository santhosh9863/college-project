import 'package:flutter/foundation.dart';

import 'data/analytics_overview.dart';
import 'data/analytics_repository.dart';

enum AnalyticsStatus { loading, ready, error }

class AnalyticsController extends ChangeNotifier {
  AnalyticsController({required AnalyticsRepository repository})
      : _repository = repository;

  final AnalyticsRepository _repository;

  AnalyticsStatus _status = AnalyticsStatus.loading;
  AnalyticsOverview? _overview;
  String? _error;

  AnalyticsStatus get status => _status;
  AnalyticsOverview? get overview => _overview;
  String? get error => _error;

  Future<void> load() async {
    _status = AnalyticsStatus.loading;
    _overview = null;
    _error = null;
    notifyListeners();
    try {
      _overview = await _repository.fetchOverview();
      _status = AnalyticsStatus.ready;
    } catch (e) {
      _status = AnalyticsStatus.error;
      _error = e.toString();
    }
    notifyListeners();
  }
}
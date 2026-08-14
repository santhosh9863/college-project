import 'package:flutter/foundation.dart';

import '../../core/config/app_config.dart';
import 'data/attendance_summary.dart';
import 'data/linways_attendance_repository.dart';
import 'import/models/parsed_linways_snapshot.dart';

enum AttendanceStatus {
  /// First fetch in flight.
  loading,

  /// Fresh value shown (fetched within the cache TTL).
  ready,

  /// Showing the last known value because Linways was unreachable.
  stale,

  /// Nothing to show: fetch failed and no cached value exists.
  unavailable,
}

/// Dashboard attendance state with two conceptually distinct sources:
/// - **LIVE** — fetched from Linways via [LinwaysAttendanceRepository] with a
///   short in-memory TTL cache (unchanged behaviour).
/// - **IMPORT** — a screenshot-derived snapshot confirmed by the student
///   (memory only, never persisted).
class AttendanceController extends ChangeNotifier {
  AttendanceController({required LinwaysAttendanceRepository repository})
      : _repository = repository {
    load();
  }

  final LinwaysAttendanceRepository _repository;

  AttendanceStatus _status = AttendanceStatus.loading;
  AttendanceSummary? _summary;
  DateTime? _lastFetchedAt;
  bool _sessionExpired = false;
  ParsedLinwaysSnapshot? _importedSnapshot;

  AttendanceStatus get status => _status;
  AttendanceSummary? get summary => _summary;
  DateTime? get lastFetchedAt => _lastFetchedAt;
  bool get sessionExpired => _sessionExpired;

  /// Screenshot-derived attendance confirmed by the student (IMPORT source).
  ParsedLinwaysSnapshot? get importedSnapshot => _importedSnapshot;

  /// Applies a confirmed screenshot import. The student reviewed it first;
  /// live data is not overwritten, it stays available via [clearImported].
  void useImported(ParsedLinwaysSnapshot snapshot) {
    _importedSnapshot = snapshot;
    notifyListeners();
  }

  /// Switches back to the live Linways value.
  void clearImported() {
    _importedSnapshot = null;
    notifyListeners();
  }

  bool get _cacheIsFresh =>
      _lastFetchedAt != null &&
      DateTime.now().difference(_lastFetchedAt!) < AppConfig.attendanceCacheTtl;

  /// Shows the cached value when fresh; otherwise fetches.
  Future<void> load() async {
    if (_cacheIsFresh && _summary != null) {
      _status = AttendanceStatus.ready;
      _sessionExpired = false;
      notifyListeners();
      return;
    }
    await refresh();
  }

  /// Fetches from Linways regardless of cache age.
  Future<void> refresh() async {
    if (_status != AttendanceStatus.ready && _summary == null) {
      _status = AttendanceStatus.loading;
      notifyListeners();
    }

    try {
      final summary = await _repository.fetchSummary();
      _summary = summary;
      _lastFetchedAt = DateTime.now();
      _sessionExpired = false;
      _status = AttendanceStatus.ready;
    } on LinwaysAttendanceException catch (error) {
      if (error.kind == LinwaysAttendanceFailureKind.sessionExpired ||
          error.kind == LinwaysAttendanceFailureKind.noSession) {
        _sessionExpired = true;
      }
      // Keep showing the last known value when Linways is unreachable (hybrid
      // cache behaviour, LINWAYS_INTEGRATION_ARCHITECTURE.md §J).
      _status = _summary != null ? AttendanceStatus.stale : AttendanceStatus.unavailable;
    } catch (_) {
      _status = _summary != null ? AttendanceStatus.stale : AttendanceStatus.unavailable;
    }
    notifyListeners();
  }
}

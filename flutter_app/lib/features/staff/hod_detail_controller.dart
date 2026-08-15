import 'package:flutter/foundation.dart';

import '../reports/data/models/evidence_file.dart';
import '../reports/data/models/report.dart';
import '../reports/data/models/report_comment.dart';
import '../reports/data/models/report_detail.dart';
import '../reports/data/models/report_status.dart';
import '../reports/data/reports_repository.dart';
import 'data/staff_reports_repository.dart';

enum HodDetailStatus { loading, ready, error }

/// State for one report in the HOD queue: detail, comments, evidence, activity
/// timeline, and the lifecycle status actions permitted for HOD
/// (pending → under_review/in_progress/rejected, under_review →
/// in_progress/rejected, in_progress → resolved/rejected). The database
/// (`can_transition_status`) is the authority; the client only surfaces the
/// actions the HOD may legally take and reports server rejection.
class HodDetailController extends ChangeNotifier {
  HodDetailController({
    required ReportsRepository repository,
    required StaffReportsRepository staffRepository,
    required String reportId,
  })  : _repository = repository,
        _staffRepository = staffRepository,
        _reportId = reportId {
    load();
  }

  final ReportsRepository _repository;
  final StaffReportsRepository _staffRepository;
  final String _reportId;

  HodDetailStatus _status = HodDetailStatus.loading;
  ReportDetail? _detail;
  Object? _error;
  bool _commentInFlight = false;
  bool _statusInFlight = false;

  HodDetailStatus get status => _status;
  ReportDetail? get detail => _detail;
  Report? get report => _detail?.report;
  Object? get error => _error;
  bool get commentInFlight => _commentInFlight;
  bool get statusInFlight => _statusInFlight;

  bool get isAssigned => _detail?.activeAssigneeId != null;

  /// The status transitions the HOD may offer, per the approved lifecycle
  /// matrix (HOD row). `in_progress` requires an active assignment (D8).
  List<ReportStatus> get availableTransitions {
    final current = _detail?.report.status;
    final assigned = isAssigned;
    switch (current) {
      case ReportStatus.pending:
        return [
          ReportStatus.underReview,
          if (assigned) ReportStatus.inProgress,
          ReportStatus.rejected,
        ];
      case ReportStatus.underReview:
        return [
          if (assigned) ReportStatus.inProgress,
          ReportStatus.rejected,
        ];
      case ReportStatus.inProgress:
        return [ReportStatus.resolved, ReportStatus.rejected];
      default:
        return const [];
    }
  }

  /// Whether [target] is offered for the current report status.
  bool canTransitionTo(ReportStatus target) =>
      availableTransitions.contains(target);

  Future<void> load() async {
    _status = HodDetailStatus.loading;
    _error = null;
    notifyListeners();
    try {
      _detail = await _repository.fetchDetail(_reportId);
      _status = HodDetailStatus.ready;
    } catch (error) {
      _error = error;
      _status = HodDetailStatus.error;
    }
    notifyListeners();
  }

  /// Moves the report to [newStatus] (e.g. a review/accept move) and reloads
  /// the detail. Returns whether the database accepted the transition.
  Future<bool> changeStatus(ReportStatus newStatus) async {
    if (_statusInFlight || !canTransitionTo(newStatus)) return false;
    _statusInFlight = true;
    notifyListeners();
    try {
      final accepted =
          await _staffRepository.updateStatus(reportId: _reportId, newStatus: newStatus);
      if (accepted) {
        await load();
      }
      return accepted;
    } finally {
      _statusInFlight = false;
      notifyListeners();
    }
  }

  /// Reject with an optional reason: records the reason as a comment (so the
  /// rejection carries a note, per the lifecycle rules) before the transition.
  Future<bool> reject({String? reason}) async {
    final reasonText = reason?.trim();
    if (reasonText != null && reasonText.isNotEmpty) {
      try {
        await _repository.addComment(_reportId, reasonText);
      } catch (_) {
        // Comment failure does not block the rejection itself.
      }
    }
    return changeStatus(ReportStatus.rejected);
  }

  Future<void> addComment(String message) async {
    if (_commentInFlight || message.trim().isEmpty) return;
    _commentInFlight = true;
    notifyListeners();
    try {
      final comment = await _repository.addComment(_reportId, message);
      if (_detail != null) {
        _detail = _withComments([..._detail!.comments, comment]);
        notifyListeners();
      }
    } finally {
      _commentInFlight = false;
      notifyListeners();
    }
  }

  Future<EvidenceFile> uploadEvidence({
    required String filePath,
    required String contentType,
  }) async {
    final file = await _repository.uploadEvidence(
      reportId: _reportId,
      filePath: filePath,
      contentType: contentType,
    );
    if (_detail != null) {
      _detail = _withEvidence([..._detail!.evidence, file]);
      notifyListeners();
    }
    return file;
  }

  /// Short-lived signed URL for displaying one private evidence file.
  Future<String> signedUrlFor(EvidenceFile file) =>
      _repository.signedEvidenceUrl(file.fileUrl);

  ReportDetail _withComments(List<ReportComment> comments) => ReportDetail(
        report: _detail!.report,
        comments: comments,
        evidence: _detail!.evidence,
        activity: _detail!.activity,
        activeAssigneeId: _detail!.activeAssigneeId,
      );

  ReportDetail _withEvidence(List<EvidenceFile> evidence) => ReportDetail(
        report: _detail!.report,
        comments: _detail!.comments,
        evidence: evidence,
        activity: _detail!.activity,
        activeAssigneeId: _detail!.activeAssigneeId,
      );
}

import 'package:flutter/foundation.dart';

import '../reports/data/models/evidence_file.dart';
import '../reports/data/models/report.dart';
import '../reports/data/models/report_comment.dart';
import '../reports/data/models/report_detail.dart';
import '../reports/data/models/report_status.dart';
import '../reports/data/reports_repository.dart';
import 'data/assignable_staff.dart';
import 'data/staff_reports_repository.dart';

enum StaffDetailStatus { loading, ready, error }

/// State for one report in the staff queue: detail, comments, evidence,
/// activity timeline, and the lifecycle status actions permitted for the
/// role (pending -> under_review/in_progress/rejected, under_review ->
/// in_progress/rejected, in_progress -> resolved/rejected; operations/admin
/// additionally reopen resolved/rejected reports, D4/D5). The database
/// (`can_transition_status`, `can_manage_assignment`) is the authority; the
/// client only surfaces the actions the role may legally take and reports
/// server rejection.
class StaffDetailController extends ChangeNotifier {
  StaffDetailController({
    required ReportsRepository repository,
    required StaffReportsRepository staffRepository,
    required String reportId,
    String role = '',
  })  : _repository = repository,
        _staffRepository = staffRepository,
        _reportId = reportId,
        _role = role {
    load();
  }

  final ReportsRepository _repository;
  final StaffReportsRepository _staffRepository;
  final String _reportId;
  final String _role;

  StaffDetailStatus _status = StaffDetailStatus.loading;
  ReportDetail? _detail;
  Object? _error;
  bool _commentInFlight = false;
  bool _statusInFlight = false;
  bool _assignmentInFlight = false;
  List<AssignableStaff> _staffDirectory = const [];

  StaffDetailStatus get status => _status;
  ReportDetail? get detail => _detail;
  Report? get report => _detail?.report;
  Object? get error => _error;
  bool get commentInFlight => _commentInFlight;
  bool get statusInFlight => _statusInFlight;
  bool get assignmentInFlight => _assignmentInFlight;

  /// Whether the caller's role may manage assignments (D2: O/A only).
  bool get canManageAssignments =>
      _role == 'operations' || _role == 'admin';

  /// Whether the caller's role may reopen (D4/D5: O/A only).
  bool get canReopen => canManageAssignments;

  bool get isAssigned => _detail?.activeAssigneeId != null;

  /// Assignee display name resolved from the staff directory, when loaded.
  String? get assigneeName {
    final assigneeId = _detail?.activeAssigneeId;
    if (assigneeId == null) return null;
    for (final staff in _staffDirectory) {
      if (staff.id == assigneeId) return staff.fullName;
    }
    return null;
  }

  /// Staff directory for the assignment picker (loaded for ops/admin).
  List<AssignableStaff> get staffDirectory => _staffDirectory;

  /// The status transitions the caller may offer, per the approved lifecycle
  /// matrix. `in_progress` requires an active assignment (D8); reopen targets
  /// follow D4/D5 (ops/admin only, new assignment required for in_progress).
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
      case ReportStatus.resolved:
      case ReportStatus.rejected:
        // Reopen (D4/D5): ops/admin only AND a new active assignment is
        // required (D8) — resolve/reject deactivated the old one, so the
        // ops user assigns first, then the reopen actions appear.
        if (!canReopen || !assigned) return const [];
        return [
          ReportStatus.underReview,
          ReportStatus.inProgress,
        ];
      default:
        return const [];
    }
  }

  /// Whether [target] is offered for the current report status.
  bool canTransitionTo(ReportStatus target) =>
      availableTransitions.contains(target);

  Future<void> load() async {
    _status = StaffDetailStatus.loading;
    _error = null;
    notifyListeners();
    try {
      _detail = await _repository.fetchDetail(_reportId);
      if (canManageAssignments && _staffDirectory.isEmpty) {
        _staffDirectory = await _staffRepository.listAssignableStaff();
      }
      _status = StaffDetailStatus.ready;
    } catch (error) {
      _error = error;
      _status = StaffDetailStatus.error;
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

  /// Assigns [assigneeId] (push-only, D3; ops/admin only) and reloads the
  /// detail. Returns whether the database accepted the assignment.
  Future<bool> assignTo(String assigneeId) async {
    if (_assignmentInFlight || !canManageAssignments) return false;
    _assignmentInFlight = true;
    notifyListeners();
    try {
      final accepted =
          await _staffRepository.assign(reportId: _reportId, assigneeId: assigneeId);
      if (accepted) {
        await load();
      }
      return accepted;
    } finally {
      _assignmentInFlight = false;
      notifyListeners();
    }
  }

  /// Deactivates the current assignment (ops/admin only) and reloads.
  Future<bool> unassign() async {
    if (_assignmentInFlight || !canManageAssignments || !isAssigned) return false;
    _assignmentInFlight = true;
    notifyListeners();
    try {
      final accepted = await _staffRepository.unassign(reportId: _reportId);
      if (accepted) {
        await load();
      }
      return accepted;
    } finally {
      _assignmentInFlight = false;
      notifyListeners();
    }
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

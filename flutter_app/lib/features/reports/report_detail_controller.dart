import 'package:flutter/foundation.dart';

import 'data/models/evidence_file.dart';
import 'data/models/report.dart';
import 'data/models/report_comment.dart';
import 'data/models/report_detail.dart';
import 'data/reports_repository.dart';

enum ReportDetailStatus { loading, ready, error }

/// State for one report detail: report, comments, evidence, activity timeline,
/// support interaction, own-comment deletion and own-pending cancellation.
/// All writes go through the repository; the database (RLS + lifecycle) is the
/// authority.
class ReportDetailController extends ChangeNotifier {
  ReportDetailController({
    required ReportsRepository repository,
    required String reportId,
  })  : _repository = repository,
        _reportId = reportId {
    load();
  }

  final ReportsRepository _repository;
  final String _reportId;

  ReportDetailStatus _status = ReportDetailStatus.loading;
  ReportDetail? _detail;
  Object? _error;
  bool _supportInFlight = false;
  bool _commentInFlight = false;
  bool _cancelling = false;

  ReportDetailStatus get status => _status;
  ReportDetail? get detail => _detail;
  Report? get report => _detail?.report;
  Object? get error => _error;
  bool get supportInFlight => _supportInFlight;
  bool get commentInFlight => _commentInFlight;
  bool get cancelling => _cancelling;

  bool get isSupported => _detail?.report.isSupported ?? false;
  int get supportCount => _detail?.report.supportCount ?? 0;
  bool get isMine => _detail?.report.isMine ?? false;

  Future<void> load() async {
    _status = ReportDetailStatus.loading;
    _error = null;
    notifyListeners();
    try {
      _detail = await _repository.fetchDetail(_reportId);
      _status = ReportDetailStatus.ready;
    } catch (error) {
      _error = error;
      _status = ReportDetailStatus.error;
    }
    notifyListeners();
  }

  /// Optimistic support toggle; reverts on failure. The database policy
  /// (open report, own community, not own report) remains the enforcement.
  Future<void> toggleSupport() async {
    if (_supportInFlight || _detail == null) return;
    final current = _detail!;
    final wasSupported = current.report.isSupported;

    _supportInFlight = true;
    _detail = _withReport(
      current.report.copyWith(
        isSupported: !wasSupported,
        supportCount: (current.report.supportCount + (wasSupported ? -1 : 1))
            .clamp(0, 1 << 31),
      ),
    );
    notifyListeners();

    try {
      if (wasSupported) {
        await _repository.withdrawSupport(_reportId);
      } else {
        await _repository.addSupport(_reportId);
      }
    } catch (error) {
      _detail = current;
      rethrow;
    } finally {
      _supportInFlight = false;
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

  Future<void> deleteComment(String commentId) async {
    await _repository.deleteComment(commentId);
    if (_detail != null) {
      _detail = _withComments(
        _detail!.comments.where((c) => c.id != commentId).toList(),
      );
      notifyListeners();
    }
  }

  /// Cancels the caller's own pending report (soft delete). Returns whether
  /// the database accepted it.
  Future<bool> cancelReport() async {
    if (_cancelling) return false;
    _cancelling = true;
    notifyListeners();
    try {
      return await _repository.cancelReport(_reportId);
    } finally {
      _cancelling = false;
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

  ReportDetail _withReport(Report report) => ReportDetail(
        report: report,
        comments: _detail?.comments ?? const [],
        evidence: _detail?.evidence ?? const [],
        activity: _detail?.activity ?? const [],
        activeAssigneeId: _detail?.activeAssigneeId,
      );

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

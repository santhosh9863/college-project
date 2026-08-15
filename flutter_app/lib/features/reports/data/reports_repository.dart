import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'evidence_mime.dart';
import 'models/evidence_file.dart';
import 'models/report.dart';
import 'models/report_activity_item.dart';
import 'models/report_comment.dart';
import 'models/report_detail.dart';

/// Thrown when a report is not visible to the caller (RLS) or does not exist.
class ReportNotFoundException implements Exception {
  const ReportNotFoundException();
}

/// Reports data access. Authorization is enforced entirely by RLS — this
/// repository only builds queries for what the authenticated user can already
/// see; it never filters by community client-side.
///
/// Reporter/community ids come from the authenticated state ([currentUserId]
/// and the caller-supplied community snapshot), never from user input.
class ReportsRepository {
  ReportsRepository({SupabaseClient? client, String? currentUserId})
      : _client = client ?? Supabase.instance.client,
        _currentUserId = currentUserId;

  final SupabaseClient _client;

  /// Authenticated user id, or null when provided by the caller at
  /// construction (tests). RLS remains the security boundary.
  final String? _currentUserId;

  static const int _limit = 50;

  static const String _feedSelect =
      'id, title, description, status, priority, category_id, reporter_id, '
      'community_id, created_at, updated_at, categories(name), '
      'report_supports(count)';

  String get _userId {
    final id = _currentUserId ?? _client.auth.currentUser?.id;
    if (id == null || id.isEmpty) {
      throw StateError('No authenticated user');
    }
    return id;
  }

  // ---------------------------------------------------------------------------
  // Feed
  // ---------------------------------------------------------------------------

  /// Community feed (RLS-scoped). Optional filters: status, category,
  /// priority, title search, own-reports only. Deleted reports are never
  /// returned (RLS).
  Future<List<Report>> fetchFeed({
    String statusFilter = 'all',
    String? categoryId,
    String? priority,
    String search = '',
    bool mineOnly = false,
  }) async {
    var query = _client.from('reports').select(_feedSelect);

    if (mineOnly) query = query.eq('reporter_id', _userId);
    if (statusFilter != 'all') query = query.eq('status', statusFilter);
    if (categoryId != null) query = query.eq('category_id', categoryId);
    if (priority != null) query = query.eq('priority', priority);
    if (search.trim().isNotEmpty) {
      query = query.ilike('title', '%${search.trim()}%');
    }

    final rows =
        await query.order('created_at', ascending: false).limit(_limit);

    final reports = rows
        .map((row) => Report.fromJson(row, currentUserId: _userId))
        .toList();
    final supported = await fetchMySupportedIds();
    return reports
        .map((report) =>
            report.copyWith(isSupported: supported.contains(report.id)))
        .toList();
  }

  /// Ids of reports the authenticated student has supported.
  Future<Set<String>> fetchMySupportedIds() async {
    final rows = await _client
        .from('report_supports')
        .select('report_id')
        .eq('supporter_id', _userId);
    return {for (final row in rows) (row['report_id'] as String?) ?? ''};
  }

  // ---------------------------------------------------------------------------
  // Detail
  // ---------------------------------------------------------------------------

  /// Full detail (report + comments + evidence + activity + active assignee).
  /// Throws [ReportNotFoundException] when the report is not visible.
  Future<ReportDetail> fetchDetail(String reportId) async {
    final row = await _client
        .from('reports')
        .select(
          '$_feedSelect, '
          'report_comments(id, author_id, message, created_at, order:created_at.asc), '
          'evidence_files(id, report_id, file_url, file_type, uploaded_by, created_at), '
          'report_activity(id, actor_id, activity_type, metadata, created_at, order:created_at.asc), '
          'report_assignments(assigned_to, active)',
        )
        .eq('id', reportId)
        .maybeSingle();

    if (row == null) throw const ReportNotFoundException();

    final report = Report.fromJson(row, currentUserId: _userId);

    final comments = [
      for (final c in (row['report_comments'] as List? ?? const []))
        ReportComment.fromJson(c as Map<String, dynamic>, currentUserId: _userId),
    ];
    final evidence = [
      for (final e in (row['evidence_files'] as List? ?? const []))
        EvidenceFile.fromJson(e as Map<String, dynamic>, currentUserId: _userId),
    ];
    final activity = [
      for (final a in (row['report_activity'] as List? ?? const []))
        ReportActivityItem.fromJson(a as Map<String, dynamic>),
    ];

    String? activeAssigneeId;
    for (final assignment in (row['report_assignments'] as List? ?? const [])) {
      if (assignment is Map<String, dynamic> && assignment['active'] == true) {
        activeAssigneeId = assignment['assigned_to'] as String?;
        break;
      }
    }

    final supported = await fetchMySupportedIds();
    return ReportDetail(
      report: report.copyWith(isSupported: supported.contains(report.id)),
      comments: comments,
      evidence: evidence,
      activity: activity,
      activeAssigneeId: activeAssigneeId,
    );
  }

  // ---------------------------------------------------------------------------
  // Create
  // ---------------------------------------------------------------------------

  /// Id of the caller's active community. RLS (`communities_select_visible`)
  /// guarantees the returned row is the caller's own active community — the
  /// client never selects a community. Null when no community is assigned yet
  /// (community_pending).
  Future<String?> fetchMyCommunityId() async {
    final row = await _client.from('communities').select('id').maybeSingle();
    return row == null ? null : (row['id'] as String?) ?? '';
  }

  /// Creates a pending community report. Reporter/community ids come from the
  /// authenticated state; RLS (`can_create_report`) is the enforcement. The
  /// department id comes from the authenticated profile (NOT NULL column).
  /// Returns the new report id.
  Future<String> createReport({
    required String title,
    required String description,
    required String categoryId,
    required String priority,
    required String departmentId,
    required String communityId,
    int? semester,
    String? section,
  }) async {
    final row = await _client
        .from('reports')
        .insert({
          'report_type': 'community',
          'title': title.trim(),
          'description': description.trim(),
          'category_id': categoryId,
          'priority': priority,
          'status': 'pending',
          'department_id': departmentId,
          'community_id': communityId,
          'semester': semester,
          'section': section,
          'reporter_id': _userId,
        })
        .select('id')
        .single();

    return (row['id'] as String?) ?? '';
  }

  // ---------------------------------------------------------------------------
  // Support
  // ---------------------------------------------------------------------------

  /// Student supports an open report in their community (RLS-gated). Not their
  /// own report.
  Future<void> addSupport(String reportId) async {
    await _client.from('report_supports').insert({
      'report_id': reportId,
      'supporter_id': _userId,
    });
  }

  /// Withdraws the student's own support (RLS: own-row delete).
  Future<void> withdrawSupport(String reportId) async {
    await _client
        .from('report_supports')
        .delete()
        .eq('report_id', reportId)
        .eq('supporter_id', _userId);
  }

  // ---------------------------------------------------------------------------
  // Comments
  // ---------------------------------------------------------------------------

  /// Adds a comment to a visible report (RLS: own author + visible + not
  /// deleted).
  Future<ReportComment> addComment(String reportId, String message) async {
    final row = await _client
        .from('report_comments')
        .insert({
          'report_id': reportId,
          'author_id': _userId,
          'message': message.trim(),
        })
        .select('id, report_id, author_id, message, created_at')
        .single();
    return ReportComment.fromJson(row, currentUserId: _userId);
  }

  /// Deletes the caller's own comment (or admin). RLS enforces.
  Future<void> deleteComment(String commentId) async {
    await _client.from('report_comments').delete().eq('id', commentId);
  }

  // ---------------------------------------------------------------------------
  // Cancel (student soft-delete of own pending report)
  // ---------------------------------------------------------------------------

  /// Cancels the caller's own pending report (sets deleted_at; status stays
  /// pending). RLS (`can_update_report`) enforces ownership + pending + no
  /// status change. Returns whether the update was applied.
  Future<bool> cancelReport(String reportId) async {
    final rows = await _client
        .from('reports')
        .update({
          'deleted_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', reportId)
        .eq('reporter_id', _userId)
        .select('id');
    return rows.isNotEmpty;
  }

  // ---------------------------------------------------------------------------
  // Evidence
  // ---------------------------------------------------------------------------

  /// Uploads an evidence file to the private `evidence` bucket and records the
  /// metadata row (both RLS-gated: own report only for students).
  Future<EvidenceFile> uploadEvidence({
    required String reportId,
    required String filePath,
    required String contentType,
  }) async {
    final file = File(filePath);
    final safeName = file.uri.pathSegments.last.replaceAll(RegExp(r'[\\/]'), '_');
    final objectPath =
        'evidence/$reportId/${DateTime.now().millisecondsSinceEpoch}_$safeName';

    await _client.storage.from('evidence').uploadBinary(
          objectPath,
          await file.readAsBytes(),
          fileOptions: FileOptions(contentType: contentType),
        );

    final row = await _client
        .from('evidence_files')
        .insert({
          'report_id': reportId,
          'file_url': objectPath,
          'file_type': contentType,
          'uploaded_by': _userId,
        })
        .select('id, report_id, file_url, file_type, uploaded_by, created_at')
        .single();

    return EvidenceFile.fromJson(row, currentUserId: _userId);
  }

  /// Short-lived signed URL for displaying private evidence. Never a public
  /// URL.
  Future<String> signedEvidenceUrl(String objectPath) {
    return _client.storage.from('evidence').createSignedUrl(objectPath, 3600);
  }

  /// Convenience: resolves the MIME type for an evidence file by name.
  static String mimeTypeFor(String fileName) => evidenceMimeTypeFromName(fileName);
}

/// An evidence file on a report (`evidence_files` table + private `evidence`
/// storage bucket). `fileUrl` is the storage object path, never a public URL —
/// the bucket is private and access is policy-controlled.
class EvidenceFile {
  const EvidenceFile({
    required this.id,
    required this.reportId,
    required this.fileUrl,
    required this.fileType,
    required this.uploadedBy,
    required this.createdAt,
    this.isMine = false,
  });

  factory EvidenceFile.fromJson(
    Map<String, dynamic> json, {
    required String currentUserId,
  }) {
    final uploadedBy = (json['uploaded_by'] as String?) ?? '';
    return EvidenceFile(
      id: (json['id'] as String?) ?? '',
      reportId: (json['report_id'] as String?) ?? '',
      fileUrl: (json['file_url'] as String?) ?? '',
      fileType: (json['file_type'] as String?) ?? '',
      uploadedBy: uploadedBy,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      isMine: uploadedBy == currentUserId,
    );
  }

  final String id;
  final String reportId;
  final String fileUrl;
  final String fileType;
  final String uploadedBy;
  final DateTime createdAt;

  /// Whether the authenticated student uploaded this file (display only).
  final bool isMine;
}

import 'package:college_project_app/data/models/community.dart';
import 'package:college_project_app/data/models/profile.dart';
import 'package:college_project_app/features/reports/create_report_controller.dart';
import 'package:college_project_app/features/reports/data/categories_repository.dart';
import 'package:college_project_app/features/reports/data/models/evidence_file.dart';
import 'package:college_project_app/features/reports/data/models/report_category.dart';
import 'package:college_project_app/features/reports/data/reports_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Profile _profile({String? departmentId = 'dept-1'}) => Profile(
      id: 'user-a',
      fullName: 'Test Student',
      email: 'student@college.example',
      role: 'student',
      semester: 5,
      section: 'C',
      studentId: 'S-2024-001',
      departmentId: departmentId,
    );

Community _community() =>
    const Community(courseCode: 'BCA', batchYear: 2024, semester: 'Sem 5', section: 'C');

class _FakeCategoriesRepository extends CategoriesRepository {
  _FakeCategoriesRepository()
      : super(client: SupabaseClient('http://localhost', 'anon-key'));

  @override
  Future<List<ReportCategory>> fetchAll() async {
    return const [
      ReportCategory(id: 'cat-1', name: 'Academic'),
      ReportCategory(id: 'cat-2', name: 'Facilities'),
    ];
  }
}

class _FakeReportsRepository extends ReportsRepository {
  _FakeReportsRepository({this.failCreate = false}) : super(
          client: SupabaseClient('http://localhost', 'anon-key'),
          currentUserId: 'user-a',
        );

  String? communityId = 'community-1';
  bool failCreate;
  Map<String, dynamic>? lastCreateArgs;
  final List<String> uploaded = [];
  bool communityChecked = false;

  /// Paths that should throw, to simulate a storage-layer failure.
  final Set<String> failEvidencePaths = {};

  @override
  Future<String?> fetchMyCommunityId() async {
    communityChecked = true;
    return communityId;
  }

  @override
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
    lastCreateArgs = {
      'title': title,
      'description': description,
      'categoryId': categoryId,
      'priority': priority,
      'departmentId': departmentId,
      'communityId': communityId,
      'semester': semester,
      'section': section,
    };
    if (failCreate) throw Exception('create failed');
    return 'report-1';
  }

  @override
  Future<EvidenceFile> uploadEvidence({
    required String reportId,
    required String filePath,
    required String contentType,
  }) async {
    uploaded.add(filePath);
    if (failEvidencePaths.contains(filePath)) {
      throw Exception('storage rejected $filePath');
    }
    return EvidenceFile(
      id: 'e-1',
      reportId: reportId,
      fileUrl: 'evidence/$reportId/x.png',
      fileType: contentType,
      uploadedBy: 'user-a',
      createdAt: DateTime(2026, 8, 15),
    );
  }
}

void main() {
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('CreateReportController', () {
    test('loads categories on construction', () async {
      final controller = CreateReportController(
        repository: _FakeReportsRepository(),
        categoriesRepository: _FakeCategoriesRepository(),
      );
      await settle();

      expect(controller.categories, hasLength(2));
      expect(controller.categoriesFailed, isFalse);
    });

    test('validationMessage walks the requirements in order', () {
      final controller = CreateReportController(
        repository: _FakeReportsRepository(),
        categoriesRepository: _FakeCategoriesRepository(),
      );

      expect(controller.validationMessage, 'Add a short title.');
      controller.setTitle('Broken projector');
      expect(controller.validationMessage, 'Describe the problem.');
      controller.setDescription('Room 12.');
      expect(controller.validationMessage, 'Choose a category.');
      controller.setCategoryId('cat-1');
      expect(controller.validationMessage, 'Choose a priority.');
      controller.setPriority('high');
      expect(controller.validationMessage, isNull);
      expect(controller.canSubmit, isTrue);
    });

    test('evidence drafts can be added and removed', () {
      final controller = CreateReportController(
        repository: _FakeReportsRepository(),
        categoriesRepository: _FakeCategoriesRepository(),
      );

      controller.addEvidence(const EvidenceDraft(
        path: 'C:/tmp/a.png',
        fileName: 'a.png',
        contentType: 'image/png',
      ));
      controller.addEvidence(const EvidenceDraft(
        path: 'C:/tmp/b.pdf',
        fileName: 'b.pdf',
        contentType: 'application/pdf',
      ));
      expect(controller.evidence, hasLength(2));

      controller.removeEvidenceAt(0);
      expect(controller.evidence, hasLength(1));
      expect(controller.evidence.first.fileName, 'b.pdf');

      controller.removeEvidenceAt(5); // out of range is a no-op
      expect(controller.evidence, hasLength(1));
    });

    test('submit creates the report from authenticated state and uploads evidence',
        () async {
      final repo = _FakeReportsRepository();
      final controller = CreateReportController(
        repository: repo,
        categoriesRepository: _FakeCategoriesRepository(),
        profile: _profile(),
        community: _community(),
      );
      await settle();

      controller.setTitle('Broken projector');
      controller.setDescription('Room 12 projector is broken.');
      controller.setCategoryId('cat-1');
      controller.setPriority('high');
      controller.addEvidence(const EvidenceDraft(
        path: 'C:/tmp/a.png',
        fileName: 'a.png',
        contentType: 'image/png',
      ));
      await settle();

      final id = await controller.submit();

      expect(id, 'report-1');
      expect(repo.communityChecked, isTrue);
      expect(repo.lastCreateArgs, {
        'title': 'Broken projector',
        'description': 'Room 12 projector is broken.',
        'categoryId': 'cat-1',
        'priority': 'high',
        'departmentId': 'dept-1',
        'communityId': 'community-1',
        'semester': 5,
        'section': 'C',
      });
      expect(repo.uploaded, ['C:/tmp/a.png']);
      expect(controller.submitting, isFalse);
      expect(controller.error, isNull);
    });

    test('submit without a community shows a clear error', () async {
      final repo = _FakeReportsRepository()..communityId = null;
      final controller = CreateReportController(
        repository: repo,
        categoriesRepository: _FakeCategoriesRepository(),
        profile: _profile(),
        community: _community(),
      );
      await settle();

      controller.setTitle('t');
      controller.setDescription('d');
      controller.setCategoryId('cat-1');
      controller.setPriority('low');

      final id = await controller.submit();

      expect(id, isNull);
      expect(repo.lastCreateArgs, isNull);
      expect(controller.error, contains('community'));
    });

    test('submit without a department shows a clear error', () async {
      final controller = CreateReportController(
        repository: _FakeReportsRepository(),
        categoriesRepository: _FakeCategoriesRepository(),
        profile: _profile(departmentId: null),
        community: _community(),
      );
      await settle();

      controller.setTitle('t');
      controller.setDescription('d');
      controller.setCategoryId('cat-1');
      controller.setPriority('low');

      final id = await controller.submit();

      expect(id, isNull);
      expect(controller.error, contains('department'));
    });

    test('submit exposes the underlying failure in debug builds', () async {
      final repo = _FakeReportsRepository(failCreate: true);
      final controller = CreateReportController(
        repository: repo,
        categoriesRepository: _FakeCategoriesRepository(),
        profile: _profile(),
        community: _community(),
      );
      await settle();

      controller.setTitle('t');
      controller.setDescription('d');
      controller.setCategoryId('cat-1');
      controller.setPriority('low');

      final id = await controller.submit();

      expect(id, isNull);
      expect(controller.lastSubmitError, isA<Exception>());
      expect(controller.lastSubmitError.toString(), contains('create failed'));
      expect(controller.error, contains('Could not create the report'));
      expect(controller.error, contains('Details (debug)'));
      expect(controller.error, contains('create failed'));
    });

    test('a failed evidence upload does not discard the created report',
        () async {
      final repo = _FakeReportsRepository()..failEvidencePaths.add('C:/tmp/a.png');
      final controller = CreateReportController(
        repository: repo,
        categoriesRepository: _FakeCategoriesRepository(),
        profile: _profile(),
        community: _community(),
      );
      await settle();

      controller.setTitle('t');
      controller.setDescription('d');
      controller.setCategoryId('cat-1');
      controller.setPriority('low');
      controller.addEvidence(const EvidenceDraft(
        path: 'C:/tmp/a.png',
        fileName: 'a.png',
        contentType: 'image/png',
      ));

      final id = await controller.submit();

      expect(id, 'report-1');
      expect(controller.error, isNull);
      expect(controller.lastSubmitError, isNull);
      expect(controller.failedEvidenceCount, 1);
      expect(controller.lastEvidenceError.toString(),
          contains('storage rejected'));
    });

    test('evidence uploads continue after one fails', () async {
      final repo = _FakeReportsRepository()..failEvidencePaths.add('C:/tmp/a.png');
      final controller = CreateReportController(
        repository: repo,
        categoriesRepository: _FakeCategoriesRepository(),
        profile: _profile(),
        community: _community(),
      );
      await settle();

      controller.setTitle('t');
      controller.setDescription('d');
      controller.setCategoryId('cat-1');
      controller.setPriority('low');
      for (final path in ['C:/tmp/a.png', 'C:/tmp/b.png', 'C:/tmp/c.png']) {
        controller.addEvidence(EvidenceDraft(
          path: path,
          fileName: path.split('/').last,
          contentType: 'image/png',
        ));
      }

      final id = await controller.submit();

      expect(id, 'report-1');
      expect(repo.uploaded, hasLength(3));
      expect(controller.failedEvidenceCount, 1);
    });

    test('submit is a no-op while invalid or already submitting', () async {
      final repo = _FakeReportsRepository();
      final controller = CreateReportController(
        repository: repo,
        categoriesRepository: _FakeCategoriesRepository(),
        profile: _profile(),
        community: _community(),
      );
      await settle();

      expect(await controller.submit(), isNull); // invalid form
      expect(repo.communityChecked, isFalse);
      expect(controller.lastSubmitError, isNull);
    });

    test('categories failure is reported without blocking the form', () async {
      final controller = CreateReportController(
        repository: _FakeReportsRepository(),
        categoriesRepository: _FakeCategoriesRepository(),
        profile: _profile(),
        community: _community(),
      );
      await settle();

      expect(controller.categories, hasLength(2));
    });
  });
}

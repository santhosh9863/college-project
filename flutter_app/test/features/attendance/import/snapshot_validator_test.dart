import 'package:college_project_app/data/models/community.dart';
import 'package:college_project_app/data/models/profile.dart';
import 'package:college_project_app/features/attendance/import/models/validation_issue.dart';
import 'package:college_project_app/features/attendance/import/parser/linways_ocr_parser.dart';
import 'package:college_project_app/features/attendance/import/validator/snapshot_validator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/linways_fixtures.dart';

const _parser = LinwaysOcrParser();
const _validator = SnapshotValidator();

const _registeredProfile = Profile(
  id: 'u1',
  fullName: 'Santhosh Kumar',
  email: '9538111909@college-project.local',
  role: 'student',
  semester: 5,
  section: 'C',
  studentId: '9538111909',
);

const _registeredCommunity = Community(
  courseCode: 'BCA',
  batchYear: 2024,
  semester: 'S5',
  section: 'C',
);

List<ValidationIssue> _validate(String fixture, {Profile? profile, Community? community}) =>
    _validator.validate(
      _parser.parse(fixture),
      profile: profile ?? _registeredProfile,
      community: community ?? _registeredCommunity,
    );

bool _hasCode(List<ValidationIssue> issues, String code) =>
    issues.any((issue) => issue.code == code);

void main() {
  group('SnapshotValidator', () {
    test('valid overall snapshot produces no errors', () {
      final issues = _validate(LinwaysFixtures.overallAttendance);
      expect(issues.where((i) => i.severity == ValidationSeverity.error), isEmpty);
      expect(_hasCode(issues, 'percentageMismatch'), isFalse);
      expect(_hasCode(issues, 'absentMismatch'), isFalse);
    });

    test('absent conflict is a warning, never an error', () {
      final issues = _validate(LinwaysFixtures.overallAbsentConflict);
      expect(
        issues.any((i) =>
            i.code == 'absentMismatch' && i.severity == ValidationSeverity.warning),
        isTrue,
      );
    });

    test('percentage mismatch is a warning, never an error', () {
      final issues = _validate(LinwaysFixtures.overallPercentageConflict);
      expect(
        issues.any((i) =>
            i.code == 'percentageMismatch' && i.severity == ValidationSeverity.warning),
        isTrue,
      );
    });

    test('attended > conducted is an ERROR', () {
      final snapshot = _parser.parse(LinwaysFixtures.subjectWiseInvalidCounts);
      final issues = _validator.validate(snapshot);
      expect(
        issues.any((i) =>
            i.code == 'invalidCounts' && i.severity == ValidationSeverity.error),
        isTrue,
      );
    });

    test('invalid overall percentage is an ERROR', () {
      final snapshot = _parser.parse('''
Attendance Summary
Attendance Percentage: 125.0 %
''');
      final issues = _validator.validate(snapshot);
      expect(
        issues.any((i) =>
            i.code == 'invalidPercentage' && i.severity == ValidationSeverity.error),
        isTrue,
      );
    });

    test('section mismatch with registered profile is a warning', () {
      final issues = _validate(LinwaysFixtures.identityMismatchSection);
      expect(
        issues.any((i) =>
            i.code == 'identitySectionMismatch' &&
            i.severity == ValidationSeverity.warning),
        isTrue,
      );
    });

    test('matching identity produces no identity warnings', () {
      final issues = _validate(LinwaysFixtures.overallAttendance);
      expect(
        issues.where((i) => i.code.startsWith('identity')).toList(),
        isEmpty,
      );
    });

    test('semester mismatch is a warning', () {
      final issues = _validate('''
Attendance Summary
Semester: S6
Section: C
Classes Conducted: 40
Classes Attended: 32
Attendance Percentage: 80.00 %
''');
      expect(_hasCode(issues, 'identitySemesterMismatch'), isTrue);
    });

    test('department mismatch is a warning', () {
      final issues = _validate('''
Attendance Summary
Department: BBA
Classes Conducted: 40
Classes Attended: 32
Attendance Percentage: 80.00 %
''');
      expect(_hasCode(issues, 'identityDepartmentMismatch'), isTrue);
    });

    test('missing subject code is INFO, never a blocker', () {
      final issues = _validate(LinwaysFixtures.subjectWiseNoHeader);
      expect(
        issues.any((i) =>
            i.code == 'subjectCodeMissing' && i.severity == ValidationSeverity.info),
        isTrue,
      );
    });

    test('unsupported screenshot yields no-attendance ERROR', () {
      final issues = _validate(LinwaysFixtures.unsupported);
      expect(
        issues.any((i) =>
            i.code == 'noAttendanceData' && i.severity == ValidationSeverity.error),
        isTrue,
      );
    });

    test('issues are sorted errors first', () {
      final issues = _validate(LinwaysFixtures.identityMismatchSection);
      var sawNonError = false;
      for (final issue in issues) {
        if (issue.severity != ValidationSeverity.error) sawNonError = true;
        if (sawNonError) {
          expect(issue.severity, isNot(ValidationSeverity.error));
        }
      }
    });
  });
}
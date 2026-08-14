import 'package:college_project_app/features/attendance/import/models/parsed_linways_snapshot.dart';
import 'package:college_project_app/features/attendance/import/models/provenance.dart';
import 'package:college_project_app/features/attendance/import/models/validation_issue.dart';
import 'package:college_project_app/features/attendance/import/parser/linways_ocr_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/linways_fixtures.dart';

void main() {
  const parser = LinwaysOcrParser();

  group('LinwaysOcrParser', () {
    group('screen detection', () {
      test('detects overall attendance screen', () {
        final snapshot = parser.parse(LinwaysFixtures.overallAttendance);
        expect(snapshot.source.screenType, LinwaysScreenType.overallAttendance);
        expect(snapshot.source.screenConfidence, greaterThan(0.5));
      });

      test('detects subject-wise attendance screen', () {
        final snapshot = parser.parse(LinwaysFixtures.subjectWise);
        expect(snapshot.source.screenType, LinwaysScreenType.subjectWiseAttendance);
      });

      test('detects subject-wise screen without header', () {
        final snapshot = parser.parse(LinwaysFixtures.subjectWiseNoHeader);
        expect(snapshot.source.screenType, LinwaysScreenType.subjectWiseAttendance);
      });

      test('detects student profile screen', () {
        final snapshot = parser.parse(LinwaysFixtures.studentProfile);
        expect(snapshot.source.screenType, LinwaysScreenType.studentProfile);
      });

      test('unsupported text yields unknown type and reports it', () {
        final snapshot = parser.parse(LinwaysFixtures.unsupported);
        expect(snapshot.source.screenType, LinwaysScreenType.unknown);
        expect(
          snapshot.warnings.any((w) => w.code == 'screenTypeUncertain'),
          isTrue,
        );
      });

      test('empty OCR yields unknown type and no attendance', () {
        final snapshot = parser.parse(LinwaysFixtures.empty);
        expect(snapshot.source.screenType, LinwaysScreenType.unknown);
        expect(snapshot.hasAnyAttendance, isFalse);
        expect(
          snapshot.warnings.any((w) => w.code == 'noAttendanceData'),
          isTrue,
        );
      });
    });

    group('overall attendance parsing', () {
      test('extracts counts and percentage', () {
        final snapshot = parser.parse(LinwaysFixtures.overallAttendance);
        expect(snapshot.overall.conducted, const ProvenanceValue.extracted(40));
        expect(snapshot.overall.attended, const ProvenanceValue.extracted(32));
        expect(snapshot.overall.percentage.value, 80.0);
        expect(snapshot.overall.percentage.source, ExtractionSource.extracted);
      });

      test('derives absent and percentage from counts', () {
        final snapshot = parser.parse(LinwaysFixtures.overallCountsOnly);
        expect(snapshot.overall.absent.value, 8);
        expect(snapshot.overall.absent.source, ExtractionSource.derived);
        expect(snapshot.overall.percentage.value, closeTo(80.0, 0.001));
        expect(snapshot.overall.percentage.source, ExtractionSource.derived);
      });

      test('derives status from percentage', () {
        final snapshot = parser.parse(LinwaysFixtures.overallAttendance);
        expect(snapshot.overall.status.value, 'Moderate');
        expect(snapshot.overall.status.source, ExtractionSource.derived);
      });

      test('percentage-only screen leaves counts missing', () {
        final snapshot = parser.parse(LinwaysFixtures.overallPercentageOnly);
        expect(snapshot.overall.percentage.value, closeTo(89.11, 0.001));
        expect(snapshot.overall.conducted.isMissing, isTrue);
        expect(snapshot.overall.attended.isMissing, isTrue);
      });

      test('parses standalone big percentage', () {
        final snapshot = parser.parse(LinwaysFixtures.standalonePercentage);
        expect(snapshot.overall.percentage.value, closeTo(89.11, 0.001));
        expect(snapshot.overall.percentage.source, ExtractionSource.extracted);
      });

      test('preserves conflicting visible absent and warns', () {
        final snapshot = parser.parse(LinwaysFixtures.overallAbsentConflict);
        expect(snapshot.overall.absent.value, 9);
        expect(snapshot.overall.absent.source, ExtractionSource.extracted);
        expect(
          snapshot.warnings.any((w) => w.code == 'absentMismatch'),
          isTrue,
        );
      });

      test('preserves conflicting visible percentage and warns', () {
        final snapshot = parser.parse(LinwaysFixtures.overallPercentageConflict);
        expect(snapshot.overall.percentage.value, 75.0);
        expect(
          snapshot.warnings.any((w) => w.code == 'percentageMismatch'),
          isTrue,
        );
      });

      test('suspicious OCR counts are not guessed', () {
        final snapshot = parser.parse(LinwaysFixtures.subjectWiseOcrNoise);
        final row = snapshot.subjects.single;
        expect(row.name.value, 'Operating Systems');
        expect(row.conducted.isMissing, isTrue);
        expect(row.attended.isMissing, isTrue);
        expect(row.absent.isMissing, isTrue);
        expect(row.percentage.isMissing, isTrue);
        expect(
          snapshot.warnings.any((w) => w.code == 'suspiciousOcrNumber'),
          isTrue,
        );
      });
    });

    group('identity parsing', () {
      test('extracts full profile header', () {
        final snapshot = parser.parse(LinwaysFixtures.overallAttendance);
        expect(snapshot.identity.studentName.value, 'Santhosh Kumar');
        expect(snapshot.identity.studentId.value, '9538111909');
        expect(snapshot.identity.department.value, 'BCA');
        expect(snapshot.identity.semester.value, 'S5');
        expect(snapshot.identity.section.value, 'C');
        expect(snapshot.identity.academicYear.value, '2024-2025');
      });

      test('missing identity fields are MISSING, never guessed', () {
        final snapshot = parser.parse(LinwaysFixtures.overallCountsOnly);
        expect(snapshot.identity.studentName.isMissing, isTrue);
        expect(snapshot.identity.studentId.isMissing, isTrue);
      });

      test('never guesses a subject code or register number', () {
        final snapshot = parser.parse(LinwaysFixtures.subjectWiseNoHeader);
        for (final subject in snapshot.subjects) {
          expect(subject.code.isMissing, isTrue);
        }
      });
    });

    group('subject-wise parsing', () {
      test('parses header-based table rows with code and faculty', () {
        final snapshot = parser.parse(LinwaysFixtures.subjectWise);
        expect(snapshot.subjects, hasLength(3));

        final os = snapshot.subjects.first;
        expect(os.name.value, 'Operating Systems');
        expect(os.code.value, 'CS201');
        expect(os.faculty.value, contains('Prof. Meena'));
        expect(os.conducted.value, 40);
        expect(os.attended.value, 32);
        expect(os.absent.value, 8);
        expect(os.percentage.value, closeTo(80.0, 0.001));
      });

      test('parses rows without header (conducted → attended → absent)', () {
        final snapshot = parser.parse(LinwaysFixtures.subjectWiseNoHeader);
        expect(snapshot.subjects, hasLength(2));
        final os = snapshot.subjects.first;
        expect(os.name.value, 'Operating Systems');
        expect(os.conducted.value, 40);
        expect(os.attended.value, 32);
        expect(os.absent.value, 8);
        expect(os.percentage.isMissing, isTrue);
      });

      test('derives absent when only percentage column present', () {
        final snapshot = parser.parse(LinwaysFixtures.subjectWiseNoAbsentColumn);
        final os = snapshot.subjects.first;
        expect(os.absent.value, 8);
        expect(os.absent.source, ExtractionSource.derived);
        expect(os.percentage.value, closeTo(80.0, 0.001));
      });

      test('deduplicates duplicate rows and warns', () {
        final snapshot = parser.parse(LinwaysFixtures.subjectWiseDuplicates);
        expect(snapshot.subjects, hasLength(1));
        expect(
          snapshot.warnings.any((w) => w.code == 'duplicateSubjectRow'),
          isTrue,
        );
      });

      test('flags invalid subject counts', () {
        final snapshot = parser.parse(LinwaysFixtures.subjectWiseInvalidCounts);
        expect(snapshot.subjects, hasLength(1));
        expect(
          snapshot.warnings.any((w) => w.code == 'invalidSubjectCounts'),
          isTrue,
        );
      });

      test('attendance date extracted when labelled', () {
        final snapshot = parser.parse(LinwaysFixtures.subjectWise);
        expect(snapshot.attendanceDate.value, '12-08-2026');
      });
    });

    group('no guessing', () {
      test('unsupported screens yield no attendance data', () {
        final snapshot = parser.parse(LinwaysFixtures.unsupported);
        expect(snapshot.hasAnyAttendance, isFalse);
        expect(
          snapshot.warnings.any((w) =>
              w.code == 'noAttendanceData' &&
              w.severity == ValidationSeverity.error),
          isTrue,
        );
      });

      test('every parsed field carries provenance', () {
        final snapshot = parser.parse(LinwaysFixtures.overallAttendance);
        expect(snapshot.overall.conducted.source, ExtractionSource.extracted);
        expect(snapshot.overall.absent.source, ExtractionSource.derived);
        expect(snapshot.identity.section.source, ExtractionSource.extracted);
      });
    });
  });
}
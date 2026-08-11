import 'package:college_project_app/features/attendance/data/attendance_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AttendanceSummary.fromJson', () {
    test('parses the documented response shape', () {
      final summary = AttendanceSummary.fromJson(const {
        'totalHours': 120,
        'attendedHours': 107,
        'totalPresent': 107,
        'attendancePercentage': 89.11,
        'isHourWiseEnabled': true,
      });

      expect(summary.totalHours, 120);
      expect(summary.attendedHours, 107);
      expect(summary.totalPresent, 107);
      expect(summary.attendancePercentage, 89.11);
      expect(summary.isHourWiseEnabled, isTrue);
    });

    test('accepts numeric strings', () {
      final summary = AttendanceSummary.fromJson(const {
        'totalHours': '120',
        'attendedHours': '107',
        'totalPresent': '107',
        'attendancePercentage': '89.11',
        'isHourWiseEnabled': false,
      });

      expect(summary.totalHours, 120);
      expect(summary.attendancePercentage, 89.11);
      expect(summary.isHourWiseEnabled, isFalse);
    });

    test('tolerates missing optional percentage and unknown keys', () {
      final summary = AttendanceSummary.fromJson(const {
        'totalHours': 120,
        'attendedHours': 107,
        'totalPresent': 107,
        'isHourWiseEnabled': false,
        'someFutureKey': 'ignored',
      });

      expect(summary.attendancePercentage, isNull);
      expect(summary.totalPresent, 107);
    });

    test('defaults missing integers to zero', () {
      final summary = AttendanceSummary.fromJson(const {
        'attendancePercentage': 50,
        'isHourWiseEnabled': true,
      });

      expect(summary.totalHours, 0);
      expect(summary.attendedHours, 0);
    });
  });
}

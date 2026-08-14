/// Representative OCR-text fixtures for the Linways screenshot parser.
///
/// These mirror the documented Linways layouts (profile header + overall
/// attendance; subject-wise table; profile screen). Validation against the
/// actual user-provided Linways screenshots is a pending Part 2 task — these
/// fixtures are the reference corpus until then.
class LinwaysFixtures {
  LinwaysFixtures._();

  /// Screen A: overall attendance with a profile header.
  static const String overallAttendance = '''
Attendance Summary
Student Name: Santhosh Kumar
Register No: 9538111909
Department: BCA
Semester: S5
Section: C
Academic Year: 2024-2025
Classes Conducted: 40
Classes Attended: 32
Attendance Percentage: 80.00 %
''';

  /// Screen A: percentage only, no counts.
  static const String overallPercentageOnly = '''
Attendance Summary
Attendance Percentage: 89.11 %
''';

  /// Screen A: counts only — percentage and absent must be derived.
  static const String overallCountsOnly = '''
Attendance Summary
Classes Conducted: 40
Classes Attended: 32
''';

  /// Screen A: visible absent conflicts with the calculation (40 - 32 = 8,
  /// screenshot says 9) — value must be preserved, warning generated.
  static const String overallAbsentConflict = '''
Attendance Summary
Classes Conducted: 40
Classes Attended: 32
Classes Absent: 9
Attendance Percentage: 80.00 %
''';

  /// Screen A: visible percentage conflicts with the counts.
  static const String overallPercentageConflict = '''
Attendance Summary
Classes Conducted: 40
Classes Attended: 32
Attendance Percentage: 75.00 %
''';

  /// Screen A with a labelled attendance date.
  static const String overallWithDate = '''
Attendance Summary
As on 12-08-2026
Attendance Percentage: 89.11 %
''';

  /// Screen B: subject-wise table with a header row and pipe borders.
  static const String subjectWise = '''
Subject-wise Attendance
Student: Santhosh Kumar
Register No: 9538111909
As on 12-08-2026
Subject | Code | Faculty | Conducted | Attended | Absent | Percentage
Operating Systems | CS201 | Prof. Meena | 40 | 32 | 8 | 80.0%
DBMS | CS202 | Prof. Kumar | 42 | 38 | 4 | 90.48%
Programming in Java | CS203 | Dr. Rao | 36 | 29 | 7 | 80.56%
''';

  /// Screen B: subject rows without a header — trailing integers are
  /// conducted → attended → absent; percentage derived.
  static const String subjectWiseNoHeader = '''
Subject-wise Attendance
Operating Systems 40 32 8
DBMS 42 38 4
''';

  /// Screen B: rows with percentage but no absent column.
  static const String subjectWiseNoAbsentColumn = '''
Subject-wise Attendance
Operating Systems 40 32 80.0%
DBMS 42 38 90.48%
''';

  /// Screen B: duplicate rows must keep one and warn.
  static const String subjectWiseDuplicates = '''
Subject-wise Attendance
Operating Systems 40 32 8 80.0%
Operating Systems 40 32 8 80.0%
''';

  /// Screen B: attended > conducted — invalid row.
  static const String subjectWiseInvalidCounts = '''
Subject-wise Attendance
Operating Systems 40 45 8 80.0%
''';

  /// Screen B: OCR noise (O/I/L vs 0/1) in a count.
  static const String subjectWiseOcrNoise = '''
Subject-wise Attendance
Operating Systems 4O 32 8 80.0%
''';

  /// Screen C: student profile only.
  static const String studentProfile = '''
Student Profile
Student Name: Santhosh Kumar
Register No: 9538111909
Programme: BCA
Current Sem: S5
Section: C
Batch: 2024-2028
Academic Year: 2024-2025
Email: santhosh@example.com
''';

  /// Screen A with section A — mismatches a registered section C profile.
  static const String identityMismatchSection = '''
Attendance Summary
Student Name: Santhosh Kumar
Register No: 9538111909
Semester: S5
Section: A
Classes Conducted: 40
Classes Attended: 32
Attendance Percentage: 80.00 %
''';

  /// Not a Linways screen at all.
  static const String unsupported = '''
Welcome to my photo album!
These are pictures from my vacation.
Beautiful sunset at the beach.
''';

  /// No text at all.
  static const String empty = '';

  /// Percentage appears only as a standalone big number.
  static const String standalonePercentage = '''
Attendance Summary
Overall Attendance
89.11 %
''';
}
import 'package:college_project_app/features/reports/data/models/report.dart';
import 'package:college_project_app/features/reports/data/models/report_priority.dart';
import 'package:college_project_app/features/reports/data/models/report_status.dart';
import 'package:college_project_app/features/reports/widgets/report_detail_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Report _report({String id = 'r-2', String? duplicateOf}) => Report(
      id: id,
      title: 'Broken projector',
      description: 'Projector in room 12 is broken.',
      categoryId: 'cat-1',
      categoryName: 'Academic',
      priority: ReportPriority.high,
      status: ReportStatus.pending,
      reporterId: 'user-b',
      communityId: 'community-1',
      supportCount: 0,
      createdAt: DateTime(2026, 10, 5),
      duplicateOf: duplicateOf,
    );

Map<String, dynamic> _json({Object? duplicateOf, bool includeKey = true}) => {
      'id': 'r-2',
      'title': 'Broken projector',
      'description': 'Projector in room 12 is broken.',
      'category_id': 'cat-1',
      'priority': 'high',
      'status': 'pending',
      'reporter_id': 'user-b',
      'community_id': 'community-1',
      'created_at': '2026-10-05T10:00:00Z',
      if (includeKey) 'duplicate_of': duplicateOf,
    };

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('Report.duplicateOf parsing', () {
    test('reads a uuid target', () {
      final report =
          Report.fromJson(_json(duplicateOf: 'r-1'), currentUserId: 'user-a');
      expect(report.duplicateOf, 'r-1');
      expect(report.isDuplicate, isTrue);
    });

    test('null duplicate_of means not flagged', () {
      final report =
          Report.fromJson(_json(duplicateOf: null), currentUserId: 'user-a');
      expect(report.duplicateOf, isNull);
      expect(report.isDuplicate, isFalse);
    });

    test('missing key means not flagged, not a crash', () {
      final report = Report.fromJson(
        _json(includeKey: false),
        currentUserId: 'user-a',
      );
      expect(report.duplicateOf, isNull);
      expect(report.isDuplicate, isFalse);
    });

    test('blank or whitespace value normalises to null', () {
      expect(
        Report.fromJson(_json(duplicateOf: '   '), currentUserId: 'user-a')
            .duplicateOf,
        isNull,
      );
    });

    test('non-string value normalises to null', () {
      expect(
        Report.fromJson(_json(duplicateOf: 42), currentUserId: 'user-a')
            .duplicateOf,
        isNull,
      );
    });

    test('a self-reference is not treated as a duplicate', () {
      final report =
          Report.fromJson(_json(duplicateOf: 'r-2'), currentUserId: 'user-a');
      expect(report.duplicateOf, 'r-2');
      expect(report.isDuplicate, isFalse,
          reason: 'a report must never point at itself in the UI');
    });

    test('copyWith preserves duplicateOf', () {
      final report = _report(duplicateOf: 'r-1');
      expect(report.copyWith(isSupported: true).duplicateOf, 'r-1');
    });
  });

  group('DuplicateNoticeCard', () {
    testWidgets('renders nothing when the report is not flagged',
        (tester) async {
      await tester.pumpWidget(_wrap(DuplicateNoticeCard(
        report: _unflagged(),
      )));
      expect(find.byType(DuplicateNoticeCard), findsOneWidget);
      expect(find.textContaining('similar report'), findsNothing);
    });

    testWidgets('student sees guidance, never a reprimand', (tester) async {
      await tester.pumpWidget(_wrap(DuplicateNoticeCard(
        report: _report(duplicateOf: 'r-1'),
      )));

      expect(find.text('A similar report already exists'), findsOneWidget);
      expect(find.textContaining('Supporting their report'), findsOneWidget);
      // The advisory framing must not read as a fault.
      expect(find.textContaining('invalid'), findsNothing);
      expect(find.textContaining('rejected'), findsNothing);
    });

    testWidgets('staff sees the triage wording', (tester) async {
      await tester.pumpWidget(_wrap(DuplicateNoticeCard(
        report: _report(duplicateOf: 'r-1'),
        viewerIsStaff: true,
      )));

      expect(find.text('Possible duplicate of an earlier report'),
          findsOneWidget);
      expect(find.textContaining('Advisory only'), findsOneWidget);
    });

    testWidgets('hides the link when no navigation is wired up', (tester) async {
      await tester.pumpWidget(_wrap(DuplicateNoticeCard(
        report: _report(duplicateOf: 'r-1'),
      )));

      expect(find.text('View the earlier report'), findsNothing);
    });

    testWidgets('link invokes the callback', (tester) async {
      String? opened;
      await tester.pumpWidget(_wrap(DuplicateNoticeCard(
        report: _report(duplicateOf: 'r-1'),
        onOpenCanonical: () => opened = 'r-1',
      )));

      await tester.tap(find.text('View the earlier report'));
      await tester.pump();
      expect(opened, 'r-1');
    });

    testWidgets('renders nothing visible for an unflagged report',
        (tester) async {
      await tester.pumpWidget(_wrap(DuplicateNoticeCard(
        report: _unflagged(),
      )));
      // The widget collapses to zero-size rather than painting an empty card.
      final size = tester.getSize(find.byType(DuplicateNoticeCard));
      expect(size.width, 0);
      expect(size.height, 0);
    });
  });
}

/// An unflagged report, built without the helper's duplicateOf parameter.
Report _unflagged() => Report(
      id: 'r-9',
      title: 'Wi-Fi dropping',
      description: 'Library wifi drops hourly.',
      categoryId: 'cat-1',
      categoryName: 'Academic',
      priority: ReportPriority.low,
      status: ReportStatus.pending,
      reporterId: 'user-b',
      communityId: 'community-1',
      supportCount: 0,
      createdAt: DateTime(2026, 10, 5),
    );

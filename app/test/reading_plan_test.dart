import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gramma/l10n.dart';
import 'package:gramma/reading_plan.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a plan in the asset schema decodes fully', () {
    final json = jsonEncode({
      'name': 'Test',
      'source': 'a schema example',
      'days': [
        [
          {'label': '1. Mose 1-2', 'osis': 'Gen.1'},
          {'label': 'Psalm 1-2', 'osis': 'Ps.1'},
        ],
        [
          {'label': 'Matthäus 1', 'osis': 'Matt.1'},
        ],
      ],
    });
    final plan = ReadingPlan.decode(json)!;
    expect(plan.name, 'Test');
    expect(plan.source, 'a schema example');
    expect(plan.days.length, 2);
    expect(plan.days[0].map((r) => r.osis), ['Gen.1', 'Ps.1']);
    expect(plan.days[1].single.label, 'Matthäus 1');
  });

  test('garbage decodes to null', () {
    expect(ReadingPlan.decode(''), isNull);
    expect(ReadingPlan.decode(jsonEncode({'name': 'x', 'days': []})), isNull);
  });

  test('a 366-day plan anchors to the leap-year calendar', () {
    expect(planDayFor(DateTime(2025, 1, 1), planDays: 366), 1);
    expect(planDayFor(DateTime(2025, 2, 28), planDays: 366), 59);
    expect(
      planDayFor(DateTime(2024, 2, 29), planDays: 366),
      60,
      reason: 'leap day exists in leap years',
    );
    expect(
      planDayFor(DateTime(2025, 3, 1), planDays: 366),
      61,
      reason: '1 March is day 61 in every year',
    );
    expect(planDayFor(DateTime(2025, 12, 31), planDays: 366), 366);
  });

  test('a 365-day plan follows the year it is read in', () {
    expect(planDayFor(DateTime(2026, 1, 1)), 1);
    expect(planDayFor(DateTime(2026, 3, 1)), 60);
    expect(planDayFor(DateTime(2026, 10, 26)), 299);
    expect(planDayFor(DateTime(2026, 12, 31)), 365);
    expect(
      planDayFor(DateTime(2024, 12, 31)),
      366,
      reason: 'clamped by the popup',
    );
  });

  test('the plan day never skips or repeats around the clock change', () {
    // The autumn change (2026-10-25 in Europe) once made 26 and 27 October
    // the same day and 28 October two days later; the spring change had
    // the same effect in the other direction. Every date is one more than
    // the day before, whatever the plan length.
    for (final planDays in [365, 366]) {
      var previous = planDayFor(DateTime(2026, 1, 1), planDays: planDays);
      for (
        var d = DateTime(2026, 1, 2);
        d.year == 2026;
        d = DateTime(2026, d.month, d.day + 1)
      ) {
        final day = planDayFor(d, planDays: planDays);
        final step = day - previous;
        expect(
          step,
          planDays == 366 && d.month == 3 && d.day == 1 ? 2 : 1,
          reason: '$d with $planDays days',
        );
        previous = day;
      }
    }
  });

  testWidgets('the plan popup navigates days and opens readings', (
    tester,
  ) async {
    final plan = ReadingPlan(
      name: 'Test',
      source: 'src',
      days: [
        [const PlanRef(label: 'Erster', osis: 'Gen.1')],
        [
          const PlanRef(label: 'Zweiter A', osis: 'Exod.2'),
          const PlanRef(label: 'Zweiter B', osis: 'Ps.3'),
        ],
      ],
    );
    String? opened;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showReadingPlan(
              context,
              plan: plan,
              initialDay: 2,
              onOpen: (osis) => opened = osis,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Test — Day 2'), findsOneWidget);
    expect(find.text('Zweiter B'), findsOneWidget);

    await tester.tap(find.byKey(const Key('plan-prev')));
    await tester.pumpAndSettle();
    expect(find.text('Test — Day 1'), findsOneWidget);
    expect(
      find.byKey(const Key('plan-prev')),
      findsOneWidget,
    ); // disabled at day 1 but present
    await tester.tap(find.byKey(const Key('plan-ref-0')));
    await tester.pumpAndSettle();
    expect(opened, 'Gen.1');
    expect(
      find.text('Test — Day 1'),
      findsNothing,
      reason: 'opening a reading closes the popup',
    );
  });
}

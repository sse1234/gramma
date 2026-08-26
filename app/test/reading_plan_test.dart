import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gramma/l10n.dart';
import 'package:gramma/reading_plan.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the bundled Bibelliga plan is complete', () {
    final json = File('assets/plans/bibelliga.json').readAsStringSync();
    final plan = ReadingPlan.decode(json)!;
    expect(plan.name, 'Bibelliga');
    expect(plan.days.length, 366, reason: 'a full leap-year calendar');
    expect(plan.days.every((d) => d.length == 3), isTrue,
        reason: 'three streams every day');
    expect(plan.days[0].map((r) => r.osis), ['Gen.1', 'Ps.1', 'Matt.1']);
    expect(plan.days[365].map((r) => r.label),
        ['Hiob 41-42', 'Maleachi 3', 'Offenbarung 22']);
    final books = {
      for (final day in plan.days)
        for (final ref in day) ref.osis.split('.').first,
    };
    expect(books.length, 66, reason: 'the whole canon, nothing else');
  });

  test('garbage decodes to null', () {
    expect(ReadingPlan.decode(''), isNull);
    expect(ReadingPlan.decode(jsonEncode({'name': 'x', 'days': []})), isNull);
  });

  test('plan days anchor to the leap-year calendar', () {
    expect(planDayFor(DateTime(2025, 1, 1)), 1);
    expect(planDayFor(DateTime(2025, 2, 28)), 59);
    expect(planDayFor(DateTime(2024, 2, 29)), 60,
        reason: 'leap day exists in leap years');
    expect(planDayFor(DateTime(2025, 3, 1)), 61,
        reason: '1 March is day 61 in every year');
    expect(planDayFor(DateTime(2025, 12, 31)), 366);
  });

  testWidgets('the plan popup navigates days and opens readings',
      (tester) async {
    final plan = ReadingPlan(name: 'Test', source: 'src', days: [
      [const PlanRef(label: 'Erster', osis: 'Gen.1')],
      [
        const PlanRef(label: 'Zweiter A', osis: 'Exod.2'),
        const PlanRef(label: 'Zweiter B', osis: 'Ps.3'),
      ],
    ]);
    String? opened;
    await tester.pumpWidget(MaterialApp(
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
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Test — Day 2'), findsOneWidget);
    expect(find.text('Zweiter B'), findsOneWidget);

    await tester.tap(find.byKey(const Key('plan-prev')));
    await tester.pumpAndSettle();
    expect(find.text('Test — Day 1'), findsOneWidget);
    expect(find.byKey(const Key('plan-prev')),
        findsOneWidget); // disabled at day 1 but present
    await tester.tap(find.byKey(const Key('plan-ref-0')));
    await tester.pumpAndSettle();
    expect(opened, 'Gen.1');
    expect(find.text('Test — Day 1'), findsNothing,
        reason: 'opening a reading closes the popup');
  });
}

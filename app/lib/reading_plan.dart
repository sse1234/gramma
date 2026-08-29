import 'dart:convert';

import 'package:flutter/material.dart';

import 'l10n.dart';
import 'src/rust/api/library.dart' as rust;

/// Reading plans: 1..n references per day of the year. Plans are
/// imported from JSON files into the library like modules; with none
/// imported, the feature stays dormant.
class PlanRef {
  const PlanRef({required this.label, required this.osis});

  final String label;

  /// Where the reading starts — the jump target.
  final String osis;
}

class ReadingPlan {
  const ReadingPlan({
    required this.name,
    required this.source,
    required this.days,
  });

  final String name;
  final String source;
  final List<List<PlanRef>> days;

  static ReadingPlan? decode(String json) {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      final days = <List<PlanRef>>[
        for (final day in data['days'] as List)
          [
            for (final ref in day as List)
              PlanRef(
                label: (ref as Map)['label'] as String,
                osis: ref['osis'] as String,
              ),
          ],
      ];
      if (days.isEmpty) return null;
      return ReadingPlan(
        name: data['name'] as String,
        source: (data['source'] as String?) ?? '',
        days: days,
      );
    } catch (_) {
      return null;
    }
  }

  /// The imported plans, by name — the import validated the JSON, so
  /// a record failing to decode is skipped defensively.
  static List<ReadingPlan> fromLibrary() {
    return [for (final record in rust.plans()) ?decode(record.json)];
  }
}

/// The 1-based plan day for a date. Plans span the full leap-year
/// calendar (366 days), anchored by month and day: 1 March is day 61 in
/// every year, and day 60 (29 February) simply has no date in common
/// years.
int planDayFor(DateTime date) {
  return DateTime(2024, date.month, date.day)
          .difference(DateTime(2024, 1, 1))
          .inDays +
      1;
}

/// The plan popup: today's readings with day navigation; tapping a
/// reference opens it in the reading desk.
Future<void> showReadingPlan(
  BuildContext context, {
  required ReadingPlan plan,
  required ValueChanged<String> onOpen,
  int? initialDay,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _PlanDialog(
      plan: plan,
      onOpen: onOpen,
      initialDay: initialDay ?? planDayFor(DateTime.now()),
    ),
  );
}

class _PlanDialog extends StatefulWidget {
  const _PlanDialog({
    required this.plan,
    required this.onOpen,
    required this.initialDay,
  });

  final ReadingPlan plan;
  final ValueChanged<String> onOpen;
  final int initialDay;

  @override
  State<_PlanDialog> createState() => _PlanDialogState();
}

class _PlanDialogState extends State<_PlanDialog> {
  late int _day = widget.initialDay.clamp(1, widget.plan.days.length);

  int get _today => planDayFor(DateTime.now());

  void _shift(int delta) {
    setState(
        () => _day = (_day + delta).clamp(1, widget.plan.days.length));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final refs = widget.plan.days[_day - 1];
    return AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(
                context.l10n.planDay(widget.plan.name, _day),
                key: const Key('plan-title')),
          ),
          IconButton(
            key: const Key('plan-prev'),
            icon: const Icon(Icons.chevron_left),
            visualDensity: VisualDensity.compact,
            onPressed: _day > 1 ? () => _shift(-1) : null,
          ),
          IconButton(
            key: const Key('plan-next'),
            icon: const Icon(Icons.chevron_right),
            visualDensity: VisualDensity.compact,
            onPressed:
                _day < widget.plan.days.length ? () => _shift(1) : null,
          ),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _day == _today
                  ? context.l10n.todaysReadings
                  : widget.plan.source,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < refs.length; i++)
              ListTile(
                key: Key('plan-ref-$i'),
                leading: Icon(Icons.menu_book_outlined,
                    color: theme.colorScheme.primary),
                title: Text(refs[i].label),
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onOpen(refs[i].osis);
                },
              ),
          ],
        ),
      ),
      actions: [
        if (_day != _today)
          TextButton(
            key: const Key('plan-today'),
            onPressed: () => setState(() => _day = _today),
            child: Text(context.l10n.today),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.close),
        ),
      ],
    );
  }
}

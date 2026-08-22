import 'package:flutter/material.dart';

import 'src/rust/api/references.dart';

/// Walking-skeleton screen: proves the Flutter ↔ Rust round trip by resolving
/// typed references through gramma-core and echoing the canonical OSIS form.
class ReferenceScreen extends StatefulWidget {
  const ReferenceScreen({super.key});

  @override
  State<ReferenceScreen> createState() => _ReferenceScreenState();
}

class _ReferenceScreenState extends State<ReferenceScreen> {
  ParseOutcome? _outcome;

  void _onChanged(String input) {
    setState(() {
      _outcome = input.trim().isEmpty ? null : parseReference(input: input);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outcome = _outcome;
    return Scaffold(
      appBar: AppBar(title: const Text('gramma')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Bible reference',
                    hintText: 'Joh 3,16 · 1 Kor 13,4-7 · Ps 23',
                  ),
                  onChanged: _onChanged,
                ),
                const SizedBox(height: 24),
                if (outcome?.osis != null)
                  Text(
                    outcome!.osis!,
                    key: const Key('osis-result'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium,
                  ),
                if (outcome?.error != null)
                  Text(
                    outcome!.error!,
                    key: const Key('parse-error'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

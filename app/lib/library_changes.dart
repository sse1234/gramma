import 'package:flutter/foundation.dart';

/// Counts changes to what the library holds — an import, a delete, a
/// rename (ADR 0039). The desk listens and reloads its module lists;
/// the views are handed the count and load their text again when it
/// moves, so a text imported over itself shows its new content and a
/// deleted one leaves the screen at once.
final ValueNotifier<int> libraryRevision = ValueNotifier<int>(0);

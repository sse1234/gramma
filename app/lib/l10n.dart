import 'package:flutter/widgets.dart';

import 'l10n/app_localizations.dart';

export 'l10n/app_localizations.dart';

/// Shorthand for the generated localizations (ADR 0015).
extension L10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

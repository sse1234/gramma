import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show GlobalMaterialLocalizations;

import 'l10n/app_localizations.dart';

export 'l10n/app_localizations.dart';

/// Shorthand for the generated localizations (ADR 0015).
extension L10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// The delegates the app runs with (ADR 0038): gramma's own strings and
/// the Material, Cupertino and widgets translations of the packages its
/// widgets come from since the Material library left the framework.
///
/// The generated `AppLocalizations.localizationsDelegates` still names
/// the framework's former copies. The package's widgets do not look
/// those up: under a German locale they found no translations at all and
/// refused to build.
const List<LocalizationsDelegate<dynamic>> grammaLocalizationsDelegates = [
  AppLocalizations.delegate,
  ...GlobalMaterialLocalizations.delegates,
];

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
  ];

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @keep.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get keep;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @toolsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get toolsTooltip;

  /// No description provided for @readingPlanBibelliga.
  ///
  /// In en, this message translates to:
  /// **'Reading plan · Bibelliga'**
  String get readingPlanBibelliga;

  /// No description provided for @desksTooltip.
  ///
  /// In en, this message translates to:
  /// **'Desks — {name}'**
  String desksTooltip(String name);

  /// No description provided for @newDesk.
  ///
  /// In en, this message translates to:
  /// **'New desk'**
  String get newDesk;

  /// No description provided for @renameDeskMenu.
  ///
  /// In en, this message translates to:
  /// **'Rename desk…'**
  String get renameDeskMenu;

  /// No description provided for @deleteDeskMenu.
  ///
  /// In en, this message translates to:
  /// **'Delete desk…'**
  String get deleteDeskMenu;

  /// No description provided for @renameDeskTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename desk'**
  String get renameDeskTitle;

  /// No description provided for @deleteDeskTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String deleteDeskTitle(String name);

  /// No description provided for @deleteDeskBody.
  ///
  /// In en, this message translates to:
  /// **'The desk and its view arrangement are removed on every synced device. Your texts and reading history stay.'**
  String get deleteDeskBody;

  /// No description provided for @deskDefaultPrefix.
  ///
  /// In en, this message translates to:
  /// **'Desk'**
  String get deskDefaultPrefix;

  /// No description provided for @addViewTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add view'**
  String get addViewTooltip;

  /// No description provided for @textView.
  ///
  /// In en, this message translates to:
  /// **'Text view'**
  String get textView;

  /// No description provided for @footnotesView.
  ///
  /// In en, this message translates to:
  /// **'Footnotes view'**
  String get footnotesView;

  /// No description provided for @commentaryView.
  ///
  /// In en, this message translates to:
  /// **'Commentary view'**
  String get commentaryView;

  /// No description provided for @dictionaryView.
  ///
  /// In en, this message translates to:
  /// **'Dictionary view'**
  String get dictionaryView;

  /// No description provided for @settingsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTooltip;

  /// No description provided for @importOsisTooltip.
  ///
  /// In en, this message translates to:
  /// **'Import module…'**
  String get importOsisTooltip;

  /// No description provided for @importedModule.
  ///
  /// In en, this message translates to:
  /// **'Imported {title} ({verses} verses)'**
  String importedModule(String title, int verses);

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String importFailed(String error);

  /// No description provided for @unlinked.
  ///
  /// In en, this message translates to:
  /// **'Unlinked'**
  String get unlinked;

  /// No description provided for @closeView.
  ///
  /// In en, this message translates to:
  /// **'Close view'**
  String get closeView;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @forward.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get forward;

  /// No description provided for @history.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get history;

  /// No description provided for @viewMenuTooltip.
  ///
  /// In en, this message translates to:
  /// **'View menu'**
  String get viewMenuTooltip;

  /// No description provided for @footnotesTitle.
  ///
  /// In en, this message translates to:
  /// **'Footnotes'**
  String get footnotesTitle;

  /// No description provided for @commentaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Commentary'**
  String get commentaryTitle;

  /// No description provided for @dictionaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Dictionary'**
  String get dictionaryTitle;

  /// No description provided for @selectorTooltip.
  ///
  /// In en, this message translates to:
  /// **'Select book, chapter, verse'**
  String get selectorTooltip;

  /// No description provided for @linkFootnotesHint.
  ///
  /// In en, this message translates to:
  /// **'Link this view to a text view to see its footnotes'**
  String get linkFootnotesHint;

  /// No description provided for @noFootnotes.
  ///
  /// In en, this message translates to:
  /// **'No footnotes in view'**
  String get noFootnotes;

  /// No description provided for @linkCommentaryHint.
  ///
  /// In en, this message translates to:
  /// **'Link this view to a text view to see the commentary on its passage'**
  String get linkCommentaryHint;

  /// No description provided for @noCommentary.
  ///
  /// In en, this message translates to:
  /// **'No commentary in view'**
  String get noCommentary;

  /// No description provided for @noCommentaryModules.
  ///
  /// In en, this message translates to:
  /// **'Import a commentary (a SWORD zip package) to use this view'**
  String get noCommentaryModules;

  /// No description provided for @importedCommentary.
  ///
  /// In en, this message translates to:
  /// **'Imported {title} ({entries} entries)'**
  String importedCommentary(String title, int entries);

  /// No description provided for @importedDictionary.
  ///
  /// In en, this message translates to:
  /// **'Imported {title} ({entries} entries)'**
  String importedDictionary(String title, int entries);

  /// No description provided for @noDictionaryModules.
  ///
  /// In en, this message translates to:
  /// **'Import a dictionary (a SWORD zip package) to use this view'**
  String get noDictionaryModules;

  /// No description provided for @searchDictionaryHint.
  ///
  /// In en, this message translates to:
  /// **'Search by Strong\'s number or word — or long-press a word in the text'**
  String get searchDictionaryHint;

  /// No description provided for @dictionarySearchLabel.
  ///
  /// In en, this message translates to:
  /// **'Number or word'**
  String get dictionarySearchLabel;

  /// No description provided for @noDictionaryResults.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get noDictionaryResults;

  /// No description provided for @strongsTagged.
  ///
  /// In en, this message translates to:
  /// **'Strong\'s numbers'**
  String get strongsTagged;

  /// No description provided for @noConcordanceSource.
  ///
  /// In en, this message translates to:
  /// **'Import a Strong\'s-tagged Bible (e.g. the KJV) to see occurrences'**
  String get noConcordanceSource;

  /// No description provided for @importToBegin.
  ///
  /// In en, this message translates to:
  /// **'Import an OSIS module to begin reading'**
  String get importToBegin;

  /// No description provided for @passageNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Passage not available in {module}'**
  String passageNotAvailable(String module);

  /// No description provided for @planDay.
  ///
  /// In en, this message translates to:
  /// **'{name} — Day {day}'**
  String planDay(String name, int day);

  /// No description provided for @todaysReadings.
  ///
  /// In en, this message translates to:
  /// **'Today\'s readings'**
  String get todaysReadings;

  /// No description provided for @sectionReading.
  ///
  /// In en, this message translates to:
  /// **'Reading'**
  String get sectionReading;

  /// No description provided for @textSize.
  ///
  /// In en, this message translates to:
  /// **'Text size'**
  String get textSize;

  /// No description provided for @pxColumnLabel.
  ///
  /// In en, this message translates to:
  /// **'{px} px column'**
  String pxColumnLabel(int px);

  /// No description provided for @footnoteTextSize.
  ///
  /// In en, this message translates to:
  /// **'Footnote text size'**
  String get footnoteTextSize;

  /// No description provided for @previewTextSize.
  ///
  /// In en, this message translates to:
  /// **'Preview text size'**
  String get previewTextSize;

  /// No description provided for @commentaryTextSize.
  ///
  /// In en, this message translates to:
  /// **'Commentary text size'**
  String get commentaryTextSize;

  /// No description provided for @lineSpacing.
  ///
  /// In en, this message translates to:
  /// **'Line spacing'**
  String get lineSpacing;

  /// No description provided for @lineSpacingLabel.
  ///
  /// In en, this message translates to:
  /// **'{v} × font size'**
  String lineSpacingLabel(String v);

  /// No description provided for @columnTurnEffort.
  ///
  /// In en, this message translates to:
  /// **'Column turn effort'**
  String get columnTurnEffort;

  /// No description provided for @columnAdvanceLabel.
  ///
  /// In en, this message translates to:
  /// **'{p}% of a column'**
  String columnAdvanceLabel(int p);

  /// No description provided for @defaultText.
  ///
  /// In en, this message translates to:
  /// **'Default text'**
  String get defaultText;

  /// No description provided for @defaultTextSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Used to resolve references in previews.'**
  String get defaultTextSubtitle;

  /// No description provided for @firstModule.
  ///
  /// In en, this message translates to:
  /// **'First module'**
  String get firstModule;

  /// No description provided for @sectionAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get sectionAppearance;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @tone.
  ///
  /// In en, this message translates to:
  /// **'Tone'**
  String get tone;

  /// No description provided for @fontWeightLightMode.
  ///
  /// In en, this message translates to:
  /// **'Font weight · light mode'**
  String get fontWeightLightMode;

  /// No description provided for @fontWeightDarkMode.
  ///
  /// In en, this message translates to:
  /// **'Font weight · dark mode'**
  String get fontWeightDarkMode;

  /// No description provided for @weightNatural.
  ///
  /// In en, this message translates to:
  /// **'natural'**
  String get weightNatural;

  /// No description provided for @trueBlack.
  ///
  /// In en, this message translates to:
  /// **'True black in dark mode'**
  String get trueBlack;

  /// No description provided for @trueBlackSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Keep the background fully black; contrast dims only the text.'**
  String get trueBlackSubtitle;

  /// No description provided for @contrast.
  ///
  /// In en, this message translates to:
  /// **'Contrast'**
  String get contrast;

  /// No description provided for @sectionTypesetting.
  ///
  /// In en, this message translates to:
  /// **'Typesetting'**
  String get sectionTypesetting;

  /// No description provided for @typeface.
  ///
  /// In en, this message translates to:
  /// **'Typeface'**
  String get typeface;

  /// No description provided for @changeEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Change…'**
  String get changeEllipsis;

  /// No description provided for @lineWidth.
  ///
  /// In en, this message translates to:
  /// **'Line width'**
  String get lineWidth;

  /// No description provided for @lineWidthSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{ems} em — about {chars} characters per line. Fixed so the visual shape of the text stays familiar on every page and device.'**
  String lineWidthSubtitle(int ems, int chars);

  /// No description provided for @measureDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Change line width?'**
  String get measureDialogTitle;

  /// No description provided for @measureDialogBody.
  ///
  /// In en, this message translates to:
  /// **'The line width determines where every line of text breaks. Changing it re-typesets everything — the familiar visual shape of pages you have read will change. This setting is meant to be chosen once and kept.'**
  String get measureDialogBody;

  /// No description provided for @keepCurrent.
  ///
  /// In en, this message translates to:
  /// **'Keep current'**
  String get keepCurrent;

  /// No description provided for @understandChange.
  ///
  /// In en, this message translates to:
  /// **'I understand, change it'**
  String get understandChange;

  /// No description provided for @typefaceDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Change typeface?'**
  String get typefaceDialogTitle;

  /// No description provided for @typefaceDialogBody.
  ///
  /// In en, this message translates to:
  /// **'The typeface defines where every line of text breaks. Changing it re-typesets everything — the familiar visual shape of pages you have read will change.'**
  String get typefaceDialogBody;

  /// No description provided for @fontBookSubtitle.
  ///
  /// In en, this message translates to:
  /// **'the heavier cut — the default'**
  String get fontBookSubtitle;

  /// No description provided for @fontPlusSubtitle.
  ///
  /// In en, this message translates to:
  /// **'the lighter companion cut'**
  String get fontPlusSubtitle;

  /// No description provided for @fontLiterataSubtitle.
  ///
  /// In en, this message translates to:
  /// **'designed for e-reading — larger x-height'**
  String get fontLiterataSubtitle;

  /// No description provided for @typefaceChangeFailed.
  ///
  /// In en, this message translates to:
  /// **'Typeface change failed: {error}'**
  String typefaceChangeFailed(String error);

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @sectionSync.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get sectionSync;

  /// No description provided for @syncedFolder.
  ///
  /// In en, this message translates to:
  /// **'Synced folder'**
  String get syncedFolder;

  /// No description provided for @syncOffSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Off — point gramma at a folder your cloud provider or sync agent keeps in sync, or connect Dropbox directly. Desks and reading positions flow between your devices; texts never leave this device.'**
  String get syncOffSubtitle;

  /// No description provided for @syncDropboxSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Dropbox — direct connection, no local client. Op-logs live under Apps in your Dropbox.'**
  String get syncDropboxSubtitle;

  /// No description provided for @connectDropbox.
  ///
  /// In en, this message translates to:
  /// **'Connect Dropbox…'**
  String get connectDropbox;

  /// No description provided for @useICloud.
  ///
  /// In en, this message translates to:
  /// **'Use iCloud Drive'**
  String get useICloud;

  /// No description provided for @chooseFolder.
  ///
  /// In en, this message translates to:
  /// **'Choose folder…'**
  String get chooseFolder;

  /// No description provided for @enterPath.
  ///
  /// In en, this message translates to:
  /// **'Enter path…'**
  String get enterPath;

  /// No description provided for @syncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get syncNow;

  /// No description provided for @disable.
  ///
  /// In en, this message translates to:
  /// **'Disable'**
  String get disable;

  /// No description provided for @syncDisabled.
  ///
  /// In en, this message translates to:
  /// **'Sync disabled'**
  String get syncDisabled;

  /// No description provided for @syncEnabledPulled.
  ///
  /// In en, this message translates to:
  /// **'Sync enabled — {count, plural, =0{no changes yet} one{1 change pulled} other{{count} changes pulled}}'**
  String syncEnabledPulled(int count);

  /// No description provided for @folderNotUsable.
  ///
  /// In en, this message translates to:
  /// **'Folder not usable: {error}'**
  String folderNotUsable(String error);

  /// No description provided for @alreadyUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Already up to date'**
  String get alreadyUpToDate;

  /// No description provided for @changesPulled.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 change pulled} other{{count} changes pulled}}'**
  String changesPulled(int count);

  /// No description provided for @syncPathTitle.
  ///
  /// In en, this message translates to:
  /// **'Synced folder path'**
  String get syncPathTitle;

  /// No description provided for @useFolder.
  ///
  /// In en, this message translates to:
  /// **'Use folder'**
  String get useFolder;

  /// No description provided for @icloudUnavailable.
  ///
  /// In en, this message translates to:
  /// **'iCloud is not available — check that iCloud Drive is enabled for this device'**
  String get icloudUnavailable;

  /// No description provided for @icloudNoContainer.
  ///
  /// In en, this message translates to:
  /// **'No gramma iCloud container yet — open gramma on your iPhone or iPad once, then try again'**
  String get icloudNoContainer;

  /// No description provided for @dropboxConnectTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect Dropbox'**
  String get dropboxConnectTitle;

  /// No description provided for @dropboxIntro.
  ///
  /// In en, this message translates to:
  /// **'Create a free \"Scoped access\" app with \"App folder\" access at dropbox.com/developers/apps and paste its app key. gramma will only ever see its own app folder.'**
  String get dropboxIntro;

  /// No description provided for @appKey.
  ///
  /// In en, this message translates to:
  /// **'App key'**
  String get appKey;

  /// No description provided for @dropboxStep1.
  ///
  /// In en, this message translates to:
  /// **'1. Open this link in a browser and allow access:'**
  String get dropboxStep1;

  /// No description provided for @dropboxStep2.
  ///
  /// In en, this message translates to:
  /// **'2. Paste the code Dropbox shows:'**
  String get dropboxStep2;

  /// No description provided for @accessCode.
  ///
  /// In en, this message translates to:
  /// **'Access code'**
  String get accessCode;

  /// No description provided for @connecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get connecting;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @dropboxConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Dropbox connection failed: {error}'**
  String dropboxConnectionFailed(String error);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

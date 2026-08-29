// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get cancel => 'Cancel';

  @override
  String get apply => 'Apply';

  @override
  String get close => 'Close';

  @override
  String get open => 'Open';

  @override
  String get delete => 'Delete';

  @override
  String get keep => 'Keep';

  @override
  String get rename => 'Rename';

  @override
  String get today => 'Today';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get toolsTooltip => 'Tools';

  @override
  String get readingPlan => 'Reading plan';

  @override
  String desksTooltip(String name) {
    return 'Desks — $name';
  }

  @override
  String get newDesk => 'New desk';

  @override
  String get renameDeskMenu => 'Rename desk…';

  @override
  String get deleteDeskMenu => 'Delete desk…';

  @override
  String get renameDeskTitle => 'Rename desk';

  @override
  String deleteDeskTitle(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get deleteDeskBody =>
      'The desk and its view arrangement are removed on every synced device. Your texts and reading history stay.';

  @override
  String get deskDefaultPrefix => 'Desk';

  @override
  String get addViewTooltip => 'Add view';

  @override
  String get textView => 'Text view';

  @override
  String get footnotesView => 'Footnotes view';

  @override
  String get commentaryView => 'Commentary view';

  @override
  String get dictionaryView => 'Dictionary view';

  @override
  String get bookView => 'Book view';

  @override
  String get devotionalView => 'Devotional view';

  @override
  String get settingsTooltip => 'Settings';

  @override
  String get importOsisTooltip => 'Import module…';

  @override
  String importedModule(String title, int verses) {
    return 'Imported $title ($verses verses)';
  }

  @override
  String importFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String get unlinked => 'Unlinked';

  @override
  String get closeView => 'Close view';

  @override
  String get back => 'Back';

  @override
  String get forward => 'Forward';

  @override
  String get history => 'History';

  @override
  String get viewMenuTooltip => 'View menu';

  @override
  String get footnotesTitle => 'Footnotes';

  @override
  String get commentaryTitle => 'Commentary';

  @override
  String get dictionaryTitle => 'Dictionary';

  @override
  String get bookTitle => 'Book';

  @override
  String get devotionalTitle => 'Devotional';

  @override
  String get selectorTooltip => 'Select book, chapter, verse';

  @override
  String get linkFootnotesHint =>
      'Link this view to a text view to see its footnotes';

  @override
  String get noFootnotes => 'No footnotes in view';

  @override
  String get linkCommentaryHint =>
      'Link this view to a text view to see the commentary on its passage';

  @override
  String get noCommentary => 'No commentary in view';

  @override
  String get noCommentaryModules =>
      'Import a commentary (a SWORD zip package) to use this view';

  @override
  String importedCommentary(String title, int entries) {
    return 'Imported $title ($entries entries)';
  }

  @override
  String importedDictionary(String title, int entries) {
    return 'Imported $title ($entries entries)';
  }

  @override
  String get noBookModules =>
      'Import a book (a SWORD zip package) to use this view';

  @override
  String get noDevotionalModules =>
      'Import a daily devotional (a SWORD zip package) to use this view';

  @override
  String get tableOfContents => 'Table of contents';

  @override
  String importedPlan(String name, int days) {
    return 'Imported reading plan $name ($days days)';
  }

  @override
  String importedBook(String title, int entries) {
    return 'Imported $title ($entries sections)';
  }

  @override
  String importedDevotional(String title, int entries) {
    return 'Imported $title ($entries readings)';
  }

  @override
  String get noDictionaryModules =>
      'Import a dictionary (a SWORD zip package) to use this view';

  @override
  String get searchDictionaryHint =>
      'Search by Strong\'s number or word — or long-press a word in the text';

  @override
  String get dictionarySearchLabel => 'Number or word';

  @override
  String get noDictionaryResults => 'No matches';

  @override
  String get searchTool => 'Search';

  @override
  String get searchQueryHint => 'Search the text…';

  @override
  String get goodHit => 'Good hit — save as training example';

  @override
  String get noGoodHit => 'No good hit';

  @override
  String get labelRecorded => 'Saved as training example';

  @override
  String get markSelection => 'Mark / note';

  @override
  String get noteHint => 'Note (optional — empty saves just the mark)';

  @override
  String get deleteNote => 'Delete';

  @override
  String get save => 'Save';

  @override
  String get exportLabels => 'Export training labels…';

  @override
  String get noLabelsYet => 'No training labels collected yet';

  @override
  String get strongsTagged => 'Strong\'s numbers';

  @override
  String get noConcordanceSource =>
      'Import a Strong\'s-tagged Bible (e.g. the KJV) to see occurrences';

  @override
  String get importToBegin => 'Import an OSIS module to begin reading';

  @override
  String passageNotAvailable(String module) {
    return 'Passage not available in $module';
  }

  @override
  String planDay(String name, int day) {
    return '$name — Day $day';
  }

  @override
  String get todaysReadings => 'Today\'s readings';

  @override
  String get sectionReading => 'Reading';

  @override
  String get textSize => 'Text size';

  @override
  String pxColumnLabel(int px) {
    return '$px px column';
  }

  @override
  String get footnoteTextSize => 'Footnote text size';

  @override
  String get previewTextSize => 'Preview text size';

  @override
  String get commentaryTextSize => 'Commentary text size';

  @override
  String get lineSpacing => 'Line spacing';

  @override
  String lineSpacingLabel(String v) {
    return '$v × font size';
  }

  @override
  String get columnTurnEffort => 'Column turn effort';

  @override
  String columnAdvanceLabel(int p) {
    return '$p% of a column';
  }

  @override
  String get defaultText => 'Default text';

  @override
  String get defaultTextSubtitle => 'Used to resolve references in previews.';

  @override
  String get firstModule => 'First module';

  @override
  String get sectionAppearance => 'Appearance';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get tone => 'Tone';

  @override
  String get fontWeightLightMode => 'Font weight · light mode';

  @override
  String get fontWeightDarkMode => 'Font weight · dark mode';

  @override
  String get weightNatural => 'natural';

  @override
  String get keepScreenOn => 'Keep the screen on';

  @override
  String get keepScreenOnSubtitle => 'The display never sleeps while reading';

  @override
  String get notesTitle => 'Notes';

  @override
  String get noNotesYet =>
      'No marks or notes yet — long-press a word in the text to begin.';

  @override
  String get pureMark => 'Mark';

  @override
  String get trueBlack => 'True black in dark mode';

  @override
  String get trueBlackSubtitle =>
      'Keep the background fully black; contrast dims only the text.';

  @override
  String get contrast => 'Contrast';

  @override
  String get sectionTypesetting => 'Typesetting';

  @override
  String get typeface => 'Typeface';

  @override
  String get changeEllipsis => 'Change…';

  @override
  String get lineWidth => 'Line width';

  @override
  String lineWidthSubtitle(int ems, int chars) {
    return '$ems em — about $chars characters per line. Fixed so the visual shape of the text stays familiar on every page and device.';
  }

  @override
  String get measureDialogTitle => 'Change line width?';

  @override
  String get measureDialogBody =>
      'The line width determines where every line of text breaks. Changing it re-typesets everything — the familiar visual shape of pages you have read will change. This setting is meant to be chosen once and kept.';

  @override
  String get keepCurrent => 'Keep current';

  @override
  String get understandChange => 'I understand, change it';

  @override
  String get typefaceDialogTitle => 'Change typeface?';

  @override
  String get typefaceDialogBody =>
      'The typeface defines where every line of text breaks. Changing it re-typesets everything — the familiar visual shape of pages you have read will change.';

  @override
  String get fontBookSubtitle => 'the heavier cut — the default';

  @override
  String get fontPlusSubtitle => 'the lighter companion cut';

  @override
  String get fontLiterataSubtitle => 'designed for e-reading — larger x-height';

  @override
  String typefaceChangeFailed(String error) {
    return 'Typeface change failed: $error';
  }

  @override
  String get language => 'Language';

  @override
  String get sectionSync => 'Sync';

  @override
  String get syncedFolder => 'Synced folder';

  @override
  String get syncOffSubtitle =>
      'Off — point gramma at a folder your cloud provider or sync agent keeps in sync, or connect Dropbox directly. Desks and reading positions flow between your devices; texts never leave this device.';

  @override
  String get syncDropboxSubtitle =>
      'Dropbox — direct connection, no local client. Op-logs live under Apps in your Dropbox.';

  @override
  String get connectDropbox => 'Connect Dropbox…';

  @override
  String get useICloud => 'Use iCloud Drive';

  @override
  String get chooseFolder => 'Choose folder…';

  @override
  String get enterPath => 'Enter path…';

  @override
  String get syncNow => 'Sync now';

  @override
  String get disable => 'Disable';

  @override
  String get syncDisabled => 'Sync disabled';

  @override
  String syncEnabledPulled(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes pulled',
      one: '1 change pulled',
      zero: 'no changes yet',
    );
    return 'Sync enabled — $_temp0';
  }

  @override
  String folderNotUsable(String error) {
    return 'Folder not usable: $error';
  }

  @override
  String get alreadyUpToDate => 'Already up to date';

  @override
  String changesPulled(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes pulled',
      one: '1 change pulled',
    );
    return '$_temp0';
  }

  @override
  String get syncPathTitle => 'Synced folder path';

  @override
  String get useFolder => 'Use folder';

  @override
  String get icloudUnavailable =>
      'iCloud is not available — check that iCloud Drive is enabled for this device';

  @override
  String get icloudNoContainer =>
      'No gramma iCloud container yet — open gramma on your iPhone or iPad once, then try again';

  @override
  String get dropboxConnectTitle => 'Connect Dropbox';

  @override
  String get dropboxIntro =>
      'Create a free \"Scoped access\" app with \"App folder\" access at dropbox.com/developers/apps and paste its app key. gramma will only ever see its own app folder.';

  @override
  String get appKey => 'App key';

  @override
  String get dropboxStep1 => '1. Open this link in a browser and allow access:';

  @override
  String get dropboxStep2 => '2. Paste the code Dropbox shows:';

  @override
  String get accessCode => 'Access code';

  @override
  String get connecting => 'Connecting…';

  @override
  String get connect => 'Connect';

  @override
  String dropboxConnectionFailed(String error) {
    return 'Dropbox connection failed: $error';
  }
}

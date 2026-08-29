// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get cancel => 'Abbrechen';

  @override
  String get apply => 'Übernehmen';

  @override
  String get close => 'Schließen';

  @override
  String get open => 'Öffnen';

  @override
  String get delete => 'Löschen';

  @override
  String get keep => 'Behalten';

  @override
  String get rename => 'Umbenennen';

  @override
  String get today => 'Heute';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get toolsTooltip => 'Werkzeuge';

  @override
  String get readingPlan => 'Leseplan';

  @override
  String desksTooltip(String name) {
    return 'Schreibtische — $name';
  }

  @override
  String get newDesk => 'Neuer Schreibtisch';

  @override
  String get renameDeskMenu => 'Schreibtisch umbenennen…';

  @override
  String get deleteDeskMenu => 'Schreibtisch löschen…';

  @override
  String get renameDeskTitle => 'Schreibtisch umbenennen';

  @override
  String deleteDeskTitle(String name) {
    return '„$name“ löschen?';
  }

  @override
  String get deleteDeskBody =>
      'Der Schreibtisch und seine Ansichten werden auf allen synchronisierten Geräten entfernt. Deine Texte und dein Verlauf bleiben erhalten.';

  @override
  String get deskDefaultPrefix => 'Schreibtisch';

  @override
  String get addViewTooltip => 'Ansicht hinzufügen';

  @override
  String get textView => 'Textansicht';

  @override
  String get footnotesView => 'Fußnotenansicht';

  @override
  String get commentaryView => 'Kommentaransicht';

  @override
  String get dictionaryView => 'Wörterbuchansicht';

  @override
  String get bookView => 'Buchansicht';

  @override
  String get devotionalView => 'Andachtsansicht';

  @override
  String get settingsTooltip => 'Einstellungen';

  @override
  String get importOsisTooltip => 'Modul importieren…';

  @override
  String importedModule(String title, int verses) {
    return '$title importiert ($verses Verse)';
  }

  @override
  String importFailed(String error) {
    return 'Import fehlgeschlagen: $error';
  }

  @override
  String get unlinked => 'Nicht verknüpft';

  @override
  String get closeView => 'Ansicht schließen';

  @override
  String get back => 'Zurück';

  @override
  String get forward => 'Vorwärts';

  @override
  String get history => 'Verlauf';

  @override
  String get viewMenuTooltip => 'Ansichtsmenü';

  @override
  String get footnotesTitle => 'Fußnoten';

  @override
  String get commentaryTitle => 'Kommentar';

  @override
  String get dictionaryTitle => 'Wörterbuch';

  @override
  String get bookTitle => 'Buch';

  @override
  String get devotionalTitle => 'Andacht';

  @override
  String get selectorTooltip => 'Buch, Kapitel, Vers wählen';

  @override
  String get linkFootnotesHint =>
      'Verknüpfe diese Ansicht mit einer Textansicht, um deren Fußnoten zu sehen';

  @override
  String get noFootnotes => 'Keine Fußnoten im sichtbaren Bereich';

  @override
  String get linkCommentaryHint =>
      'Verknüpfe diese Ansicht mit einer Textansicht, um den Kommentar zur Passage zu sehen';

  @override
  String get noCommentary => 'Kein Kommentar im sichtbaren Bereich';

  @override
  String get noCommentaryModules =>
      'Importiere einen Kommentar (SWORD-Zip-Paket), um diese Ansicht zu nutzen';

  @override
  String importedCommentary(String title, int entries) {
    return '$title importiert ($entries Abschnitte)';
  }

  @override
  String importedDictionary(String title, int entries) {
    return '$title importiert ($entries Einträge)';
  }

  @override
  String get noBookModules =>
      'Importiere ein Buch (SWORD-Zip-Paket), um diese Ansicht zu nutzen';

  @override
  String get noDevotionalModules =>
      'Importiere eine Tagesandacht (SWORD-Zip-Paket), um diese Ansicht zu nutzen';

  @override
  String get tableOfContents => 'Inhaltsverzeichnis';

  @override
  String importedPlan(String name, int days) {
    return 'Leseplan $name importiert ($days Tage)';
  }

  @override
  String importedBook(String title, int entries) {
    return '$title importiert ($entries Abschnitte)';
  }

  @override
  String importedDevotional(String title, int entries) {
    return '$title importiert ($entries Andachten)';
  }

  @override
  String get noDictionaryModules =>
      'Importiere ein Wörterbuch (SWORD-Zip-Paket), um diese Ansicht zu nutzen';

  @override
  String get searchDictionaryHint =>
      'Suche nach Strong-Nummer oder Wort – oder halte ein Wort im Text gedrückt';

  @override
  String get dictionarySearchLabel => 'Nummer oder Wort';

  @override
  String get noDictionaryResults => 'Keine Treffer';

  @override
  String get searchTool => 'Suche';

  @override
  String get searchQueryHint => 'Im Text suchen…';

  @override
  String get goodHit => 'Guter Treffer – als Trainingsbeispiel speichern';

  @override
  String get noGoodHit => 'Kein guter Treffer';

  @override
  String get labelRecorded => 'Als Trainingsbeispiel gespeichert';

  @override
  String get markSelection => 'Markieren / Notiz';

  @override
  String get noteHint => 'Notiz (optional – leer speichert nur die Markierung)';

  @override
  String get deleteNote => 'Löschen';

  @override
  String get save => 'Speichern';

  @override
  String get exportLabels => 'Trainingslabels exportieren…';

  @override
  String get noLabelsYet => 'Noch keine Trainingslabels gesammelt';

  @override
  String get strongsTagged => 'Strong-Nummern';

  @override
  String get noConcordanceSource =>
      'Importiere eine Bibel mit Strong-Nummern (z. B. die KJV), um Vorkommen zu sehen';

  @override
  String get importToBegin =>
      'Importiere ein OSIS-Modul, um mit dem Lesen zu beginnen';

  @override
  String passageNotAvailable(String module) {
    return 'Textstelle in $module nicht verfügbar';
  }

  @override
  String planDay(String name, int day) {
    return '$name — Tag $day';
  }

  @override
  String get todaysReadings => 'Heutige Leseabschnitte';

  @override
  String get sectionReading => 'Lesen';

  @override
  String get textSize => 'Textgröße';

  @override
  String pxColumnLabel(int px) {
    return '$px px Spalte';
  }

  @override
  String get footnoteTextSize => 'Fußnoten-Textgröße';

  @override
  String get previewTextSize => 'Vorschau-Textgröße';

  @override
  String get commentaryTextSize => 'Kommentar-Textgröße';

  @override
  String get lineSpacing => 'Zeilenabstand';

  @override
  String lineSpacingLabel(String v) {
    return '$v × Schriftgröße';
  }

  @override
  String get columnTurnEffort => 'Spaltenwechsel-Widerstand';

  @override
  String columnAdvanceLabel(int p) {
    return '$p% einer Spalte';
  }

  @override
  String get defaultText => 'Standardtext';

  @override
  String get defaultTextSubtitle => 'Für Verweise in Vorschauen verwendet.';

  @override
  String get firstModule => 'Erstes Modul';

  @override
  String get sectionAppearance => 'Erscheinungsbild';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Hell';

  @override
  String get themeDark => 'Dunkel';

  @override
  String get tone => 'Farbton';

  @override
  String get fontWeightLightMode => 'Strichstärke · helles Design';

  @override
  String get fontWeightDarkMode => 'Strichstärke · dunkles Design';

  @override
  String get weightNatural => 'natürlich';

  @override
  String get keepScreenOn => 'Bildschirm anlassen';

  @override
  String get keepScreenOnSubtitle => 'Das Display schläft beim Lesen nie ein';

  @override
  String get trueBlack => 'Echtes Schwarz im dunklen Design';

  @override
  String get trueBlackSubtitle =>
      'Hintergrund bleibt tiefschwarz; der Kontrastregler dimmt nur den Text.';

  @override
  String get contrast => 'Kontrast';

  @override
  String get sectionTypesetting => 'Satz';

  @override
  String get typeface => 'Schriftart';

  @override
  String get changeEllipsis => 'Ändern…';

  @override
  String get lineWidth => 'Zeilenbreite';

  @override
  String lineWidthSubtitle(int ems, int chars) {
    return '$ems em — etwa $chars Zeichen pro Zeile. Fest, damit das Schriftbild auf jeder Seite und jedem Gerät vertraut bleibt.';
  }

  @override
  String get measureDialogTitle => 'Zeilenbreite ändern?';

  @override
  String get measureDialogBody =>
      'Die Zeilenbreite bestimmt, wo jede Textzeile umbricht. Eine Änderung setzt alles neu — das vertraute Schriftbild bereits gelesener Seiten ändert sich. Diese Einstellung ist dafür gedacht, einmal gewählt und dann beibehalten zu werden.';

  @override
  String get keepCurrent => 'Aktuelle behalten';

  @override
  String get understandChange => 'Ich verstehe — ändern';

  @override
  String get typefaceDialogTitle => 'Schriftart ändern?';

  @override
  String get typefaceDialogBody =>
      'Die Schriftart bestimmt, wo jede Textzeile umbricht. Eine Änderung setzt alles neu — das vertraute Schriftbild bereits gelesener Seiten ändert sich.';

  @override
  String get fontBookSubtitle => 'der kräftigere Schnitt — Standard';

  @override
  String get fontPlusSubtitle => 'der leichtere Schwesterschnitt';

  @override
  String get fontLiterataSubtitle =>
      'fürs Lesen am Bildschirm entworfen — größere x-Höhe';

  @override
  String typefaceChangeFailed(String error) {
    return 'Schriftartwechsel fehlgeschlagen: $error';
  }

  @override
  String get language => 'Sprache';

  @override
  String get sectionSync => 'Synchronisierung';

  @override
  String get syncedFolder => 'Synchronisierter Ordner';

  @override
  String get syncOffSubtitle =>
      'Aus — verbinde gramma mit einem Ordner, den dein Cloud-Anbieter oder Sync-Dienst synchron hält, oder verbinde Dropbox direkt. Schreibtische und Lesepositionen fließen zwischen deinen Geräten; Texte verlassen dieses Gerät nie.';

  @override
  String get syncDropboxSubtitle =>
      'Dropbox — direkte Verbindung, kein lokaler Client. Die Op-Logs liegen unter Apps in deiner Dropbox.';

  @override
  String get connectDropbox => 'Dropbox verbinden…';

  @override
  String get useICloud => 'iCloud Drive verwenden';

  @override
  String get chooseFolder => 'Ordner wählen…';

  @override
  String get enterPath => 'Pfad eingeben…';

  @override
  String get syncNow => 'Jetzt synchronisieren';

  @override
  String get disable => 'Deaktivieren';

  @override
  String get syncDisabled => 'Synchronisierung deaktiviert';

  @override
  String syncEnabledPulled(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Änderungen übernommen',
      one: '1 Änderung übernommen',
      zero: 'noch keine Änderungen',
    );
    return 'Synchronisierung aktiv — $_temp0';
  }

  @override
  String folderNotUsable(String error) {
    return 'Ordner nicht nutzbar: $error';
  }

  @override
  String get alreadyUpToDate => 'Bereits aktuell';

  @override
  String changesPulled(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Änderungen übernommen',
      one: '1 Änderung übernommen',
    );
    return '$_temp0';
  }

  @override
  String get syncPathTitle => 'Pfad des synchronisierten Ordners';

  @override
  String get useFolder => 'Ordner verwenden';

  @override
  String get icloudUnavailable =>
      'iCloud ist nicht verfügbar — prüfe, ob iCloud Drive für dieses Gerät aktiviert ist';

  @override
  String get icloudNoContainer =>
      'Noch kein gramma-iCloud-Container — öffne gramma einmal auf deinem iPhone oder iPad und versuche es dann erneut';

  @override
  String get dropboxConnectTitle => 'Dropbox verbinden';

  @override
  String get dropboxIntro =>
      'Lege unter dropbox.com/developers/apps eine kostenlose App mit „Scoped access“ und „App folder“-Zugriff an und füge ihren App-Schlüssel ein. gramma sieht ausschließlich seinen eigenen App-Ordner.';

  @override
  String get appKey => 'App-Schlüssel';

  @override
  String get dropboxStep1 =>
      '1. Öffne diesen Link im Browser und erlaube den Zugriff:';

  @override
  String get dropboxStep2 => '2. Füge den von Dropbox angezeigten Code ein:';

  @override
  String get accessCode => 'Zugriffscode';

  @override
  String get connecting => 'Verbinde…';

  @override
  String get connect => 'Verbinden';

  @override
  String dropboxConnectionFailed(String error) {
    return 'Dropbox-Verbindung fehlgeschlagen: $error';
  }
}

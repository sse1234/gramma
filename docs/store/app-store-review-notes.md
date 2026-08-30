# App Review notes · reply to the information request

Paste into the App Review Information → Notes field / reply thread.
Attach the screen recording as item 1.

---

1. SCREEN RECORDING: The attached recording, captured on a physical
   Mac running the latest macOS, begins at app launch (fresh
   installation) and shows the typical flow: importing a Bible module,
   reading, opening a second linked translation side by side, looking
   up a word in the Strong's dictionary, creating a color mark with a
   note, and the notes overview. The app has NO account system — no
   registration, no login, no account deletion — no paid content, no
   subscriptions, no user-generated content shared with anyone (notes
   stay on device), and it requests no sensitive-data or device
   permissions, so none of these flows exist to record.

2. TESTED ON: MacBook (Apple silicon) with the latest macOS; iPhone
   15 Pro Max and iPad Pro 11" (M2) with the latest iOS/iPadOS; iPad
   Pro 13" simulator. Automated test suite runs on every commit
   (github.com/sse1234/gramma).

3. WHAT THE APP IS: gramma is a Bible study app for readers who want
   book-quality typography. It typesets Scripture with a TeX-style
   line-breaking engine, shows translations and commentaries side by
   side in synchronized views, and offers study tools (Strong's
   dictionaries, concordance, search, reading plans, notes and color
   marks). Target audience: anyone reading and studying the Bible,
   German- and English-speaking. It is completely free, open source
   (MIT), with no ads, analytics, accounts, or purchases.

4. SETUP: The app ships without Bible texts (licensing is the
   users' own responsibility; public-domain modules are freely
   available). To try it: open Settings → Import (or the import
   action in the toolbar), and choose any SWORD module zip from the
   CrossWire Bible Society, e.g. the public-domain King James
   Version: https://www.crosswire.org/ftpmirror/pub/sword/packages/rawzip/KJV.zip
   Download that file, import it, and every feature is available
   offline. No credentials are needed anywhere in the app.

5. EXTERNAL SERVICES: None. The app runs fully offline and operates
   no server. The optional device-to-device sync writes end-to-end-
   encrypted files into a folder the user chooses (e.g. their own
   iCloud Drive); the app never transmits data to us or any third
   party. No authentication services, payment processors, data
   providers, or AI services are used.

6. REGIONAL DIFFERENCES: None. The app functions identically in all
   regions; the UI is localized in English and German.

7. REGULATED INDUSTRY / PROTECTED MATERIAL: Not applicable. The app
   ships no third-party content whatsoever. Users import modules
   they have the right to use, exactly like a document viewer opens
   the user's own files. The app itself is open source under the MIT
   license: https://github.com/sse1234/gramma

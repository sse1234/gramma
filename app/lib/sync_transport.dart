import 'dropbox_sync.dart';
import 'icloud.dart';
import 'src/rust/api/user.dart';

/// One full pull cycle across whatever transport is active (ADR 0014):
/// platform preparation (iCloud placeholder downloads), the Dropbox
/// mirror when connected, then the engine's own sync_now — followed by
/// pushing the own log back out. Never throws: sync trouble must not
/// disturb reading.
Future<List<String>> pullSync() async {
  try {
    final dir = syncDir();
    if (dir == null) return const [];
    await icloudPrepare(dir);
    final dropbox = activeDropbox;
    if (dropbox != null) {
      await dropbox.pullForeign();
    }
    // sync_now also self-heals offline writes into the own log, so the
    // push must come after it.
    final changed = syncNow();
    if (dropbox != null) {
      await dropbox.pushOwn();
    }
    return changed;
  } catch (_) {
    return const [];
  }
}
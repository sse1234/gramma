import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show decodeImageFromList;

import 'src/rust/api/typeset.dart';

/// Decoded figures of imported documents (ADR 0029), by module and image
/// index, loaded on demand through the bridge and kept for the pane's
/// lifetime. Listeners repaint when an image arrives.
class ModuleImages extends ChangeNotifier {
  final Map<String, Map<int, ui.Image>> _images = {};
  final Set<String> _pending = {};

  Map<int, ui.Image> of(String module) => _images[module] ?? const {};

  /// Start loading every index not yet present.
  void ensure(String module, Iterable<int> indices) {
    for (final index in indices) {
      final key = '$module/$index';
      if (_pending.contains(key) ||
          (_images[module]?.containsKey(index) ?? false)) {
        continue;
      }
      _pending.add(key);
      moduleImage(moduleCode: module, index: index)
          .then((view) async {
            if (view == null) return;
            final image = await decodeImageFromList(view.data);
            _images.putIfAbsent(module, () => {})[index] = image;
            notifyListeners();
          })
          .catchError((_) {})
          .whenComplete(() => _pending.remove(key));
    }
  }

  @override
  void dispose() {
    for (final images in _images.values) {
      for (final image in images.values) {
        image.dispose();
      }
    }
    super.dispose();
  }
}

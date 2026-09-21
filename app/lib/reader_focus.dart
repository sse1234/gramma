import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keyboard ownership of the text views (ADR 0028): the arrow keys page
/// the view acted in last — clicked, dragged, or scrolled — and a press
/// is never spent on focusing.
class ReaderFocus {
  ReaderFocus({required this.onStep, required this.isCurrent}) {
    node.addListener(_changed);
  }

  /// Pages the owning view by whole columns.
  final void Function(int steps) onStep;

  /// Whether the owning view is still mounted and its route is on top.
  final bool Function() isCurrent;

  final FocusNode node = FocusNode(debugLabel: 'reader-pane');

  /// The view that owns the keyboard.
  static ReaderFocus? _lastActive;

  /// Takes the keyboard now — a pointer down or a wheel in the view.
  void claim() => node.requestFocus();

  /// Takes the keyboard after the first frame unless something has it:
  /// the first text view owns the keyboard from the start, so the very
  /// first arrow press pages.
  void claimAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isCurrent() && !node.hasFocus) node.requestFocus();
    });
  }

  /// Arrow keys page; anything else passes.
  KeyEventResult handle(KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      onStep(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      onStep(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Arrow keys that reach the screen unhandled — focus sitting on a
  /// toolbar button, or nowhere after a menu closed — page the view that
  /// last owned the keyboard and give it the keyboard back. Keys typed
  /// into a text field are left to the field.
  static KeyEventResult handleStray(KeyEvent event) {
    final focus = _lastActive;
    if (focus == null || !focus.isCurrent()) return KeyEventResult.ignored;
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }
    final result = focus.handle(event);
    if (result == KeyEventResult.handled) focus.node.requestFocus();
    return result;
  }

  /// Focus gained makes this the keyboard's view. Focus lost to nowhere —
  /// a closed menu, a rebuilt toolbar — is taken back after the frame, so
  /// the next arrow press pages instead of being spent on focusing. Focus
  /// on a real widget (a field, a button) is left alone.
  void _changed() {
    if (node.hasFocus) {
      _lastActive = this;
      return;
    }
    if (_lastActive != this) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_lastActive != this || !isCurrent()) return;
      if (FocusManager.instance.primaryFocus is FocusScopeNode) {
        node.requestFocus();
      }
    });
  }

  void dispose() {
    if (_lastActive == this) _lastActive = null;
    node.removeListener(_changed);
    node.dispose();
  }
}

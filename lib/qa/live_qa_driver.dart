import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'qa_scenario.dart';

/// What kind of thing a recorded step was, so the dashboard can style it.
enum QaStepKind { phase, action, assertion }

enum QaStepStatus { running, passed, failed }

/// One line of the live step log.
class QaStep {
  QaStep({required this.label, required this.kind});

  final String label;
  final QaStepKind kind;
  QaStepStatus status = QaStepStatus.running;
  String? failure;
}

/// How the driver waits: for the UI to come to rest, and for the deliberate
/// pauses that make a run watchable.
///
/// This is injectable because waiting is the one thing that differs between a
/// live app and a test: a running app advances on a real clock and real frames,
/// while `flutter test` fakes both and only advances when the tester pumps.
/// Isolating it here lets [LiveQaDriver] itself — the lookups, the pointer
/// dispatch, the assertions — be covered by `test/qa_live_driver_test.dart`.
abstract class QaPacer {
  Future<void> settle();

  Future<void> pause(Duration duration);
}

/// The real-app pacer: real frames, real clock.
class LiveQaPacer implements QaPacer {
  const LiveQaPacer();

  /// A live app has no `pumpAndSettle`, so this pumps a few frames and leaves a
  /// grace period for async work (futures, fake Firestore reads) to land.
  @override
  Future<void> settle() async {
    final binding = WidgetsBinding.instance;
    for (var i = 0; i < 3; i++) {
      await binding.endOfFrame;
    }
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await binding.endOfFrame;
  }

  @override
  Future<void> pause(Duration duration) => Future<void>.delayed(duration);
}

/// Runs a [QaScenario] inside the *running* app rather than under
/// `flutter test`.
///
/// A widget test drives a [WidgetTester], which only exists under
/// `TestWidgetsFlutterBinding` — that binding replaces the app's own binding at
/// startup, so it can never be used from a live app. Instead this driver works
/// directly against the real element tree: it locates widgets by walking
/// elements from the stage root, and taps them by dispatching genuine pointer
/// events through [GestureBinding]. That means no `flutter_test` dependency is
/// pulled into the app, and what you watch on screen is the production widget
/// responding to real hit-tested taps.
///
/// Everything is deliberately paced ([stepDelay]) and each target is
/// highlighted before it is acted on, because the point of this runner is to be
/// watched.
class LiveQaDriver implements QaDriver {
  LiveQaDriver({
    required this.root,
    required this.onUpdate,
    required this.onHighlight,
    required this.stepDelay,
    this.isExcluded,
    this.beforeStep,
    this.pacer = const LiveQaPacer(),
  });

  /// Scopes every lookup to the subtree under [stageKey]. Kept for the driver's
  /// own tests (`test/qa_live_driver_test.dart`), which mount a widget inside a
  /// keyed subtree and drive it — the way the old embedded "stage" worked.
  LiveQaDriver.scopedTo(
    GlobalKey stageKey, {
    required this.onUpdate,
    required this.onHighlight,
    required this.stepDelay,
    this.pacer = const LiveQaPacer(),
  })  : root = (() {
          final context = stageKey.currentContext;
          return context is Element ? context : null;
        }),
        isExcluded = null,
        beforeStep = null;

  /// Resolves the element to search from. The live-app runner returns the app
  /// root (`WidgetsBinding.instance.rootElement`); [LiveQaDriver.scopedTo]
  /// returns a stage subtree. Returning null (nothing mounted yet) yields no
  /// matches rather than throwing.
  final Element? Function() root;

  /// Optional filter that prunes a subtree from the element walk: return true to
  /// skip [element] and all of its descendants. The live-app runner passes
  /// `QaChrome.matches` so its own PiP/highlight overlay never matches a lookup.
  final bool Function(Element element)? isExcluded;

  /// Optional gate awaited at the start of every action/assertion step, after
  /// the step is logged but before it runs. In a normal run it is null; in a
  /// "Debug" (step-through) run the runner uses it to pause until the user
  /// presses Continue.
  final Future<void> Function()? beforeStep;

  /// Called whenever [steps] changes, so the dashboard can repaint the log.
  final VoidCallback onUpdate;

  /// Paints (or clears, when null) the highlight over the widget being acted
  /// on. The rect is in global coordinates.
  final void Function(Rect? globalRect) onHighlight;

  /// Read fresh before every step so the speed control takes effect mid-run.
  final Duration Function() stepDelay;

  /// How to wait. Defaults to real frames and a real clock.
  final QaPacer pacer;

  final List<QaStep> steps = <QaStep>[];

  int _pointer = 0;

  /// How long an assertion keeps re-checking before giving up. A live app has
  /// no `pumpAndSettle`, so instead of guessing a fixed wait, assertions poll —
  /// which absorbs the async loads (e.g. a fake Firestore read) that a widget
  /// test would have settled synchronously.
  static const Duration _assertionTimeout = Duration(seconds: 3);
  static const Duration _pollInterval = Duration(milliseconds: 50);

  // ---- Step bookkeeping -----------------------------------------------------

  Future<void> _step(
    QaStepKind kind,
    String label,
    Future<void> Function() body,
  ) async {
    final step = QaStep(label: label, kind: kind);
    steps.add(step);
    onUpdate();

    // In a step-through run, block here (with the step already shown as pending)
    // until the user presses Continue.
    if (beforeStep != null) await beforeStep!();

    // Pause *before* acting so a watcher can read the step and see the
    // highlight land before the UI changes underneath them.
    await pacer.pause(stepDelay());

    try {
      await body();
      step.status = QaStepStatus.passed;
    } on QaScenarioFailure catch (e) {
      step.status = QaStepStatus.failed;
      step.failure = e.message;
      onUpdate();
      rethrow;
    } catch (e) {
      step.status = QaStepStatus.failed;
      step.failure = e.toString();
      onUpdate();
      rethrow;
    } finally {
      onUpdate();
    }
  }

  // ---- Element lookup -------------------------------------------------------

  List<Element> _findAll(QaLocator locator) {
    final rootElement = root();
    if (rootElement == null) return const <Element>[];

    final excluded = isExcluded;
    final matches = <Element>[];
    void visit(Element element) {
      // Prune the runner's own chrome (PiP/highlight) so it can never be
      // matched or descended into.
      if (excluded != null && excluded(element)) return;
      if (_matches(element, locator)) matches.add(element);
      element.visitChildren(visit);
    }

    rootElement.visitChildren(visit);
    return matches;
  }

  bool _matches(Element element, QaLocator locator) {
    final widget = element.widget;
    switch (locator) {
      case QaTextLocator(:final text):
        // Mirrors what `find.text` matches: plain Text, Text.rich, and the
        // current contents of an editable field.
        if (widget is Text) {
          return widget.data == text || widget.textSpan?.toPlainText() == text;
        }
        if (widget is EditableText) return widget.controller.text == text;
        return false;
      case QaTypeLocator(:final type):
        return widget.runtimeType == type;
      case QaKeyLocator(:final key):
        return widget.key == key;
    }
  }

  /// Resolves [locator] to exactly one on-screen element, or fails.
  Element _requireSingle(QaLocator locator, String action) {
    final matches = _findAll(locator);
    if (matches.isEmpty) {
      throw QaScenarioFailure(
        'Could not $action ${locator.description}: nothing on screen matches it.',
      );
    }
    if (matches.length > 1) {
      throw QaScenarioFailure(
        'Could not $action ${locator.description}: '
        '${matches.length} widgets match, so the target is ambiguous.',
      );
    }
    return matches.single;
  }

  RenderBox _requireBox(Element element, QaLocator locator, String action) {
    final renderObject = element.renderObject;
    if (renderObject is! RenderBox || !renderObject.attached) {
      throw QaScenarioFailure(
        'Could not $action ${locator.description}: it is not laid out on screen.',
      );
    }
    return renderObject;
  }

  // ---- Frame / settle helpers ----------------------------------------------

  Future<void> _settleQuietly() => pacer.settle();

  Future<void> _highlight(RenderBox box) async {
    final rect = box.localToGlobal(Offset.zero) & box.size;
    onHighlight(rect);
    await pacer.pause(const Duration(milliseconds: 220));
  }

  /// Polls [predicate] until it holds or [_assertionTimeout] elapses, so
  /// assertions tolerate the async gaps a widget test would have settled away.
  ///
  /// Elapsed time is accumulated from the poll interval rather than read off
  /// the wall clock, so the timeout means the same thing whether the pacer is
  /// advancing a real clock or a faked one.
  Future<bool> _waitFor(bool Function() predicate) async {
    var elapsed = Duration.zero;
    while (true) {
      if (predicate()) return true;
      if (elapsed >= _assertionTimeout) return false;
      await pacer.pause(_pollInterval);
      elapsed += _pollInterval;
    }
  }

  // ---- QaDriver -------------------------------------------------------------

  @override
  Future<void> phase(String name, Future<void> Function() body) async {
    final step = QaStep(label: name, kind: QaStepKind.phase);
    steps.add(step);
    onUpdate();
    try {
      await body();
      step.status = QaStepStatus.passed;
    } catch (e) {
      step.status = QaStepStatus.failed;
      // Surface why the phase failed (e.g. missing credentials, no running
      // app) so the PiP shows the reason, not just a red bar.
      step.failure = e is QaScenarioFailure ? e.message : e.toString();
      rethrow;
    } finally {
      onUpdate();
    }
  }

  @override
  Future<void> tap(QaLocator locator) async {
    await _step(QaStepKind.action, 'tap ${locator.description}', () async {
      final element = _requireSingle(locator, 'tap');
      final box = _requireBox(element, locator, 'tap');
      await _highlight(box);

      final center = box.localToGlobal(box.size.center(Offset.zero));
      final binding = WidgetsBinding.instance;
      final pointer = ++_pointer;

      // A real down/up pair through the gesture binding: the widget is hit
      // tested and responds exactly as it would to a finger.
      binding.handlePointerEvent(
        PointerDownEvent(pointer: pointer, position: center),
      );
      await pacer.pause(const Duration(milliseconds: 80));
      binding.handlePointerEvent(
        PointerUpEvent(pointer: pointer, position: center),
      );

      await _settleQuietly();
      onHighlight(null);
    });
  }

  @override
  Future<void> enterText(QaLocator locator, String text) async {
    await _step(
      QaStepKind.action,
      'enter "$text" into ${locator.description}',
      () async {
        final target = _requireSingle(locator, 'type into');
        final editable = _findEditableWithin(target);
        if (editable == null) {
          throw QaScenarioFailure(
            'Could not type into ${locator.description}: '
            'it contains no editable field.',
          );
        }

        final box = _requireBox(editable, locator, 'type into');
        await _highlight(box);

        final state = (editable as StatefulElement).state as EditableTextState;
        // Going through updateEditingValue (rather than poking the controller)
        // is what the platform keyboard does, so onChanged/formatters fire.
        state.updateEditingValue(
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          ),
        );

        await _settleQuietly();
        onHighlight(null);
      },
    );
  }

  /// [target] may be the editable itself or a wrapper such as `TextField`.
  Element? _findEditableWithin(Element target) {
    if (target.widget is EditableText) return target;
    Element? found;
    void visit(Element element) {
      if (found != null) return;
      if (element.widget is EditableText) {
        found = element;
        return;
      }
      element.visitChildren(visit);
    }

    target.visitChildren(visit);
    return found;
  }

  @override
  Future<void> settle() async {
    await _step(QaStepKind.action, 'wait for the UI to settle', _settleQuietly);
  }

  @override
  Future<void> expectVisible(QaLocator locator, {int? count}) async {
    final label = count == null
        ? 'expect ${locator.description} to be visible'
        : 'expect exactly $count of ${locator.description}';
    await _step(QaStepKind.assertion, label, () async {
      final satisfied = await _waitFor(() {
        final matches = _findAll(locator).length;
        return count == null ? matches > 0 : matches == count;
      });
      if (!satisfied) {
        final actual = _findAll(locator).length;
        throw QaScenarioFailure(
          count == null
              ? 'Expected ${locator.description} to be visible, but found none.'
              : 'Expected exactly $count of ${locator.description}, found $actual.',
        );
      }
      final matches = _findAll(locator);
      if (matches.isNotEmpty) {
        final box = matches.first.renderObject;
        if (box is RenderBox && box.attached) {
          await _highlight(box);
          onHighlight(null);
        }
      }
    });
  }

  @override
  Future<void> expectAbsent(QaLocator locator) async {
    await _step(
      QaStepKind.assertion,
      'expect ${locator.description} not to be present',
      () async {
        await _settleQuietly();
        final matches = _findAll(locator).length;
        if (matches != 0) {
          throw QaScenarioFailure(
            'Expected ${locator.description} not to be present, '
            'but found $matches.',
          );
        }
      },
    );
  }

  @override
  Future<void> check(String label, bool Function() condition) async {
    await _step(QaStepKind.assertion, label, () async {
      if (!condition()) {
        throw QaScenarioFailure('Check failed: $label');
      }
    });
  }
}

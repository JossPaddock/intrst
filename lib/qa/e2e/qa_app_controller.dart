import 'package:flutter/foundation.dart';

import 'qa_app_harness.dart';

/// Process-wide handle to the running app's [QaAppHarness].
///
/// The live QA runner lives inside the admin dashboard, which is a route pushed
/// on top of `MyHomePage`. To drive the real app it needs a reference to the
/// running `_MyHomePageState`, which it can't reach through the widget tree once
/// the dashboard is popped. So the home state registers itself here on
/// `initState` (guarded by `kIsWeb && kDebugMode`) and clears it on `dispose`;
/// the runner reads [harness].
///
/// This is intentionally a tiny singleton with no Firebase or UI dependencies,
/// so importing it from `main.dart` adds no weight to release builds.
class QaAppController {
  QaAppController._();

  static final QaAppController instance = QaAppController._();

  QaAppHarness? _harness;

  /// The live app harness, or null before the home page has mounted.
  QaAppHarness? get harness => _harness;

  bool get isReady => _harness != null;

  void register(QaAppHarness harness) {
    _harness = harness;
    if (kDebugMode) {
      debugPrint('[QA] app harness registered');
    }
  }

  /// Clears the harness, but only if [harness] is the one currently registered
  /// (guards against a disposed state clobbering a freshly mounted one during
  /// hot restart).
  void unregister(QaAppHarness harness) {
    if (identical(_harness, harness)) {
      _harness = null;
    }
  }
}

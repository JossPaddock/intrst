import 'package:flutter/widgets.dart';

/// Marks a subtree as the live QA runner's own **chrome** — the draggable PiP
/// results panel and the highlight box — so [LiveQaDriver]'s element walk can
/// prune it.
///
/// The live runner drives the *whole* running app, so without this an assertion
/// such as "expect the text 'passed' to be visible" could match the PiP's own
/// summary label instead of the app under test. Wrapping the overlay chrome in
/// a `QaChrome` lets the driver skip that subtree entirely (see
/// `LiveQaDriver.isExcluded`).
class QaChrome extends StatelessWidget {
  const QaChrome({super.key, required this.child});

  final Widget child;

  /// True if [element] is (or is inside) a `QaChrome`. Passed as the driver's
  /// exclusion predicate; because the walk stops descending at the first match,
  /// testing the element's own widget type is enough.
  static bool matches(Element element) => element.widget is QaChrome;

  @override
  Widget build(BuildContext context) => child;
}

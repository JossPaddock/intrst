import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:intrst/qa/e2e/qa_chrome.dart';
import 'package:intrst/qa/live_qa_driver.dart';
import 'package:intrst/qa/qa_scenario.dart';

import 'support/tester_pacer.dart';

/// Verifies the *live* runner — the driver the admin dashboard uses to replay
/// scenarios on screen.
///
/// The headless bridge is covered implicitly by every scenario in the registry,
/// but [LiveQaDriver] never runs under `flutter test` in normal use, so without
/// this file the dashboard's runner would be the one untested piece of the
/// system.
///
/// The only part of the driver that genuinely needs a running app is *waiting*,
/// which is why that is isolated behind [QaPacer]. Swapping in a tester-backed
/// pacer lets everything else — element lookup, hit-tested pointer dispatch,
/// polling assertions, step bookkeeping — be exercised for real here.
void main() {
  final stageKey = GlobalKey();

  LiveQaDriver makeDriver(WidgetTester tester) => LiveQaDriver.scopedTo(
        stageKey,
        onUpdate: () {},
        onHighlight: (_) {},
        stepDelay: () => Duration.zero,
        pacer: TesterPacer(tester),
      );

  // Mirrors how QaTestRunnerPanel mounts a scenario: inside a keyed subtree the
  // driver scopes all of its lookups to.
  Widget stage(Widget child) => MaterialApp(
        home: Scaffold(body: KeyedSubtree(key: stageKey, child: child)),
      );

  testWidgets('finds widgets by text and by type, scoped to the stage',
      (tester) async {
    await tester.pumpWidget(stage(
      const Center(child: Text('hello stage')),
    ));

    final driver = makeDriver(tester);
    await driver.expectVisible(qaText('hello stage'), count: 1);
    await driver.expectVisible(qaType(Center));
    await driver.expectAbsent(qaText('not here'));

    expect(driver.steps.length, 3);
    expect(
      driver.steps.every((s) => s.status == QaStepStatus.passed),
      isTrue,
    );
  });

  testWidgets('taps a real button with hit-tested pointer events',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(stage(
      Center(
        child: ElevatedButton(
          onPressed: () => taps++,
          child: const Text('press me'),
        ),
      ),
    ));

    final driver = makeDriver(tester);
    await driver.tap(qaText('press me'));

    // The production button ran its own onPressed, driven by a genuine
    // down/up pair through GestureBinding — not by calling the callback.
    expect(taps, 1);
    expect(driver.steps.single.status, QaStepStatus.passed);
  });

  testWidgets('a tap that changes state is observed by the next assertion',
      (tester) async {
    await tester.pumpWidget(stage(const _Toggler()));

    final driver = makeDriver(tester);
    await driver.expectVisible(qaText('off'), count: 1);
    await driver.tap(qaText('flip'));
    await driver.expectVisible(qaText('on'), count: 1);
    await driver.expectAbsent(qaText('off'));

    expect(
      driver.steps.every((s) => s.status == QaStepStatus.passed),
      isTrue,
    );
  });

  testWidgets('assertions poll, so async work does not need a fixed wait',
      (tester) async {
    await tester.pumpWidget(stage(const _LatePayload()));

    final driver = makeDriver(tester);
    // The text only arrives after a delay; expectVisible must wait it out
    // rather than failing on the first look.
    await driver.expectVisible(qaText('arrived'), count: 1);
    expect(driver.steps.single.status, QaStepStatus.passed);
  });

  testWidgets('types into a field through the wrapping TextField',
      (tester) async {
    final controller = TextEditingController();
    var lastChanged = '';
    await tester.pumpWidget(stage(
      Center(
        child: TextField(
          controller: controller,
          onChanged: (value) => lastChanged = value,
        ),
      ),
    ));

    final driver = makeDriver(tester);
    await driver.enterText(qaType(TextField), 'typed value');

    expect(controller.text, 'typed value');
    // Went through updateEditingValue, so production onChanged fired.
    expect(lastChanged, 'typed value');
  });

  testWidgets('a failed assertion throws and marks the step failed',
      (tester) async {
    await tester.pumpWidget(stage(const SizedBox.shrink()));

    final driver = makeDriver(tester);
    await expectLater(
      () => driver.expectVisible(qaText('missing')),
      throwsA(isA<QaScenarioFailure>()),
    );

    expect(driver.steps.single.status, QaStepStatus.failed);
    expect(driver.steps.single.failure, contains('missing'));
  });

  testWidgets('an ambiguous target fails instead of guessing', (tester) async {
    await tester.pumpWidget(stage(
      const Column(children: [Text('dupe'), Text('dupe')]),
    ));

    final driver = makeDriver(tester);
    await expectLater(
      () => driver.tap(qaText('dupe')),
      throwsA(
        isA<QaScenarioFailure>().having(
          (e) => e.message,
          'message',
          contains('ambiguous'),
        ),
      ),
    );
  });

  testWidgets('phases wrap their steps and record failure', (tester) async {
    await tester.pumpWidget(stage(const Text('present')));

    final driver = makeDriver(tester);
    await driver.phase('a passing phase', () async {
      await driver.expectVisible(qaText('present'));
    });

    expect(driver.steps.first.kind, QaStepKind.phase);
    expect(driver.steps.first.status, QaStepStatus.passed);
    expect(driver.steps[1].kind, QaStepKind.assertion);
  });

  testWidgets('check() reports plain boolean conditions', (tester) async {
    await tester.pumpWidget(stage(const SizedBox.shrink()));

    final driver = makeDriver(tester);
    await driver.check('two is two', () => 2 == 2);
    expect(driver.steps.single.status, QaStepStatus.passed);

    await expectLater(
      () => driver.check('two is three', () => 2 == 3),
      throwsA(isA<QaScenarioFailure>()),
    );
    expect(driver.steps.last.status, QaStepStatus.failed);
  });

  // The live-app runner scopes to the whole app root and prunes its own PiP
  // chrome. This proves both: text inside a QaChrome subtree is invisible to
  // lookups, while text elsewhere in the same tree is found.
  testWidgets('a root-scoped driver skips QaChrome subtrees', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: const [
              Text('real app text'),
              QaChrome(child: Text('pip chrome text')),
            ],
          ),
        ),
      ),
    );

    final driver = LiveQaDriver(
      root: () => WidgetsBinding.instance.rootElement,
      isExcluded: QaChrome.matches,
      onUpdate: () {},
      onHighlight: (_) {},
      stepDelay: () => Duration.zero,
      pacer: TesterPacer(tester),
    );

    await driver.expectVisible(qaText('real app text'), count: 1);
    await driver.expectAbsent(qaText('pip chrome text'));
  });

  // The debug/step-through mode hangs off `beforeStep`: it is awaited before
  // every action/assertion, after the step is logged. Here it just counts; the
  // runner uses it to block on a "Continue" completer.
  testWidgets('beforeStep is awaited before each step', (tester) async {
    await tester.pumpWidget(stage(const Text('present')));

    final seenAtGate = <int>[];
    late final LiveQaDriver driver;
    driver = LiveQaDriver(
      root: () => stageKey.currentContext as Element?,
      onUpdate: () {},
      onHighlight: (_) {},
      stepDelay: () => Duration.zero,
      pacer: TesterPacer(tester),
      // Record how many steps exist at the moment the gate runs: the current
      // step is already logged (so >=1), proving the gate fires per step and
      // before the body.
      beforeStep: () async => seenAtGate.add(driver.steps.length),
    );

    await driver.expectVisible(qaText('present'));
    await driver.expectVisible(qaType(Text));

    expect(seenAtGate, <int>[1, 2]);
  });
}

class _Toggler extends StatefulWidget {
  const _Toggler();

  @override
  State<_Toggler> createState() => _TogglerState();
}

class _TogglerState extends State<_Toggler> {
  bool _on = false;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_on ? 'on' : 'off'),
          ElevatedButton(
            onPressed: () => setState(() => _on = !_on),
            child: const Text('flip'),
          ),
        ],
      ),
    );
  }
}

/// Renders its payload only after a delay, standing in for the async loads
/// (e.g. a fake Firestore read) real scenarios wait on.
class _LatePayload extends StatefulWidget {
  const _LatePayload();

  @override
  State<_LatePayload> createState() => _LatePayloadState();
}

class _LatePayloadState extends State<_LatePayload> {
  String _text = 'loading';

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _text = 'arrived');
    });
  }

  @override
  Widget build(BuildContext context) => Center(child: Text(_text));
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../live_qa_driver.dart';
import 'qa_chrome.dart';

/// Where a run is in its lifecycle, for the PiP summary line.
enum QaRunStatus { running, passed, failed }

/// Observable state of the current live run, shared between the runner (which
/// writes it) and the PiP widgets (which render it). A single [ChangeNotifier]
/// keeps the draggable panel and the highlight box in sync without either
/// knowing about the runner.
class QaRunView extends ChangeNotifier {
  String scenarioName = '';
  String suite = '';

  /// Progress across a "run all", e.g. "2 / 7". Empty for a single run.
  String progress = '';

  List<QaStep> steps = const <QaStep>[];
  QaRunStatus status = QaRunStatus.running;

  /// Set when the whole run has finished (so the panel shows a Close/Back row).
  bool finished = false;

  /// True when the run is a step-through ("Debug") run.
  bool debugMode = false;

  /// True while a debug run is paused before a step, waiting for "Continue".
  bool awaitingContinue = false;

  /// Global-coordinate rect of the widget currently being acted on, or null.
  Rect? highlight;

  int get passed => steps
      .where((s) => s.kind != QaStepKind.phase && s.status == QaStepStatus.passed)
      .length;
  int get failed => steps.where((s) => s.status == QaStepStatus.failed).length;

  void notify() => notifyListeners();

  /// The whole run rendered as copyable plain text — the overlay isn't
  /// selectable, so the PiP's copy button hands this to the clipboard. Numbering
  /// mirrors what is shown on screen.
  String toPlainText() {
    final buffer = StringBuffer()
      ..writeln('Live patrol run${progress.isNotEmpty ? '  ($progress)' : ''}');
    if (suite.isNotEmpty) buffer.writeln('Suite: $suite');
    if (scenarioName.isNotEmpty) buffer.writeln('Scenario: $scenarioName');
    buffer
      ..writeln('Status: ${status.name}'
          '  ($passed passed${failed > 0 ? ', $failed failed' : ''})')
      ..writeln();

    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      final mark = switch (step.status) {
        QaStepStatus.running => '…',
        QaStepStatus.passed => '✓',
        QaStepStatus.failed => '✗',
      };
      if (step.kind == QaStepKind.phase) {
        buffer.writeln('$mark ${step.label.toUpperCase()}');
      } else {
        buffer.writeln('  $mark ${i + 1}. ${step.label}');
      }
      if (step.failure != null) {
        buffer.writeln('      ${step.failure}');
      }
    }
    return buffer.toString();
  }
}

/// Manages the two root-overlay entries the live runner shows on top of the
/// running app: a draggable results **panel** and a **highlight** box. Both are
/// wrapped in [QaChrome] so the driver's element walk skips them.
class QaPipOverlay {
  QaPipOverlay({
    required OverlayState overlay,
    required this.view,
    required this.onClose,
    required this.onBackToDashboard,
    required this.onContinue,
  }) : _overlay = overlay;

  final OverlayState _overlay;
  final QaRunView view;

  /// Invoked by the panel's ✕ — removes the overlay and abandons any run.
  final VoidCallback onClose;

  /// Invoked by "Back to dashboard" once a run has finished.
  final VoidCallback onBackToDashboard;

  /// Invoked by the "Continue" button to advance a paused debug run one step.
  final VoidCallback onContinue;

  OverlayEntry? _panelEntry;
  OverlayEntry? _highlightEntry;

  void insert() {
    _highlightEntry = OverlayEntry(
      builder: (_) => QaChrome(child: _QaHighlightLayer(view: view)),
    );
    _panelEntry = OverlayEntry(
      builder: (_) => QaChrome(
        child: _QaPipPanel(
          view: view,
          onClose: onClose,
          onBackToDashboard: onBackToDashboard,
          onContinue: onContinue,
        ),
      ),
    );
    _overlay.insert(_highlightEntry!);
    _overlay.insert(_panelEntry!);
  }

  void remove() {
    _panelEntry?.remove();
    _highlightEntry?.remove();
    _panelEntry = null;
    _highlightEntry = null;
  }
}

const Color _brand = Color(0xFF082D38);
const Color _panelBg = Color(0xFF10262E);
const Color _highlightFill = Color(0x2EFFC107);
const Color _highlightBorder = Color(0xFFFFA000);

/// Paints the driver's highlight rect (in global coordinates) over the app.
/// The root overlay fills the window from the origin, so a global rect maps
/// straight to overlay-local coordinates.
class _QaHighlightLayer extends StatelessWidget {
  const _QaHighlightLayer({required this.view});

  final QaRunView view;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: view,
      builder: (context, _) {
        final rect = view.highlight;
        if (rect == null) return const SizedBox.shrink();
        return Positioned(
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _highlightFill,
                border: Border.all(color: _highlightBorder, width: 2),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The draggable results panel. Shows the scenario name, a live step log and a
/// pass/fail summary; grows a Close / Back-to-dashboard row when finished.
class _QaPipPanel extends StatefulWidget {
  const _QaPipPanel({
    required this.view,
    required this.onClose,
    required this.onBackToDashboard,
    required this.onContinue,
  });

  final QaRunView view;
  final VoidCallback onClose;
  final VoidCallback onBackToDashboard;
  final VoidCallback onContinue;

  @override
  State<_QaPipPanel> createState() => _QaPipPanelState();
}

class _QaPipPanelState extends State<_QaPipPanel> {
  static const double _width = 340;
  final ScrollController _logController = ScrollController();

  // Top-left of the panel, in global coordinates. Set on first layout so the
  // panel opens near the top-right, out of the way of most flows.
  Offset? _position;

  // Briefly true after "copy logs", to confirm the copy landed.
  bool _copied = false;

  @override
  void dispose() {
    _logController.dispose();
    super.dispose();
  }

  Future<void> _copyLogs() async {
    await Clipboard.setData(ClipboardData(text: widget.view.toPlainText()));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (mounted) setState(() => _copied = false);
  }

  void _onStepsChanged() {
    if (!_logController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logController.hasClients) {
        _logController.jumpTo(_logController.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final position = _position ??= Offset(size.width - _width - 24, 24);

    return Positioned(
      left: position.dx.clamp(0.0, size.width - 80),
      top: position.dy.clamp(0.0, size.height - 80),
      child: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: _width,
            maxHeight: size.height * 0.7,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _panelBg,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(color: Colors.black45, blurRadius: 16, offset: Offset(0, 6)),
              ],
            ),
            child: AnimatedBuilder(
              animation: widget.view,
              builder: (context, _) {
                _onStepsChanged();
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(),
                    Flexible(child: _buildLog()),
                    _buildFooter(),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final view = widget.view;
    return GestureDetector(
      // Drag the whole panel by its header.
      onPanUpdate: (details) =>
          setState(() => _position = _position! + details.delta),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        decoration: const BoxDecoration(
          color: _brand,
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: Row(
          children: [
            const Icon(Icons.drag_indicator, size: 16, color: Colors.white54),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        view.debugMode ? 'Live patrol · debug' : 'Live patrol run',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      if (view.debugMode) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.bug_report,
                            size: 14, color: Colors.amber),
                      ],
                      if (view.progress.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          view.progress,
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                  if (view.scenarioName.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        view.scenarioName,
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: _copied ? 'Copied' : 'Copy logs',
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                _copied ? Icons.check : Icons.copy,
                color: _copied ? Colors.greenAccent.shade200 : Colors.white70,
              ),
              onPressed: _copyLogs,
            ),
            IconButton(
              tooltip: 'Close',
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, color: Colors.white70),
              onPressed: widget.onClose,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLog() {
    final steps = widget.view.steps;
    if (steps.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Starting…',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
      );
    }
    return ListView.builder(
      controller: _logController,
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: steps.length,
      itemBuilder: (context, index) => _buildStepRow(steps[index], index + 1),
    );
  }

  Widget _buildStepRow(QaStep step, int number) {
    final isPhase = step.kind == QaStepKind.phase;
    late final Color color;
    late final IconData icon;
    switch (step.status) {
      case QaStepStatus.running:
        color = Colors.amber.shade300;
        icon = Icons.more_horiz;
      case QaStepStatus.passed:
        color = isPhase ? Colors.white : Colors.greenAccent.shade200;
        icon = Icons.check;
      case QaStepStatus.failed:
        color = Colors.red.shade300;
        icon = Icons.close;
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(isPhase ? 10 : 24, 3, 10, 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isPhase ? step.label.toUpperCase() : '$number. ${step.label}',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    height: 1.35,
                    color: color,
                    fontWeight: isPhase ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
          if (step.failure != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(19, 2, 0, 2),
              child: Text(
                step.failure!,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10.5,
                  color: Colors.red.shade200,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final view = widget.view;
    final Color statusColor;
    final String statusText;
    switch (view.status) {
      case QaRunStatus.running:
        statusColor = Colors.amber.shade300;
        statusText = 'running…';
      case QaRunStatus.passed:
        statusColor = Colors.greenAccent.shade200;
        statusText = 'passed';
      case QaRunStatus.failed:
        statusColor = Colors.red.shade300;
        statusText = 'failed';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (view.awaitingContinue)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FilledButton.icon(
                onPressed: widget.onContinue,
                icon: const Icon(Icons.skip_next, size: 18),
                label: const Text('Continue (next step)'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.amber.shade600,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(36),
                ),
              ),
            ),
          Row(
            children: [
              if (view.awaitingContinue)
                Icon(Icons.pause_circle_filled,
                    size: 14, color: Colors.amber.shade300)
              else if (view.status == QaRunStatus.running)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  view.status == QaRunStatus.passed
                      ? Icons.check_circle
                      : Icons.cancel,
                  size: 14,
                  color: statusColor,
                ),
              const SizedBox(width: 8),
              Text(
                view.awaitingContinue ? 'paused' : statusText,
                style: TextStyle(
                  color: view.awaitingContinue ? Colors.amber.shade300 : statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '${view.passed} passed'
                '${view.failed > 0 ? ' · ${view.failed} failed' : ''}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
          if (view.finished)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: widget.onBackToDashboard,
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: const Text('Back to dashboard'),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

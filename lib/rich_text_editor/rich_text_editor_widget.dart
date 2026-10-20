import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderEditable;
import 'package:intrst/rich_text_editor/rich_text_document.dart';
import 'package:intrst/rich_text_editor/rich_text_editor_controller.dart';
import 'package:intrst/rich_text_editor/url_detector.dart';
import 'package:url_launcher/url_launcher.dart';
import 'link_popover.dart';
import 'link_visit_store.dart';

// ── Mode enum ─────────────────────────────────────────────────────────────────

enum RichTextEditorMode { edit, view }

// ── Widget ────────────────────────────────────────────────────────────────────

/// A drop-in replacement for [TextField] that supports rich-text hyperlinks.
///
/// ## Modes
/// Toggle between [RichTextEditorMode.edit] and [RichTextEditorMode.view] by
/// updating the [mode] prop.  Users cannot switch modes themselves.
///
/// ## Controller
/// Pass a [RichTextEditorController] to read/write the document from outside:
/// ```dart
/// final _ctrl = RichTextEditorController();
/// // … later:
/// final doc = _ctrl.document;           // serialise
/// _ctrl.loadDocument(savedDoc);         // deserialise
/// _ctrl.addLink(selection: ..., url: 'https://example.com');
/// ```
///
/// ## Drop-in compatibility
/// Accepts the most common [TextField] parameters so you can replace an
/// existing [TextField] with minimal changes.
///
/// ## iOS magnifier
/// The magnifier works because edit mode uses a standard [TextField] under the
/// hood.  View mode uses [SelectableText] which also supports it.
///
/// ## Dependencies (add to pubspec.yaml)
/// ```yaml
/// dependencies:
///   shared_preferences: ^2.0.0   # for LinkVisitStore
///   url_launcher: ^6.0.0         # for opening links
/// ```
class RichTextEditorWidget extends StatefulWidget {
  const RichTextEditorWidget({
    super.key,
    required this.mode,
    this.controller,
    this.decoration = const InputDecoration(),
    this.style,
    this.focusNode,
    this.maxLines = 1,
    this.minLines,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.enabled = true,
    this.autofocus = false,
    this.onChanged,
    this.onEditingComplete,
    this.onSubmitted,
    this.onTap,
    this.scrollPhysics,
    this.scrollController,
  });

  final RichTextEditorMode mode;

  /// Provide your own controller to read/write the document programmatically.
  /// If `null`, an internal controller is created and managed for you.
  final RichTextEditorController? controller;

  // Standard TextField parameters ────────────────────────────────────────────
  final InputDecoration? decoration;
  final TextStyle? style;
  final FocusNode? focusNode;
  final int? maxLines;
  final int? minLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final bool enabled;
  final bool autofocus;

  /// Called whenever the document changes (user typing or programmatic link ops).
  final ValueChanged<RichTextDocument>? onChanged;
  final VoidCallback? onEditingComplete;
  final ValueChanged<String>? onSubmitted;
  final GestureTapCallback? onTap;
  final ScrollPhysics? scrollPhysics;
  final ScrollController? scrollController;

  @override
  State<RichTextEditorWidget> createState() => _RichTextEditorWidgetState();
}

// ── State ─────────────────────────────────────────────────────────────────────

class _RichTextEditorWidgetState extends State<RichTextEditorWidget> {
  // Controller — either provided by the parent or self-managed.
  late RichTextEditorController _controller;
  bool _ownsController = false;

  // Focus
  late FocusNode _focusNode;
  bool _ownsFocusNode = false;

  // Overlay / popover
  OverlayEntry? _popoverEntry;
  ({String url, int start, int end})? _activeLink;
  // Caret offset of the tap that opened the popover; picks which line of a
  // wrapped link the popover anchors to.
  int _activeCaretOffset = 0;
  // The link rect the popover was last built against, and the scroll
  // positions that can move the link while the popover is open.
  Rect? _popoverAnchor;
  Listenable? _linkMovement;
  bool _repositionScheduled = false;

  // Key for measuring the TextField's render box.
  final GlobalKey _fieldKey = GlobalKey();

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    if (widget.controller == null) {
      _controller = RichTextEditorController();
      _ownsController = true;
    } else {
      _controller = widget.controller!;
    }

    if (widget.focusNode == null) {
      _focusNode = FocusNode();
      _ownsFocusNode = true;
    } else {
      _focusNode = widget.focusNode!;
    }

    _controller.addListener(_onControllerChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(RichTextEditorWidget old) {
    super.didUpdateWidget(old);

    // Controller swap.
    if (widget.controller != old.controller) {
      _controller.removeListener(_onControllerChanged);
      if (_ownsController) {
        _controller.dispose();
        _ownsController = false;
      }
      if (widget.controller == null) {
        _controller = RichTextEditorController();
        _ownsController = true;
      } else {
        _controller = widget.controller!;
      }
      _controller.addListener(_onControllerChanged);
    }

    // Focus node swap.
    if (widget.focusNode != old.focusNode) {
      _focusNode.removeListener(_onFocusChanged);
      if (_ownsFocusNode) {
        _focusNode.dispose();
        _ownsFocusNode = false;
      }
      if (widget.focusNode == null) {
        _focusNode = FocusNode();
        _ownsFocusNode = true;
      } else {
        _focusNode = widget.focusNode!;
      }
      _focusNode.addListener(_onFocusChanged);
    }

    // Hide popover when switching modes.
    if (widget.mode != old.mode) {
      _hidePopover();
    }
  }

  @override
  void dispose() {
    _hidePopover();
    _controller.removeListener(_onControllerChanged);
    _focusNode.removeListener(_onFocusChanged);
    if (_ownsController) _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  // ── Controller / focus listeners ───────────────────────────────────────────

  void _onControllerChanged() {
    widget.onChanged?.call(_controller.document);
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) _hidePopover();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return widget.mode == RichTextEditorMode.edit
        ? _buildEditMode()
        : _buildViewMode();
  }

  // ── Edit mode ──────────────────────────────────────────────────────────────

  Widget _buildEditMode() {
    return TextField(
      key: _fieldKey,
      controller: _controller,
      focusNode: _focusNode,
      decoration: widget.decoration,
      style: widget.style,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      textCapitalization: widget.textCapitalization,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      scrollPhysics: widget.scrollPhysics,
      scrollController: widget.scrollController,
      onChanged: (text) {
        _controller.reconcile(text);
        widget.onChanged?.call(_controller.document);
      },
      onEditingComplete: widget.onEditingComplete,
      onSubmitted: widget.onSubmitted,
      onTap: () {
        widget.onTap?.call();
        // The TextField updates _controller.selection before onTap returns,
        // but the selection value isn't flushed to the controller until the
        // next frame, so we defer the link check by one frame.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final sel = _controller.selection;
          if (!sel.isValid || !sel.isCollapsed) {
            _hidePopover();
            return;
          }
          final link = _controller.getLinkAtOffset(sel.baseOffset);
          if (link != null) {
            _showPopoverAtLinkRange(link);
          } else {
            _hidePopover();
          }
        });
      },
    );
  }

  void _showPopoverAtLinkRange(({String url, int start, int end}) link) {
    _hidePopover();

    _activeLink = link;
    _activeCaretOffset = _controller.selection.baseOffset;
    _popoverEntry = OverlayEntry(builder: (ctx) {
      final anchor = _popoverAnchor = _linkAnchorRect();
      // This frame's layout (keyboard resize, scrolling) may still move the
      // link; re-check once it has settled.
      _scheduleReposition();
      if (anchor == null) return const SizedBox.shrink();
      return _PopoverPositioner(
        anchor: anchor,
        // Stay clear of the notch, home indicator and keyboard.
        insets: MediaQuery.paddingOf(ctx) +
            MediaQuery.viewInsetsOf(ctx) +
            const EdgeInsets.all(8),
        onDismiss: _hidePopover,
        child: LinkPopover(
          url: link.url,
          mode: LinkPopoverMode.edit,
          onOpen: () {
            _hidePopover();
            _openLink(link.url);
          },
          onEdit: () {
            _hidePopover();
            _showLinkEditDialog(
              initialText:
              _controller.text.substring(link.start, link.end),
              initialUrl: link.url,
              offset: link.start,
            );
          },
          onRemove: () {
            _hidePopover();
            _controller.removeLink(link.start);
          },
        ),
      );
    });

    Overlay.of(context).insert(_popoverEntry!);
    _listenForLinkMovement();
  }

  /// The tapped link's rect in the overlay's coordinates — the line of the
  /// link the caret is on, since a wrapped link has one box per line — or the
  /// whole field if the link can't be measured.
  Rect? _linkAnchorRect() {
    final link = _activeLink;
    final overlayBox =
        Overlay.maybeOf(context)?.context.findRenderObject() as RenderBox?;
    final fieldBox = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (link == null ||
        overlayBox == null ||
        fieldBox == null ||
        !fieldBox.attached ||
        !fieldBox.hasSize) {
      return null;
    }

    // Measure on the field's own RenderEditable so decoration, padding and
    // the field's internal scroll offset are all accounted for.
    final editable = _renderEditable;
    if (editable != null) {
      final length = _controller.text.length;
      final boxes = editable.getBoxesForSelection(TextSelection(
        baseOffset: link.start.clamp(0, length),
        extentOffset: link.end.clamp(0, length),
      ));
      if (boxes.isNotEmpty) {
        final caretY = editable
            .getLocalRectForCaret(
                TextPosition(offset: _activeCaretOffset.clamp(0, length)))
            .center
            .dy;
        final box = boxes.firstWhere(
          (b) => b.top <= caretY && caretY <= b.bottom,
          orElse: () => boxes.first,
        );
        return MatrixUtils.transformRect(
            editable.getTransformTo(overlayBox), box.toRect());
      }
    }
    return MatrixUtils.transformRect(
        fieldBox.getTransformTo(overlayBox), Offset.zero & fieldBox.size);
  }

  RenderEditable? get _renderEditable {
    // TextField's state exposes its EditableText key through this interface.
    final Object? state = _fieldKey.currentState;
    return state is TextSelectionGestureDetectorBuilderDelegate
        ? state.editableTextKey.currentState?.renderEditable
        : null;
  }

  /// Keeps the popover on the link while it scrolls — inside the field (long
  /// text) or along with any scrollable the field sits in.
  void _listenForLinkMovement() {
    final sources = <Listenable>[];
    final editable = _renderEditable;
    if (editable != null) sources.add(editable.offset);
    for (var scrollable = Scrollable.maybeOf(context);
        scrollable != null;
        scrollable = Scrollable.maybeOf(scrollable.context)) {
      sources.add(scrollable.position);
    }
    _linkMovement = Listenable.merge(sources)
      ..addListener(_scheduleReposition);
  }

  /// After the current frame is laid out, rebuilds the popover if the link
  /// has moved since the popover was last positioned.
  void _scheduleReposition() {
    if (_repositionScheduled) return;
    _repositionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _repositionScheduled = false;
      if (!mounted || _popoverEntry == null) return;
      if (_linkAnchorRect() != _popoverAnchor) _popoverEntry!.markNeedsBuild();
    });
  }

  // ── View mode ──────────────────────────────────────────────────────────────

  Widget _buildViewMode() {
    final doc = _controller.document;
    final baseStyle = DefaultTextStyle.of(context).style.merge(widget.style);

    // Build an inline span tree from the document ops.
    final spans = <InlineSpan>[];
    for (final op in doc.ops) {
      if (op.isLink) {
        final url = op.link!;
        final visited = LinkVisitStore.instance.hasVisited(url);
        final linkColor =
        visited ? const Color(0xFF6A0DAD) : const Color(0xFF1A73E8);
        spans.add(TextSpan(
          text: op.text,
          style: baseStyle.copyWith(
            color: linkColor,
            decoration: TextDecoration.underline,
            decorationColor: linkColor,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => _openLink(url),
        ));
      } else {
        spans.add(TextSpan(text: op.text, style: baseStyle));
      }
    }

    return RichText(
      text: TextSpan(children: spans),
      maxLines: widget.maxLines,
      overflow: widget.maxLines != null
          ? TextOverflow.ellipsis
          : TextOverflow.clip,
    );
  }

  // ── Popover ────────────────────────────────────────────────────────────────

  void _hidePopover() {
    _linkMovement?.removeListener(_scheduleReposition);
    _linkMovement = null;
    _popoverEntry?.remove();
    _popoverEntry = null;
  }

  // ── Link edit dialog ───────────────────────────────────────────────────────

  Future<void> _showLinkEditDialog({
    required String initialText,
    required String initialUrl,
    required int offset,
  }) async {
    // We pass the data in and get the result back.
    // No local controller management here!
    final result = await showDialog<({String text, String url})>(
      context: context,
      builder: (ctx) => _LinkEditDialog(
        initialText: initialText,
        initialUrl: initialUrl,
      ),
    );

    if (result == null || !mounted) return;

    _controller.updateLink(
      offset: offset,
      newText: result.text.isEmpty ? null : result.text,
      newUrl: result.url.isEmpty ? null : UrlDetector.normalise(result.url),
    );
  }

  // ── URL opening ────────────────────────────────────────────────────────────

  Future<void> _openLink(String url) async {
    final normalised = UrlDetector.normalise(url);
    await LinkVisitStore.instance.markVisited(normalised);
    // Rebuild to show updated visited colour.
    if (mounted) setState(() {});

    final uri = Uri.tryParse(normalised);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

}

// ── Popover positioner ────────────────────────────────────────────────────────

/// Lays the [child] popover out next to [anchor] (the link, in overlay
/// coordinates) while keeping it fully inside the overlay minus [insets].
/// Tapping outside the popover calls [onDismiss].
class _PopoverPositioner extends StatelessWidget {
  const _PopoverPositioner({
    required this.anchor,
    required this.insets,
    required this.child,
    required this.onDismiss,
  });

  final Rect anchor;
  final EdgeInsets insets;
  final Widget child;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Transparent barrier — passes touches through to whatever is below,
        // but also fires onDismiss so the popover can close.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onDismiss,
          ),
        ),
        // The actual popover card. Taps that miss it fall through to the
        // barrier.
        Positioned.fill(
          child: CustomSingleChildLayout(
            delegate: _PopoverLayoutDelegate(anchor: anchor, insets: insets),
            child: child,
          ),
        ),
      ],
    );
  }
}

/// Places the popover just below the link with their left edges aligned,
/// flips it above the link when there's more room there, then shifts it as
/// little as needed to keep every button on screen.
class _PopoverLayoutDelegate extends SingleChildLayoutDelegate {
  _PopoverLayoutDelegate({required this.anchor, required this.insets});

  final Rect anchor;
  final EdgeInsets insets;

  static const double _gap = 4;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    // Never wider than the visible area; the URL chip shrinks to fit.
    return constraints.loosen().copyWith(
      maxWidth: math.max(0.0, constraints.maxWidth - insets.horizontal),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final bounds = insets.deflateRect(Offset.zero & size);
    final roomBelow = bounds.bottom - anchor.bottom - _gap;
    final roomAbove = anchor.top - _gap - bounds.top;
    final top = roomBelow >= childSize.height || roomBelow >= roomAbove
        ? anchor.bottom + _gap
        : anchor.top - _gap - childSize.height;
    return Offset(
      _clampInto(anchor.left, bounds.left, bounds.right - childSize.width),
      _clampInto(top, bounds.top, bounds.bottom - childSize.height),
    );
  }

  // Like num.clamp, but pins to [min] rather than throwing when the popover
  // is bigger than the space (max < min).
  static double _clampInto(double value, double min, double max) =>
      math.max(min, math.min(value, max));

  @override
  bool shouldRelayout(_PopoverLayoutDelegate old) =>
      anchor != old.anchor || insets != old.insets;
}

class _LinkEditDialog extends StatefulWidget {
  final String initialText;
  final String initialUrl;

  const _LinkEditDialog({required this.initialText, required this.initialUrl});

  @override
  State<_LinkEditDialog> createState() => _LinkEditDialogState();
}

class _LinkEditDialogState extends State<_LinkEditDialog> {
  late final TextEditingController _textCtrl;
  late final TextEditingController _urlCtrl;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(text: widget.initialText);
    _urlCtrl = TextEditingController(text: widget.initialUrl);
  }

  @override
  void dispose() {
    // These now dispose only when the Dialog is actually destroyed
    _textCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  void _handleSave() {
    // 1. Unfocus first to stop the keyboard/caret logic
    FocusManager.instance.primaryFocus?.unfocus();

    // 2. Return data
    Navigator.of(context).pop((text: _textCtrl.text.trim(), url: _urlCtrl.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit link'),
      content: SingleChildScrollView( // Prevents the RenderFlex overflow
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _textCtrl,
              decoration: const InputDecoration(labelText: 'Display text'),
              autofocus: true,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlCtrl,
              decoration: const InputDecoration(
                labelText: 'URL',
                prefixIcon: Icon(Icons.link_rounded),
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _handleSave(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _handleSave,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
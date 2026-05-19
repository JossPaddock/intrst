import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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

    final renderBox =
    _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final globalFieldOrigin = renderBox.localToGlobal(Offset.zero);
    final padding = _resolvedContentPadding();
    final painter =
    _buildPainter(renderBox.size.width - padding.horizontal);

    final boxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: link.start, extentOffset: link.end),
    );
    painter.dispose();

    final Offset popoverGlobal;
    if (boxes.isNotEmpty) {
      final box = boxes.first;
      popoverGlobal = Offset(
        globalFieldOrigin.dx + padding.left + box.left,
        globalFieldOrigin.dy + padding.top + box.bottom + 4,
      );
    } else {
      popoverGlobal = Offset(
        globalFieldOrigin.dx + padding.left,
        globalFieldOrigin.dy + renderBox.size.height + 4,
      );
    }

    _activeLink = link;
    _popoverEntry = OverlayEntry(builder: (ctx) {
      return _PopoverPositioner(
        position: popoverGlobal,
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

  // ── Link tap handling (edit mode) ──────────────────────────────────────────

  void _onEditTapUp(TapUpDetails details) {
    final offset = _hitTestTextOffset(details.localPosition);
    if (offset == null) {
      _hidePopover();
      return;
    }
    final link = _controller.getLinkAtOffset(offset);
    if (link != null) {
      _activeLink = link;
      _showPopover(link, details.localPosition);
    } else {
      _hidePopover();
      _activeLink = null;
    }
  }

  /// Converts a tap's local position (relative to the TextField) into a
  /// character offset using [TextPainter].
  int? _hitTestTextOffset(Offset localPosition) {
    final renderBox =
    _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return null;

    // Subtract content padding so we measure from the text origin.
    final padding = _resolvedContentPadding();
    final adjusted = Offset(
      (localPosition.dx - padding.left).clamp(0.0, double.infinity),
      (localPosition.dy - padding.top).clamp(0.0, double.infinity),
    );

    final painter = _buildPainter(renderBox.size.width - padding.horizontal);
    final position = painter.getPositionForOffset(adjusted);
    painter.dispose();
    return position.offset;
  }

  // ── Popover ────────────────────────────────────────────────────────────────

  void _showPopover(
      ({String url, int start, int end}) link,
      Offset localTapPosition,
      ) {
    _hidePopover();

    final renderBox =
    _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final globalFieldOrigin = renderBox.localToGlobal(Offset.zero);
    final padding = _resolvedContentPadding();
    final painter =
    _buildPainter(renderBox.size.width - padding.horizontal);

    // Get the bounding boxes for the link's character range.
    final boxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: link.start, extentOffset: link.end),
    );
    painter.dispose();

    Offset popoverGlobal;
    if (boxes.isNotEmpty) {
      final box = boxes.first;
      popoverGlobal = Offset(
        globalFieldOrigin.dx + padding.left + box.left,
        globalFieldOrigin.dy + padding.top + box.bottom + 4,
      );
    } else {
      // Fallback: just below the field.
      popoverGlobal = Offset(
        globalFieldOrigin.dx + padding.left,
        globalFieldOrigin.dy + renderBox.size.height + 4,
      );
    }

    _popoverEntry = OverlayEntry(builder: (ctx) {
      return _PopoverPositioner(
        position: popoverGlobal,
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
  }

  void _hidePopover() {
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

  // ── TextPainter helpers ────────────────────────────────────────────────────

  TextPainter _buildPainter(double maxWidth) {
    final painter = TextPainter(
      text: _controller.buildTextSpan(
        context: context,
        style: widget.style,
        withComposing: false,
      ),
      textDirection: TextDirection.ltr,
      maxLines: widget.maxLines,
    )..layout(maxWidth: maxWidth.clamp(0.0, double.infinity));
    return painter;
  }

  EdgeInsets _resolvedContentPadding() {
    final cp = widget.decoration?.contentPadding;
    if (cp == null) {
      // Match Flutter's default TextField padding.
      return const EdgeInsets.symmetric(horizontal: 12, vertical: 8);
    }
    return cp.resolve(Directionality.of(context));
  }
}

// ── Popover positioner ────────────────────────────────────────────────────────

/// Positions the [child] popover at [position] in global coordinates.
/// Tapping outside the popover calls [onDismiss].
class _PopoverPositioner extends StatelessWidget {
  const _PopoverPositioner({
    required this.position,
    required this.child,
    required this.onDismiss,
  });

  final Offset position;
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
        // The actual popover card.
        Positioned(
          left: position.dx,
          top: position.dy,
          child: child,
        ),
      ],
    );
  }
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
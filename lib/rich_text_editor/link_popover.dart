import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The mode in which the popover is shown.
enum LinkPopoverMode { edit, view }

/// Callback signatures used by [LinkPopover].
typedef OnEditLink = void Function();
typedef OnRemoveLink = void Function();
typedef OnOpenLink = void Function();

/// A compact floating card that appears when the user taps a hyperlink.
///
/// In [LinkPopoverMode.edit] it shows:
///   • The (truncated) URL
///   • An "Open" button
///   • An "Edit" button  — lets the user change display text / URL
///   • A "Remove" button — removes the link without deleting the text
///
/// In [LinkPopoverMode.view] it shows:
///   • The (truncated) URL
///   • An "Open" button
///
/// This widget is always placed inside an [OverlayEntry]; see
/// [RichTextEditorWidget] for how it is positioned.
class LinkPopover extends StatelessWidget {
  const LinkPopover({
    super.key,
    required this.url,
    required this.mode,
    required this.onOpen,
    this.onEdit,
    this.onRemove,
  });

  final String url;
  final LinkPopoverMode mode;
  final OnOpenLink onOpen;
  final OnEditLink? onEdit;
  final OnRemoveLink? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      color: colorScheme.surfaceContainerHighest,
      child: IntrinsicWidth(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // URL chip
              Flexible(
                child: _UrlChip(url: url),
              ),
              const SizedBox(width: 4),
              _Divider(),
              // Open in browser
              _IconBtn(
                icon: Icons.open_in_new_rounded,
                tooltip: 'Open link',
                onTap: onOpen,
              ),
              if (mode == LinkPopoverMode.edit) ...[
                // Edit text / URL
                _IconBtn(
                  icon: Icons.edit_rounded,
                  tooltip: 'Edit link',
                  onTap: onEdit,
                ),
                // Remove link
                _IconBtn(
                  icon: Icons.link_off_rounded,
                  tooltip: 'Remove link',
                  onTap: onRemove,
                  color: colorScheme.error,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Private sub-widgets ───────────────────────────────────────────────────────

class _UrlChip extends StatelessWidget {
  const _UrlChip({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final display = _trimUrl(url);
    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: url));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Link copied'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: Container(
        constraints: const BoxConstraints(maxWidth: 180),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          display,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            color: colorScheme.primary,
          ),
        ),
      ),
    );
  }

  String _trimUrl(String url) {
    // Strip scheme for display (https://www.google.com → www.google.com).
    return url
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceFirst(RegExp(r'^ftp://'), '');
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 20,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    color: Theme.of(context).colorScheme.outlineVariant,
  );
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          icon,
          size: 18,
          color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}
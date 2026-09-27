import 'package:flutter/material.dart';
import '../core/app_colors.dart';

/// A single autocomplete suggestion.
class Suggestion {
  final String text; // value placed into the field
  final String? secondary; // small hint shown on the right (e.g. course code)
  final Object? data; // optional payload for onPicked
  const Suggestion(this.text, {this.secondary, this.data});
}

/// Text field with a floating suggestion dropdown — mirrors the website's
/// custom autocomplete (`ac-dropdown`). Filters [suggestions] by the typed
/// query and calls [onPicked] when one is chosen.
class SuggestField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final List<Suggestion> Function() suggestions;
  final void Function(Suggestion)? onPicked;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final int maxShown;

  /// When true, focusing the field with an empty query shows the full list
  /// (used for contextual Topic suggestions). When false (default), the
  /// dropdown only appears once the user types — matching the site.
  final bool showAllOnFocus;

  const SuggestField({
    super.key,
    required this.controller,
    required this.label,
    required this.suggestions,
    this.hint,
    this.onPicked,
    this.onChanged,
    this.keyboardType,
    this.maxShown = 7,
    this.showAllOnFocus = false,
  });

  @override
  State<SuggestField> createState() => _SuggestFieldState();
}

class _SuggestFieldState extends State<SuggestField> {
  final _layerLink = LayerLink();
  final _focus = FocusNode();
  OverlayEntry? _entry;
  List<Suggestion> _matches = [];

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) {
        _update(widget.controller.text);
      } else {
        _hide();
      }
    });
  }

  @override
  void dispose() {
    _hide();
    _focus.dispose();
    super.dispose();
  }

  void _update(String q) {
    final query = q.trim().toLowerCase();
    final all = widget.suggestions();
    final List<Suggestion> list;
    if (query.isEmpty) {
      list = widget.showAllOnFocus ? all.take(widget.maxShown).toList() : const [];
    } else {
      list = all
          .where((s) =>
              s.text.toLowerCase().contains(query) ||
              (s.secondary?.toLowerCase().contains(query) ?? false))
          .take(widget.maxShown)
          .toList();
    }
    _matches = list;
    if (_matches.isEmpty || !_focus.hasFocus) {
      _hide();
    } else {
      _show();
    }
  }

  void _show() {
    _entry?.remove();
    _entry = OverlayEntry(builder: (_) => _dropdown());
    Overlay.of(context).insert(_entry!);
  }

  void _hide() {
    _entry?.remove();
    _entry = null;
  }

  void _pick(Suggestion s) {
    widget.controller.text = s.text;
    widget.controller.selection =
        TextSelection.collapsed(offset: s.text.length);
    widget.onPicked?.call(s);
    widget.onChanged?.call(s.text);
    _hide();
    _focus.unfocus();
  }

  Widget _dropdown() {
    final box = context.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 300;
    // Anchor the panel just below the field using its real height, so it never
    // overlaps the input regardless of label/dense settings.
    final fieldHeight = box?.size.height ?? 56;
    return Positioned(
      width: width,
      child: CompositedTransformFollower(
        link: _layerLink,
        showWhenUnlinked: false,
        offset: Offset(0, fieldHeight + 4),
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxHeight: 280),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderAccent),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 4),
              shrinkWrap: true,
              itemCount: _matches.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, thickness: 1, color: AppColors.border),
              itemBuilder: (_, i) {
                final s = _matches[i];
                final hasSecondary = s.secondary != null && s.secondary!.isNotEmpty;
                return InkWell(
                  onTap: () => _pick(s),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Full value — wraps so long course titles / names are
                        // never cut off (the site shows them in full too).
                        Text(s.text,
                            softWrap: true,
                            style: TextStyle(
                                color: AppColors.text, fontSize: 13.5, height: 1.3)),
                        if (hasSecondary) ...[
                          const SizedBox(height: 2),
                          Text(s.secondary!,
                              style: TextStyle(
                                  color: AppColors.accentBright, fontSize: 11.5)),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        controller: widget.controller,
        focusNode: _focus,
        keyboardType: widget.keyboardType,
        style: TextStyle(color: AppColors.text, fontSize: 14),
        decoration: InputDecoration(labelText: widget.label, hintText: widget.hint),
        onChanged: (v) {
          widget.onChanged?.call(v);
          _update(v);
        },
      ),
    );
  }
}

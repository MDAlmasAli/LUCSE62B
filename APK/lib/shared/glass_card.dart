import 'package:flutter/material.dart';
import '../core/app_colors.dart';

/// Frosted-glass container — the website's `backdrop-filter: blur()` panels.
///
/// Note: the app background is a solid, opaque colour in both themes, so a real
/// `BackdropFilter` blur is visually a no-op here while costing a separate
/// render-layer + saveLayer per card — that made long lists (Students, Retake)
/// stutter badly while scrolling. We render an equivalent opaque card instead,
/// which looks identical over the solid background but scrolls smoothly.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;
  final Color? color;
  final Border? border;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 18,
    this.blur = 18,
    this.color,
    this.border,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        // Opaque equivalent of the translucent card colour (no blur needed
        // over the solid app background).
        color: color ?? AppColors.card,
        borderRadius: BorderRadius.circular(radius),
        border: border ?? Border.all(color: AppColors.border),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: card,
      ),
    );
  }
}

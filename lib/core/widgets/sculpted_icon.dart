import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
import '../theme/app_colors.dart';

/// A small dimensional glyph. The owning button supplies its accessible label.
/// Keeping the original IconData preserves familiar actions and tap targets.
class SculptedIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color? color;
  final bool active;
  final bool onDark;

  const SculptedIcon(this.icon,
      {super.key,
      this.size = 24,
      this.color,
      this.active = false,
      this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final dark = onDark || Theme.of(context).brightness == Brightness.dark;
    final face = color ??
        (active
            ? (dark ? AppColors.silverNeon : AppColors.accentStart)
            : (dark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondaryLight));
    final edge = Color.lerp(face, const Color(0xFF241442), dark ? .54 : .38)!;
    final highlight = Color.lerp(face, Colors.white, dark ? .38 : .18)!;
    final depth = size * .065;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Transform.translate(
                offset: Offset(depth, depth * 1.35),
                child: Icon(icon, size: size, color: edge, shadows: [
                  Shadow(
                      color: Colors.black.withValues(alpha: dark ? .45 : .16),
                      offset: Offset(0, depth),
                      blurRadius: size * .16),
                ]),
              ),
              Transform.translate(
                offset: Offset(depth * .45, depth * .55),
                child: Icon(icon, size: size, color: edge),
              ),
              _GradientGlyph(
                icon: icon,
                size: size,
                colors: [highlight, face, Color.lerp(face, edge, .18)!],
              ),
            ]),
      ),
    );
  }
}

/// Paint the gradient on the font glyph itself, so each small icon does not
/// require a ShaderMask/offscreen compositing layer while the feed scrolls.
class _GradientGlyph extends LeafRenderObjectWidget {
  final IconData icon;
  final double size;
  final List<Color> colors;
  const _GradientGlyph(
      {required this.icon, required this.size, required this.colors});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderGradientGlyph(
      icon, size, colors, Directionality.of(context), IconTheme.of(context));

  @override
  void updateRenderObject(
          BuildContext context, covariant _RenderGradientGlyph renderObject) =>
      renderObject.update(icon, size, colors, Directionality.of(context),
          IconTheme.of(context));
}

class _RenderGradientGlyph extends RenderBox {
  IconData _icon;
  double _iconSize;
  List<Color> _colors;
  TextDirection _direction;
  IconThemeData _theme;
  final _text = TextPainter();
  bool _paragraphDirty = true;

  _RenderGradientGlyph(
      this._icon, this._iconSize, this._colors, this._direction, this._theme);

  void update(IconData icon, double iconSize, List<Color> colors,
      TextDirection direction, IconThemeData theme) {
    if (_icon == icon &&
        _iconSize == iconSize &&
        listEquals(_colors, colors) &&
        _direction == direction &&
        _theme == theme) {
      return;
    }
    final resized = _iconSize != iconSize;
    _icon = icon;
    _iconSize = iconSize;
    _colors = colors;
    _direction = direction;
    _theme = theme;
    _paragraphDirty = true;
    if (resized) markNeedsLayout();
    markNeedsPaint();
  }

  bool get _mirrored =>
      _icon.matchTextDirection && _direction == TextDirection.rtl;

  void _layoutGlyph() {
    if (!_paragraphDirty) return;
    final opacity = _theme.opacity ?? 1;
    final foreground = Paint()
      ..shader = LinearGradient(
        // Mirroring the paragraph must not mirror the light source.
        begin: _mirrored ? Alignment.topRight : Alignment.topLeft,
        end: _mirrored ? Alignment.bottomLeft : Alignment.bottomRight,
        colors: [
          for (final color in _colors)
            color.withValues(alpha: color.a * opacity),
        ],
        stops: const [0, .48, 1],
      ).createShader(Rect.fromLTWH(0, 0, _iconSize, _iconSize));
    _text
      ..textDirection = _direction
      ..text = TextSpan(
        text: String.fromCharCode(_icon.codePoint),
        style: TextStyle(
          inherit: false,
          foreground: foreground,
          fontSize: _iconSize,
          fontFamily: _icon.fontFamily,
          package: _icon.fontPackage,
          fontFamilyFallback: _icon.fontFamilyFallback,
          fontVariations: [
            if (_theme.fill != null) FontVariation('FILL', _theme.fill!),
            if (_theme.weight != null) FontVariation('wght', _theme.weight!),
            if (_theme.grade != null) FontVariation('GRAD', _theme.grade!),
            if (_theme.opticalSize != null)
              FontVariation('opsz', _theme.opticalSize!),
          ],
          shadows: _theme.shadows,
          height: 1,
          leadingDistribution: TextLeadingDistribution.even,
        ),
      )
      ..layout();
    _paragraphDirty = false;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(Size.square(_iconSize));

  @override
  void performLayout() => size = computeDryLayout(constraints);

  @override
  void paint(PaintingContext context, Offset offset) {
    _layoutGlyph();
    final canvas = context.canvas;
    canvas.save();
    // Anchor the font shader to this glyph, rather than the whole scene.
    canvas.translate(offset.dx, offset.dy);
    if (_mirrored) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    _text.paint(
        canvas,
        Offset(
            (size.width - _text.width) / 2, (size.height - _text.height) / 2));
    canvas.restore();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }
}

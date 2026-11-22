import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// App backdrop: the void gradient with a soft violet glow near the
/// top, so flat screens still feel like they sit inside the brand.
class VoidBackground extends StatelessWidget {
  final Widget child;
  const VoidBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: kBackdropGradient),
      child: Stack(
        children: [
          Positioned(
            top: -140,
            left: -70,
            right: -70,
            child: Container(
              height: 320,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x2E8B5CF6), Color(0x008B5CF6)],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// A raised panel with real depth: gradient face, hairline border, a
/// line of light along the top edge and a deep drop shadow.
class DepthCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double radius;

  const DepthCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        gradient: kPanelGradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0x14FFFFFF)),
        boxShadow: depthShadow(),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 18,
              right: 18,
              child: Container(
                height: 1,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0x00FFFFFF),
                      Color(0x30FFFFFF),
                      Color(0x00FFFFFF),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: padding ?? const EdgeInsets.all(16),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shell that gives a bare text field a raised, inset-look surface.
/// Pair with [bareFieldDecoration] from theme.dart.
class DepthField extends StatelessWidget {
  final Widget child;
  final double radius;

  const DepthField({super.key, required this.child, this.radius = 16});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF14141F), Color(0xFF1A1A28)],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0x12FFFFFF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Glossy gradient primary button: violet gradient face, glassy top
/// sheen, a coloured glow shadow, and a subtle press-down scale.
class GradientButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const GradientButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.padding = const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
  });

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _down ? 0.97 : 1,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              gradient: kAccentGradient,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x2EFFFFFF)),
              boxShadow: [
                BoxShadow(
                  color: kAccent.withValues(alpha: _down ? 0.25 : 0.45),
                  blurRadius: _down ? 10 : 20,
                  offset: Offset(0, _down ? 3 : 8),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: DecoratedBox(decoration: BoxDecoration(gradient: kSheenGradient)),
                  ),
                  Padding(
                    padding: widget.padding,
                    child: Center(
                      child: DefaultTextStyle(
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                        child: IconTheme(
                          data: const IconThemeData(color: Colors.white),
                          child: widget.child,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Circular avatar with a per-name gradient, a soft glow and the
/// person's initial (or a group glyph).
class GradientAvatar extends StatelessWidget {
  final String label;
  final double radius;
  final bool group;

  const GradientAvatar({
    super.key,
    required this.label,
    this.radius = 22,
    this.group = false,
  });

  static const _palettes = <List<Color>>[
    [kAccentSoft, kAccentDeep],
    [Color(0xFF67E8F9), Color(0xFF0E7490)],
    [Color(0xFFF0ABFC), Color(0xFFA21CAF)],
    [Color(0xFFFCD34D), Color(0xFFB45309)],
  ];

  List<Color> get _colors {
    var h = 0;
    for (final c in label.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return _palettes[h % _palettes.length];
  }

  String get _initial {
    final t = label.replaceAll('\$', '').trim();
    return t.isEmpty ? '?' : t[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colors = _colors;
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        border: Border.all(color: const Color(0x26FFFFFF)),
        boxShadow: [
          BoxShadow(
            color: colors.last.withValues(alpha: 0.4),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: group
            ? Icon(Icons.group, color: Colors.white, size: radius * 0.95)
            : Text(
                _initial,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: radius * 0.82,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

/// The DexterChat logo mark: a glossy violet tile in slight 3D
/// perspective carrying a white chat bubble with the $ brand glyph.
class LogoMark extends StatelessWidget {
  final double size;
  const LogoMark({super.key, this.size = 96});

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.27;
    return Transform(
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0012)
        ..rotateX(-0.05)
        ..rotateY(0.09),
      alignment: Alignment.center,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: kAccentGradient,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: const Color(0x33FFFFFF)),
          boxShadow: [
            BoxShadow(
              color: kAccent.withValues(alpha: 0.5),
              blurRadius: 30,
              offset: const Offset(0, 14),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.55),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            children: [
              const Positioned.fill(
                child: DecoratedBox(decoration: BoxDecoration(gradient: kSheenGradient)),
              ),
              Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(Icons.chat_bubble_rounded,
                        color: Colors.white, size: size * 0.54),
                    Padding(
                      padding: EdgeInsets.only(bottom: size * 0.05),
                      child: Text(
                        '\$',
                        style: TextStyle(
                          color: kAccentDeep,
                          fontSize: size * 0.27,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Text filled with the accent gradient (wordmarks, hero titles).
class GradientText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final TextAlign? textAlign;

  const GradientText(this.text, {super.key, required this.style, this.textAlign});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (rect) => kAccentGradient.createShader(rect),
      child: Text(
        text,
        textAlign: textAlign,
        style: style.copyWith(color: Colors.white),
      ),
    );
  }
}

/// One-shot entrance motion: fade in while rising a few pixels.
/// Cheap (a single tween) and safe on low-end phones.
class FadeInSlide extends StatelessWidget {
  final Widget child;
  final double dy;

  const FadeInSlide({super.key, required this.child, this.dy = 18});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, dy * (1 - v)), child: child),
      ),
      child: child,
    );
  }
}

import 'package:flutter/material.dart';

/// Official Google G logo rendered via CustomPainter.
/// Faithfully replicates the 48×48 canonical Google G SVG paths, scaled to 18dp.
/// See: https://developers.google.com/identity/branding-guidelines
class GoogleGLogo extends StatelessWidget {
  const GoogleGLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: CustomPaint(painter: _GoogleGPainter()),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  static const _blue   = Color(0xFF4285F4);
  static const _red    = Color(0xFFEA4335);
  static const _yellow = Color(0xFFFBBC05);
  static const _green  = Color(0xFF34A853);

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 48;
    final sy = size.height / 48;
    final paint = Paint()..style = PaintingStyle.fill;

    Path scaled(Path p) =>
        p.transform((Matrix4.diagonal3Values(sx, sy, 1)).storage);

    // Red — top arc
    paint.color = _red;
    final red = Path()
      ..moveTo(24, 9.5)
      ..cubicTo(27.54, 9.5, 30.71, 10.72, 33.21, 13.1)
      ..lineTo(40.06, 6.25)
      ..cubicTo(35.9, 2.38, 30.47, 0, 24, 0)
      ..cubicTo(14.62, 0, 6.51, 5.38, 2.56, 13.22)
      ..lineTo(10.54, 19.41)
      ..cubicTo(12.43, 13.72, 17.74, 9.5, 24, 9.5)
      ..close();
    canvas.drawPath(scaled(red), paint);

    // Blue — right side + crossbar
    paint.color = _blue;
    final blue = Path()
      ..moveTo(46.98, 24.55)
      ..cubicTo(46.98, 22.98, 46.83, 21.46, 46.6, 20)
      ..lineTo(24, 20)
      ..lineTo(24, 29.02)
      ..lineTo(36.94, 29.02)
      ..cubicTo(36.36, 31.98, 34.68, 34.5, 32.16, 36.2)
      ..lineTo(39.89, 42.2)
      ..cubicTo(44.4, 38.02, 46.98, 31.84, 46.98, 24.55)
      ..close();
    canvas.drawPath(scaled(blue), paint);

    // Yellow — bottom-left arc
    paint.color = _yellow;
    final yellow = Path()
      ..moveTo(10.53, 28.59)
      ..cubicTo(10.05, 27.14, 9.77, 25.6, 9.77, 24)
      ..cubicTo(9.77, 22.4, 10.04, 20.86, 10.53, 19.41)
      ..lineTo(2.55, 13.22)
      ..cubicTo(0.92, 16.46, 0, 20.12, 0, 24)
      ..cubicTo(0, 27.88, 0.92, 31.54, 2.56, 34.78)
      ..lineTo(10.53, 28.59)
      ..close();
    canvas.drawPath(scaled(yellow), paint);

    // Green — bottom arc
    paint.color = _green;
    final green = Path()
      ..moveTo(24, 48)
      ..cubicTo(30.48, 48, 35.93, 45.87, 39.89, 42.2)
      ..lineTo(32.16, 36.2)
      ..cubicTo(29.98, 37.68, 27.25, 38.6, 24, 38.6)
      ..cubicTo(17.74, 38.6, 12.43, 34.38, 10.53, 28.59)
      ..lineTo(2.55, 34.78)
      ..cubicTo(6.51, 42.62, 14.62, 48, 24, 48)
      ..close();
    canvas.drawPath(scaled(green), paint);
  }

  @override
  bool shouldRepaint(_) => false;
}

/// A Google-branded sign-in button per the official branding guidelines.
/// https://developers.google.com/identity/branding-guidelines
///
/// Usage:
///   GoogleSignInButton(onPressed: _handleSignIn, isLoading: _signingIn)
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    this.isLoading = false,
    this.label = 'Sign in with Google',
  });

  final VoidCallback? onPressed;
  final bool isLoading;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 40,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1F1F1F),
          disabledBackgroundColor: Colors.white,
          elevation: 1,
          shadowColor: Colors.black26,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: const BorderSide(color: Color(0xFFDADCE0)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF4285F4),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const GoogleGLogo(),
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: const TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1F1F1F),
                      letterSpacing: 0.25,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

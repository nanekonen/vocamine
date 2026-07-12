import 'package:flutter/material.dart';

enum AcademicItemIconKind { folder, material, wordbook }

class AcademicItemIcon extends StatelessWidget {
  final AcademicItemIconKind kind;
  final Color color;
  final double size;

  const AcademicItemIcon({
    super.key,
    required this.kind,
    required this.color,
    this.size = 28,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _AcademicItemIconPainter(kind, color)),
    );
  }
}

class _AcademicItemIconPainter extends CustomPainter {
  final AcademicItemIconKind kind;
  final Color color;

  const _AcademicItemIconPainter(this.kind, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.miter;
    final w = size.width;
    final h = size.height;
    switch (kind) {
      case AcademicItemIconKind.folder:
        canvas.drawPath(
          Path()
            ..moveTo(w * .08, h * .28)
            ..lineTo(w * .4, h * .28)
            ..lineTo(w * .5, h * .16)
            ..lineTo(w * .92, h * .16)
            ..lineTo(w * .92, h * .82)
            ..lineTo(w * .08, h * .82)
            ..close(),
          paint,
        );
        break;
      case AcademicItemIconKind.material:
        canvas.drawRect(
          Rect.fromLTWH(w * .18, h * .08, w * .64, h * .84),
          paint,
        );
        for (final y in [.34, .5, .66]) {
          canvas.drawLine(Offset(w * .3, h * y), Offset(w * .7, h * y), paint);
        }
        break;
      case AcademicItemIconKind.wordbook:
        canvas.drawLine(
          Offset(w * .5, h * .14),
          Offset(w * .5, h * .86),
          paint,
        );
        canvas.drawPath(
          Path()
            ..moveTo(w * .5, h * .22)
            ..quadraticBezierTo(w * .28, h * .08, w * .1, h * .18)
            ..lineTo(w * .1, h * .78)
            ..quadraticBezierTo(w * .3, h * .68, w * .5, h * .84),
          paint,
        );
        canvas.drawPath(
          Path()
            ..moveTo(w * .5, h * .22)
            ..quadraticBezierTo(w * .72, h * .08, w * .9, h * .18)
            ..lineTo(w * .9, h * .78)
            ..quadraticBezierTo(w * .7, h * .68, w * .5, h * .84),
          paint,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _AcademicItemIconPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color;
}

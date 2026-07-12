import 'package:flutter/material.dart';

class SquareProgressIndicator extends StatelessWidget {
  final double value;
  final double size;
  final double strokeWidth;
  final Color color;
  final Color backgroundColor;
  final Widget? child;

  const SquareProgressIndicator({
    super.key,
    required this.value,
    this.size = 64,
    this.strokeWidth = 6,
    required this.color,
    required this.backgroundColor,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _SquareProgressPainter(
          value: value.clamp(0.0, 1.0),
          strokeWidth: strokeWidth,
          color: color,
          backgroundColor: backgroundColor,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _SquareProgressPainter extends CustomPainter {
  final double value;
  final double strokeWidth;
  final Color color;
  final Color backgroundColor;

  const _SquareProgressPainter({
    required this.value,
    required this.strokeWidth,
    required this.color,
    required this.backgroundColor,
  });

  Path _clockwisePath(Size size) {
    final inset = strokeWidth / 2;
    final left = inset;
    final top = inset;
    final right = size.width - inset;
    final bottom = size.height - inset;
    final middle = size.width / 2;
    return Path()
      ..moveTo(middle, top)
      ..lineTo(right, top)
      ..lineTo(right, bottom)
      ..lineTo(left, bottom)
      ..lineTo(left, top)
      ..lineTo(middle, top);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _clockwisePath(size);
    final trackPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;
    canvas.drawPath(path, trackPaint);
    final metric = path.computeMetrics().first;
    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;
    canvas.drawPath(
      metric.extractPath(0, metric.length * value),
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SquareProgressPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.color != color ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}

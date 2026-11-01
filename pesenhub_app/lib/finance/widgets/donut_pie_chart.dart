import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class PieChartSegment {
  final double value;
  final Color color;
  final String label;
  final String? subtitle;
  final IconData? icon;

  const PieChartSegment({
    required this.value,
    required this.color,
    required this.label,
    this.subtitle,
    this.icon,
  });
}

class DonutPieChart extends StatelessWidget {
  final List<PieChartSegment> segments;
  final double size;
  final double strokeWidth;
  final Widget? centerWidget;
  final String? emptyLabel;

  const DonutPieChart({
    super.key,
    required this.segments,
    this.size = 140,
    this.strokeWidth = 18,
    this.centerWidget,
    this.emptyLabel,
  });

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<double>(0, (sum, s) => sum + s.value);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _DonutChartPainter(
              segments: segments,
              total: total,
              strokeWidth: strokeWidth,
            ),
          ),
          if (centerWidget != null)
            Padding(
              padding: EdgeInsets.all(strokeWidth + 2),
              child: FittedBox(fit: BoxFit.scaleDown, child: centerWidget!),
            )
          else if (total <= 0)
            Text(
              emptyLabel ?? '0%',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.neutralTextMuted,
              ),
            ),
        ],
      ),
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  final List<PieChartSegment> segments;
  final double total;
  final double strokeWidth;

  const _DonutChartPainter({
    required this.segments,
    required this.total,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    if (total <= 0) {
      // Empty placeholder ring
      final bgPaint = Paint()
        ..color = AppColors.cardBorderModern
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      canvas.drawCircle(center, radius, bgPaint);
      return;
    }

    // Background track for clean depth
    final trackPaint = Paint()
      ..color = AppColors.surfaceVariant.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    final activeSegments = segments.where((s) => s.value > 0).toList();
    if (activeSegments.isEmpty) return;

    // If only one segment has 100% of data
    if (activeSegments.length == 1) {
      final seg = activeSegments.first;
      final paint = Paint()
        ..color = seg.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      canvas.drawCircle(center, radius, paint);
      return;
    }

    // Multiple segments with subtle gaps
    const gapAngle = 0.05; // radians gap
    final totalGaps = activeSegments.length * gapAngle;
    final availableAngle = 2 * math.pi - totalGaps;

    double startAngle = -math.pi / 2; // Start from 12 o'clock

    for (final seg in activeSegments) {
      final sweepAngle = (seg.value / total) * availableAngle;
      if (sweepAngle > 0) {
        final paint = Paint()
          ..color = seg.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round;

        canvas.drawArc(
          rect,
          startAngle + gapAngle / 2,
          sweepAngle,
          false,
          paint,
        );
        startAngle += sweepAngle + gapAngle;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return oldDelegate.total != total ||
        oldDelegate.segments != segments ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

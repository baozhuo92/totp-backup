import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// 倒计时圆环：以环形进度展示当前时间步剩余秒数。
/// 剩余 >10s 用品牌色，≤10s 切警示色（时间紧迫提示）。
class CountdownRing extends StatelessWidget {
  final int remainingSeconds;
  final int period;
  final double size;

  const CountdownRing({
    super.key,
    required this.remainingSeconds,
    required this.period,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    // period<=0 防御（正常不会出现），按 1 处理避免除零
    final safePeriod = period > 0 ? period : 1;
    final progress = remainingSeconds.clamp(0, safePeriod) / safePeriod;
    final color =
        remainingSeconds > 10 ? AppTheme.brand : AppTheme.warning;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(progress: progress, color: color),
      ),
    );
  }
}

/// 圆环绘制：底环浅灰 + 进度弧（从 12 点方向顺时针），圆头端点
class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;

  _RingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.12;
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);

    // 底环
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = color.withValues(alpha: 0.15);
    canvas.drawArc(rect, 0, math.pi * 2, false, basePaint);

    // 进度弧（12 点方向开始，顺时针）
    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress, false, progressPaint);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

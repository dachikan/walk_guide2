import 'dart:math' as math;
import 'package:flutter/material.dart';

/// レーダー風円形ビュー - 現在地と次の地点の関係を表示
class RadarView extends StatelessWidget {
  final double distanceMeters; // 次の地点までの距離（メートル）
  final double relativeBearing; // 相対方位（-180～180度）
  final String? targetName; // 次の地点の名前
  final double maxRangeMeters; // レーダーの最大表示範囲（デフォルト100m）

  const RadarView({
    super.key,
    required this.distanceMeters,
    required this.relativeBearing,
    this.targetName,
    this.maxRangeMeters = 100.0,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RadarPainter(
        distanceMeters: distanceMeters,
        relativeBearing: relativeBearing,
        targetName: targetName,
        maxRangeMeters: maxRangeMeters,
      ),
      child: Container(),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double distanceMeters;
  final double relativeBearing;
  final String? targetName;
  final double maxRangeMeters;

  _RadarPainter({
    required this.distanceMeters,
    required this.relativeBearing,
    this.targetName,
    required this.maxRangeMeters,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 20;

    // 背景円（レーダースクリーン）
    final bgPaint = Paint()
      ..color = Colors.black.withOpacity(0.8)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, bgPaint);

    // レーダーグリッド（同心円）
    final gridPaint = Paint()
      ..color = Colors.green.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(center, radius * i / 3, gridPaint);
    }

    // 十字線（N/E/S/W）
    final crossPaint = Paint()
      ..color = Colors.green.withOpacity(0.3)
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      crossPaint,
    );
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      crossPaint,
    );

    // 方位マーク（N/E/S/W）
    _drawCompassLabel(canvas, center, radius, 0, 'N');
    _drawCompassLabel(canvas, center, radius, 90, 'E');
    _drawCompassLabel(canvas, center, radius, 180, 'S');
    _drawCompassLabel(canvas, center, radius, 270, 'W');

    // 距離スケール表示
    _drawDistanceScale(canvas, center, radius);

    // 現在地（中心の青い点）
    final currentPosPaint = Paint()
      ..color = Colors.blue[400]!
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 8, currentPosPaint);

    // 現在地の外周
    final currentPosOutlinePaint = Paint()
      ..color = Colors.blue[200]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, 8, currentPosOutlinePaint);

    // 次の地点の位置計算
    final normalizedDistance = (distanceMeters / maxRangeMeters).clamp(0.0, 1.0);
    final targetRadius = radius * normalizedDistance;

    // relativeBearingを使用（0度=上、時計回り）
    final angleRad = (relativeBearing - 90) * math.pi / 180;
    final targetX = center.dx + targetRadius * math.cos(angleRad);
    final targetY = center.dy + targetRadius * math.sin(angleRad);
    final targetPos = Offset(targetX, targetY);

    // 現在地から次の地点への線
    final linePaint = Paint()
      ..color = Colors.yellow.withOpacity(0.6)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(center, targetPos, linePaint);

    // 次の地点（赤い点）
    final targetPaint = Paint()
      ..color = Colors.red[400]!
      ..style = PaintingStyle.fill;
    canvas.drawCircle(targetPos, 10, targetPaint);

    // 次の地点の外周
    final targetOutlinePaint = Paint()
      ..color = Colors.red[200]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(targetPos, 10, targetOutlinePaint);

    // 距離表示
    _drawDistanceLabel(canvas, center, targetPos, distanceMeters);

    // レーダー外周
    final borderPaint = Paint()
      ..color = Colors.green.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, borderPaint);
  }

  void _drawCompassLabel(
    Canvas canvas,
    Offset center,
    double radius,
    double angleDegrees,
    String label,
  ) {
    final angleRad = (angleDegrees - 90) * math.pi / 180;
    final x = center.dx + (radius + 12) * math.cos(angleRad);
    final y = center.dy + (radius + 12) * math.sin(angleRad);

    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.green,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(x - textPainter.width / 2, y - textPainter.height / 2),
    );
  }

  void _drawDistanceScale(Canvas canvas, Offset center, double radius) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: '${maxRangeMeters.round()}m',
        style: TextStyle(
          color: Colors.green.withOpacity(0.6),
          fontSize: 10,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx + radius - textPainter.width - 5,
        center.dy - textPainter.height / 2,
      ),
    );
  }

  void _drawDistanceLabel(
    Canvas canvas,
    Offset start,
    Offset end,
    double distanceMeters,
  ) {
    // 線の中間点に距離を表示
    final midX = (start.dx + end.dx) / 2;
    final midY = (start.dy + end.dy) / 2;

    // 背景
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(midX, midY),
        width: 60,
        height: 24,
      ),
      const Radius.circular(4),
    );
    final bgPaint = Paint()
      ..color = Colors.black.withOpacity(0.8)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(bgRect, bgPaint);

    // テキスト
    final textPainter = TextPainter(
      text: TextSpan(
        text: '${distanceMeters.round()}m',
        style: const TextStyle(
          color: Colors.yellow,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(midX - textPainter.width / 2, midY - textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_RadarPainter oldDelegate) {
    return oldDelegate.distanceMeters != distanceMeters ||
        oldDelegate.relativeBearing != relativeBearing ||
        oldDelegate.targetName != targetName;
  }
}

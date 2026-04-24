import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vmath;

/// 3D風矢印ビュー - 次の地点への方向を立体的に表示
class Arrow3DView extends StatelessWidget {
  final double distanceMeters; // 次の地点までの距離（メートル）
  final double relativeBearing; // 相対方位（-180～180度）
  final Color arrowColor;

  const Arrow3DView({
    super.key,
    required this.distanceMeters,
    required this.relativeBearing,
    this.arrowColor = Colors.blue,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _Arrow3DPainter(
        distanceMeters: distanceMeters,
        relativeBearing: relativeBearing,
        arrowColor: arrowColor,
      ),
      child: Container(),
    );
  }
}

class _Arrow3DPainter extends CustomPainter {
  final double distanceMeters;
  final double relativeBearing;
  final Color arrowColor;

  _Arrow3DPainter({
    required this.distanceMeters,
    required this.relativeBearing,
    required this.arrowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = math.min(size.width, size.height) / 3;

    // 遠近感の計算（距離が遠いほど小さく）
    final perspective = (100 / (distanceMeters + 20)).clamp(0.3, 1.0);

    // 背景（床面）
    _drawFloor(canvas, size, center);

    // 3D矢印を描画
    _draw3DArrow(canvas, center, baseRadius, perspective);

    // 距離表示
    _drawDistanceLabel(canvas, center, baseRadius);
  }

  void _drawFloor(Canvas canvas, Size size, Offset center) {
    // グリッド線を描画（遠近感のある床）
    final floorPaint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // 水平線
    for (int i = 0; i < 5; i++) {
      final y = center.dy + (i - 2) * 40;
      final startX = center.dx - 100 + i * 10;
      final endX = center.dx + 100 - i * 10;
      canvas.drawLine(
        Offset(startX, y),
        Offset(endX, y),
        floorPaint,
      );
    }

    // 垂直線
    for (int i = 0; i < 5; i++) {
      final x = center.dx + (i - 2) * 40;
      canvas.drawLine(
        Offset(x, center.dy - 80),
        Offset(x, center.dy + 80),
        floorPaint,
      );
    }
  }

  void _draw3DArrow(Canvas canvas, Offset center, double baseRadius, double perspective) {
    // 相対方位を考慮した回転角度（ラジアン）
    final angleRad = relativeBearing * math.pi / 180;

    // 矢印の基本形状（3D風）
    final arrowLength = baseRadius * perspective * 1.5;
    final arrowWidth = baseRadius * perspective * 0.6;

    // 影を描画（奥行き感）
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    final shadowPath = Path();
    shadowPath.moveTo(center.dx + 5, center.dy + 5);
    shadowPath.lineTo(
      center.dx + math.sin(angleRad) * arrowLength * 0.3 + 5,
      center.dy - math.cos(angleRad) * arrowLength * 0.3 + 5,
    );
    shadowPath.lineTo(
      center.dx + math.sin(angleRad) * arrowLength + 5,
      center.dy - math.cos(angleRad) * arrowLength + 5,
    );
    canvas.drawPath(shadowPath, shadowPaint);

    // メインの矢印（グラデーション）
    final arrowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          arrowColor.withOpacity(0.8),
          arrowColor.withOpacity(0.4),
        ],
        stops: const [0.3, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: arrowLength));

    final arrowPath = Path();

    // 矢印の軸（台形で立体感）
    final shaftWidth = arrowWidth * 0.4;
    final leftOffset = vmath.Vector2(
      -math.cos(angleRad) * shaftWidth / 2,
      -math.sin(angleRad) * shaftWidth / 2,
    );
    final rightOffset = vmath.Vector2(
      math.cos(angleRad) * shaftWidth / 2,
      math.sin(angleRad) * shaftWidth / 2,
    );

    // 下端（現在地側）
    arrowPath.moveTo(center.dx + leftOffset.x, center.dy + leftOffset.y);
    arrowPath.lineTo(center.dx + rightOffset.x, center.dy + rightOffset.y);

    // 上端（目的地側）- 遠近感で少し細く
    final tipX = center.dx + math.sin(angleRad) * arrowLength * 0.6;
    final tipY = center.dy - math.cos(angleRad) * arrowLength * 0.6;
    final narrowShaftWidth = shaftWidth * 0.7;
    final leftTipOffset = vmath.Vector2(
      -math.cos(angleRad) * narrowShaftWidth / 2,
      -math.sin(angleRad) * narrowShaftWidth / 2,
    );
    final rightTipOffset = vmath.Vector2(
      math.cos(angleRad) * narrowShaftWidth / 2,
      math.sin(angleRad) * narrowShaftWidth / 2,
    );

    arrowPath.lineTo(tipX + rightTipOffset.x, tipY + rightTipOffset.y);
    arrowPath.lineTo(tipX + leftTipOffset.x, tipY + leftTipOffset.y);
    arrowPath.close();
    canvas.drawPath(arrowPath, arrowPaint);

    // 矢印の先端（三角形）
    final headPaint = Paint()
      ..color = arrowColor
      ..style = PaintingStyle.fill;

    final headPath = Path();
    final headBaseX = tipX;
    final headBaseY = tipY;
    final headTipX = center.dx + math.sin(angleRad) * arrowLength;
    final headTipY = center.dy - math.cos(angleRad) * arrowLength;
    final headWidth = arrowWidth * 0.8;

    headPath.moveTo(
      headBaseX - math.cos(angleRad) * headWidth / 2,
      headBaseY - math.sin(angleRad) * headWidth / 2,
    );
    headPath.lineTo(headTipX, headTipY);
    headPath.lineTo(
      headBaseX + math.cos(angleRad) * headWidth / 2,
      headBaseY + math.sin(angleRad) * headWidth / 2,
    );
    headPath.close();
    canvas.drawPath(headPath, headPaint);

    // ハイライト（光沢感）
    final highlightPaint = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(center.dx + leftOffset.x * 0.5, center.dy + leftOffset.y * 0.5),
      Offset(tipX + leftTipOffset.x * 0.5, tipY + leftTipOffset.y * 0.5),
      highlightPaint,
    );
  }

  void _drawDistanceLabel(Canvas canvas, Offset center, double baseRadius) {
    // 距離表示の背景
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + baseRadius + 30),
        width: 100,
        height: 30,
      ),
      const Radius.circular(15),
    );
    final bgPaint = Paint()
      ..color = Colors.black.withOpacity(0.7)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(bgRect, bgPaint);

    // 距離テキスト
    final textPainter = TextPainter(
      text: TextSpan(
        text: '${distanceMeters.round()}m',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy + baseRadius + 30 - textPainter.height / 2,
      ),
    );

    // 方向テキスト
    String directionText;
    if (relativeBearing.abs() < 15) {
      directionText = 'まっすぐ';
    } else if (relativeBearing > 0) {
      directionText = '右へ ${relativeBearing.round().abs()}°';
    } else {
      directionText = '左へ ${relativeBearing.round().abs()}°';
    }

    final dirTextPainter = TextPainter(
      text: TextSpan(
        text: directionText,
        style: TextStyle(
          color: Colors.yellow[300],
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    dirTextPainter.layout();
    dirTextPainter.paint(
      canvas,
      Offset(
        center.dx - dirTextPainter.width / 2,
        center.dy + baseRadius + 55,
      ),
    );
  }

  @override
  bool shouldRepaint(_Arrow3DPainter oldDelegate) {
    return oldDelegate.distanceMeters != distanceMeters ||
        oldDelegate.relativeBearing != relativeBearing;
  }
}

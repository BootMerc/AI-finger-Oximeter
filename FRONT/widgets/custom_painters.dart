import 'dart:math';
import 'package:flutter/material.dart';

// ── ECG waveform trace (dashboard BPM card header animation) ────────────────
class ECGPainter extends CustomPainter {
  final double progress;
  final Color color;
  ECGPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final pts = _buildPoints(size);
    final end = (progress * pts.length).floor().clamp(0, pts.length);
    if (end < 2) return;

    final glow = Paint()
      ..color = color.withOpacity(0.25)
      ..strokeWidth = 7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

    final line = Paint()
      ..color = color
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < end; i++) path.lineTo(pts[i].dx, pts[i].dy);

    canvas.drawPath(path, glow);
    canvas.drawPath(path, line);

    if (end < pts.length) {
      final h = pts[end - 1];
      canvas.drawCircle(h, 4.5,
          Paint()
            ..color = color
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawCircle(h, 3, Paint()..color = Colors.white);
    }
  }

  List<Offset> _buildPoints(Size s) {
    final pts = <Offset>[];
    final mid = s.height * 0.58;

    void cycle(double sx, double cw) {
      for (double x = sx; x < sx + cw * 0.12; x += 2) pts.add(Offset(x, mid));
      final pS = sx + cw * 0.12;
      final pW = cw * 0.10;
      for (double t = 0; t <= 1; t += 0.06) {
        pts.add(Offset(pS + t * pW, mid - sin(t * pi) * s.height * 0.14));
      }
      final prS = pS + pW;
      for (double x = prS; x < prS + cw * 0.04; x += 2) pts.add(Offset(x, mid));
      final qS = prS + cw * 0.04;
      pts
        ..add(Offset(qS, mid))
        ..add(Offset(qS + cw * 0.025, mid + s.height * 0.09));
      final rP = qS + cw * 0.05;
      pts.add(Offset(rP, mid - s.height * 0.80));
      final sP = rP + cw * 0.03;
      pts.add(Offset(sP, mid + s.height * 0.11));
      for (double t = 0; t <= 1; t += 0.12) {
        pts.add(Offset(sP + t * cw * 0.07, mid + s.height * 0.11 * (1 - t)));
      }
      final tS = sP + cw * 0.07;
      final tW = cw * 0.14;
      for (double t = 0; t <= 1; t += 0.06) {
        pts.add(Offset(tS + t * tW, mid - sin(t * pi) * s.height * 0.26));
      }
      final tail = tS + tW;
      for (double x = tail; x < sx + cw; x += 2) pts.add(Offset(x, mid));
    }

    cycle(0, s.width * 0.48);
    cycle(s.width * 0.48, s.width * 0.52);
    return pts;
  }

  @override
  bool shouldRepaint(ECGPainter old) => old.progress != progress;
}

// ── Raw PPG sparkline (live waveform under BPM value) ───────────────────────
class SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color color;
  SparklinePainter(this.data, this.color);

  @override
  void paint(Canvas canvas, Size s) {
    if (data.length < 2) return;
    final mn = data.reduce(min);
    final mx = data.reduce(max);
    final rng = (mx - mn) == 0 ? 1.0 : mx - mn;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path();
    for (int i = 0; i < data.length; i++) {
      final x = i / (data.length - 1) * s.width;
      final y = s.height - (data[i] - mn) / rng * s.height;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(SparklinePainter o) => o.data != data;
}

// ── Wellness Score arc gauge (270° sweep, glow + crisp layer) ───────────────
//
// Usage:
//   CustomPaint(
//     painter: WellnessGaugePainter(progress: score / 100.0, color: color),
//     child: ...,
//   )
class WellnessGaugePainter extends CustomPainter {
  final double progress; // 0.0 – 1.0
  final Color color;
  WellnessGaugePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = min(size.width, size.height) / 2 - 11;

    // 270° arc starting at 7-o'clock (135°)
    const startAngle = pi * 0.75;
    const sweepTotal = pi * 1.5;

    // Background track
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      startAngle,
      sweepTotal,
      false,
      Paint()
        ..color = Colors.white.withOpacity(0.07)
        ..strokeWidth = 10
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    if (progress <= 0) return;

    final sweep = sweepTotal * progress;

    // Glow layer
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      startAngle,
      sweep,
      false,
      Paint()
        ..color = color.withOpacity(0.35)
        ..strokeWidth = 14
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Crisp foreground arc
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      startAngle,
      sweep,
      false,
      Paint()
        ..color = color
        ..strokeWidth = 8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(WellnessGaugePainter old) =>
      old.progress != progress || old.color != color;
}
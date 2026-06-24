import 'dart:math' as math;

import 'package:flutter/material.dart';

enum WorkingAnimationStyle {
  off('off', 'Off'),
  digitalFlow('digital_flow', 'Digital flow'),
  neuralLattice('neural_lattice', 'Neural lattice'),
  orbitSync('orbit_sync', 'Orbit sync'),
  scanLine('scan_line', 'Scan line'),
  dataPackets('data_packets', 'Data packets'),
  pulseSpectrum('pulse_spectrum', 'Pulse spectrum'),
  randomWalk('random_walk', 'Random walk'),
  noiseField('noise_field', 'Noise field');

  const WorkingAnimationStyle(this.storageValue, this.label);

  final String storageValue;
  final String label;
  bool get enabled => this != WorkingAnimationStyle.off;

  static WorkingAnimationStyle fromStorage(String? value) {
    final cleaned = value?.trim();
    for (final style in WorkingAnimationStyle.values) {
      if (style.storageValue == cleaned) return style;
    }
    return WorkingAnimationStyle.digitalFlow;
  }
}

class DigitalThinkingIndicator extends StatefulWidget {
  const DigitalThinkingIndicator({
    super.key,
    required this.color,
    this.style = WorkingAnimationStyle.digitalFlow,
    this.speed = 1.0,
    this.width = 42,
    this.height = 18,
  });

  final Color color;
  final WorkingAnimationStyle style;
  final double speed;
  final double width;
  final double height;

  @override
  State<DigitalThinkingIndicator> createState() =>
      _DigitalThinkingIndicatorState();
}

class _DigitalThinkingIndicatorState extends State<DigitalThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _durationForSpeed(widget.speed),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant DigitalThinkingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.speed == widget.speed) return;
    _controller.duration = _durationForSpeed(widget.speed);
    if (!_controller.isAnimating) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: CustomPaint(
        painter: _DigitalThinkingPainter(
          animation: _controller,
          color: widget.color,
          style: widget.style,
        ),
      ),
    );
  }

  Duration _durationForSpeed(double speed) {
    final safeSpeed = speed.clamp(0.1, 5.0);
    return Duration(milliseconds: (2560 / safeSpeed).round());
  }
}

class _DigitalThinkingPainter extends CustomPainter {
  const _DigitalThinkingPainter({
    required this.animation,
    required this.color,
    required this.style,
  }) : super(repaint: animation);

  final AnimationController animation;
  final Color color;
  final WorkingAnimationStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    switch (style) {
      case WorkingAnimationStyle.off:
        return;
      case WorkingAnimationStyle.digitalFlow:
        _paintDigitalFlow(canvas, size);
        break;
      case WorkingAnimationStyle.neuralLattice:
        _paintNeuralLattice(canvas, size);
        break;
      case WorkingAnimationStyle.orbitSync:
        _paintOrbitSync(canvas, size);
        break;
      case WorkingAnimationStyle.scanLine:
        _paintScanLine(canvas, size);
        break;
      case WorkingAnimationStyle.dataPackets:
        _paintDataPackets(canvas, size);
        break;
      case WorkingAnimationStyle.pulseSpectrum:
        _paintPulseSpectrum(canvas, size);
        break;
      case WorkingAnimationStyle.randomWalk:
        _paintRandomWalk(canvas, size);
        break;
      case WorkingAnimationStyle.noiseField:
        _paintNoiseField(canvas, size);
        break;
    }
  }

  void _paintDigitalFlow(Canvas canvas, Size size) {
    final t = _time();
    final centerY = size.height / 2;
    final count = size.width > 34 ? 7 : 5;
    final step = size.width / (count - 1);
    final points = <Offset>[];

    for (var index = 0; index < count; index++) {
      final phase = (t * math.pi * 2) + (index * 0.72);
      final x = index * step;
      final y = centerY + math.sin(phase) * size.height * 0.22;
      points.add(Offset(x, y));
    }

    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.34)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, linePaint);

    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      final pulse = (math.sin((t * math.pi * 2) + (index * 0.95)) + 1) / 2;
      final radius = 1.8 + (pulse * 1.5);
      final nodePaint = Paint()
        ..color = color.withValues(alpha: 0.42 + (pulse * 0.5))
        ..style = PaintingStyle.fill;
      canvas.drawCircle(point, radius, nodePaint);

      if (index.isEven) {
        final tickPaint = Paint()
          ..color = color.withValues(alpha: 0.16 + (pulse * 0.22))
          ..strokeWidth = 1
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(point.dx, centerY - size.height * 0.42),
          Offset(point.dx, centerY - size.height * 0.32),
          tickPaint,
        );
        canvas.drawLine(
          Offset(point.dx, centerY + size.height * 0.32),
          Offset(point.dx, centerY + size.height * 0.42),
          tickPaint,
        );
      }
    }
  }

  void _paintNeuralLattice(Canvas canvas, Size size) {
    final t = _time();
    final rows = 3;
    final columns = size.width > 40 ? 6 : 4;
    final xStep = size.width / (columns - 1);
    final yStep = size.height / (rows - 1);
    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.16)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;

    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns - 1; column++) {
        final a = Offset(column * xStep, row * yStep);
        final b = Offset((column + 1) * xStep, row * yStep);
        canvas.drawLine(a, b, linePaint);
      }
    }
    for (var column = 0; column < columns; column++) {
      canvas.drawLine(
        Offset(column * xStep, 0),
        Offset(column * xStep, size.height),
        linePaint..color = color.withValues(alpha: 0.08),
      );
    }

    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final phase = (t + ((row + column) * 0.11)) % 1;
        final pulse = (math.sin(phase * math.pi * 2) + 1) / 2;
        final radius = 1.4 + (pulse * 1.9);
        final paint = Paint()
          ..color = color.withValues(alpha: 0.28 + (pulse * 0.6));
        canvas.drawCircle(Offset(column * xStep, row * yStep), radius, paint);
      }
    }
  }

  void _paintOrbitSync(Canvas canvas, Size size) {
    final t = _time();
    final center = Offset(size.width / 2, size.height / 2);
    final radiusX = size.width * 0.38;
    final radiusY = size.height * 0.32;
    final orbitPaint = Paint()
      ..color = color.withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    canvas.drawOval(
      Rect.fromCenter(center: center, width: radiusX * 2, height: radiusY * 2),
      orbitPaint,
    );
    canvas.drawCircle(
      center,
      math.max(1.8, size.height * 0.12),
      Paint()..color = color.withValues(alpha: 0.4),
    );

    for (var index = 0; index < 5; index++) {
      final angle = (t * math.pi * 2) + (index * math.pi * 0.4);
      final depth = (math.sin(angle) + 1) / 2;
      final point = Offset(
        center.dx + math.cos(angle) * radiusX,
        center.dy + math.sin(angle) * radiusY,
      );
      canvas.drawCircle(
        point,
        1.5 + depth * 2.1,
        Paint()..color = color.withValues(alpha: 0.28 + depth * 0.62),
      );
    }
  }

  void _paintScanLine(Canvas canvas, Size size) {
    final t = _time() % 1;
    final scanX = size.width * t;
    final backgroundPaint = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    for (var y = 2.0; y < size.height; y += 5) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), backgroundPaint);
    }

    final scanPaint = Paint()
      ..color = color.withValues(alpha: 0.72)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(scanX, 0), Offset(scanX, size.height), scanPaint);
    for (var index = 0; index < 6; index++) {
      final x = (scanX - (index * size.width / 7)) % size.width;
      final alpha = (0.5 - index * 0.06).clamp(0.12, 0.5).toDouble();
      canvas.drawCircle(
        Offset(x, size.height * (0.24 + (index % 3) * 0.26)),
        1.5,
        Paint()..color = color.withValues(alpha: alpha),
      );
    }
  }

  void _paintDataPackets(Canvas canvas, Size size) {
    final t = _time();
    final trackPaint = Paint()
      ..color = color.withValues(alpha: 0.14)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    final yValues = [size.height * 0.28, size.height * 0.5, size.height * 0.72];
    for (final y in yValues) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), trackPaint);
    }

    for (var index = 0; index < 7; index++) {
      final lane = index % yValues.length;
      final progress = (t + index * 0.17) % 1;
      final packetWidth = math.max(4.0, size.width * 0.12);
      final x = progress * (size.width + packetWidth) - packetWidth;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          x,
          yValues[lane] - size.height * 0.11,
          packetWidth,
          math.max(3.0, size.height * 0.18),
        ),
        const Radius.circular(2),
      );
      final pulse = (math.sin((progress + lane * 0.21) * math.pi * 2) + 1) / 2;
      canvas.drawRRect(
        rect,
        Paint()..color = color.withValues(alpha: 0.28 + pulse * 0.5),
      );
    }
  }

  void _paintPulseSpectrum(Canvas canvas, Size size) {
    final t = _time();
    final bars = size.width > 40 ? 9 : 6;
    final gap = size.width * 0.045;
    final barWidth = (size.width - (gap * (bars - 1))) / bars;
    for (var index = 0; index < bars; index++) {
      final phase = (t * math.pi * 2) + index * 0.55;
      final pulse = (math.sin(phase) + 1) / 2;
      final height = size.height * (0.22 + pulse * 0.72);
      final left = index * (barWidth + gap);
      final top = (size.height - height) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, barWidth, height),
          Radius.circular(barWidth / 2),
        ),
        Paint()..color = color.withValues(alpha: 0.28 + pulse * 0.58),
      );
    }
  }

  void _paintRandomWalk(Canvas canvas, Size size) {
    final t = _time();
    final points = <Offset>[];
    const count = 9;
    for (var index = 0; index < count; index++) {
      final x = size.width * index / (count - 1);
      final drift =
          math.sin((t * 2.7 + index * 0.37) * math.pi * 2) * 0.18 +
          math.sin((t * 5.1 + index * 0.19) * math.pi * 2) * 0.09;
      final y = size.height * (0.5 + drift).clamp(0.12, 0.88);
      points.add(Offset(x, y));
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.32)
        ..strokeWidth = 1.25
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );

    for (var index = 0; index < points.length; index++) {
      final blink = _noise(t, index, 0);
      canvas.drawCircle(
        points[index],
        1.2 + blink * 2.1,
        Paint()..color = color.withValues(alpha: 0.2 + blink * 0.68),
      );
    }
  }

  void _paintNoiseField(Canvas canvas, Size size) {
    final t = _time();
    final columns = size.width > 40 ? 8 : 6;
    final rows = 3;
    final xStep = size.width / (columns - 1);
    final yStep = size.height / (rows - 1);

    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final pulse = _noise(t, column, row);
        if (pulse < 0.28) continue;
        final point = Offset(column * xStep, row * yStep);
        canvas.drawCircle(
          point,
          0.9 + pulse * 2.4,
          Paint()..color = color.withValues(alpha: 0.14 + pulse * 0.66),
        );
      }
    }
  }

  double _noise(double t, int x, int y) {
    final a = math.sin((x * 12.9898) + (y * 78.233) + (t * 17.17));
    final b = math.sin((x * 39.3468) + (y * 11.135) - (t * 31.43));
    return ((a + b + 2) / 4).clamp(0, 1).toDouble();
  }

  double _time() {
    return (animation.lastElapsedDuration ?? Duration.zero).inMicroseconds /
        Duration.microsecondsPerSecond;
  }

  @override
  bool shouldRepaint(covariant _DigitalThinkingPainter oldDelegate) {
    return oldDelegate.animation != animation ||
        oldDelegate.color != color ||
        oldDelegate.style != style;
  }
}

class SpeakingEqualizer extends StatelessWidget {
  const SpeakingEqualizer({
    super.key,
    required this.animation,
    required this.color,
  });

  final Animation<double> animation;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 136,
      height: 16,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var index = 0; index < 18; index++)
                _EqualizerBar(
                  color: color,
                  height: _barHeight(animation.value, index),
                ),
            ],
          );
        },
      ),
    );
  }

  double _barHeight(double value, int index) {
    final phase = (value + (index * 0.1)) % 1.0;
    final rise = 1 - ((phase - 0.5).abs() * 2);
    return 4 + (10 * rise.clamp(0, 1));
  }
}

class _EqualizerBar extends StatelessWidget {
  const _EqualizerBar({required this.color, required this.height});

  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 3,
      height: height,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

part of '../main.dart';

class _LiveRecordingWaveform extends StatefulWidget {
  const _LiveRecordingWaveform({
    required this.level,
    required this.barCount,
    required this.decay,
    required this.color,
  });

  final ValueListenable<double> level;
  final int barCount;
  final double decay;
  final Color color;

  @override
  State<_LiveRecordingWaveform> createState() => _LiveRecordingWaveformState();
}

class _LiveRecordingWaveformState extends State<_LiveRecordingWaveform>
    with SingleTickerProviderStateMixin {
  static const _history = Duration(milliseconds: 3500);
  late List<double> _bars;
  late final AnimationController _animation;
  double _smoothedLevel = 0;
  DateTime? _lastSampleAt;

  int get _barCount => widget.barCount.clamp(12, 48).toInt();

  @override
  void initState() {
    super.initState();
    _bars = List<double>.filled(_barCount, 0);
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..addListener(_sampleLevel);
    _animation.repeat();
  }

  @override
  void didUpdateWidget(covariant _LiveRecordingWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.barCount != widget.barCount) {
      _bars = List<double>.filled(_barCount, 0);
      _smoothedLevel = 0;
      _lastSampleAt = null;
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  void _sampleLevel() {
    final now = DateTime.now();
    final sampleInterval = Duration(
      microseconds: _history.inMicroseconds ~/ _barCount,
    );
    if (_lastSampleAt != null &&
        now.difference(_lastSampleAt!) < sampleInterval) {
      return;
    }
    _lastSampleAt = now;
    final level = widget.level.value.clamp(0.0, 1.0);
    final responsiveLevel = math.pow(level, 0.7).toDouble();
    final smoothing = responsiveLevel < _smoothedLevel ? widget.decay : 0.9;
    _smoothedLevel += (responsiveLevel - _smoothedLevel) * smoothing;
    final idleLevel =
        0.055 + math.sin(_animation.value * math.pi * 2).abs() * 0.035;
    final value = math.max(_smoothedLevel, idleLevel).toDouble();
    if (!mounted) return;
    setState(() {
      _bars
        ..removeAt(0)
        ..add(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RecordingWaveformPainter(
        samples: List<double>.of(_bars),
        color: widget.color,
      ),
      child: const SizedBox.expand(),
    );
  }
}

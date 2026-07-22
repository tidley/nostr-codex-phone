part of '../main.dart';

class _WaveformSample {
  const _WaveformSample({required this.timestamp, required this.value});

  final DateTime timestamp;
  final double value;
}

class _LiveRecordingWaveform extends StatefulWidget {
  const _LiveRecordingWaveform({
    required this.level,
    required this.duration,
    required this.decay,
    required this.compression,
    required this.color,
  });

  final ValueListenable<double> level;
  final double duration;
  final double decay;
  final double compression;
  final Color color;

  @override
  State<_LiveRecordingWaveform> createState() => _LiveRecordingWaveformState();
}

class _LiveRecordingWaveformState extends State<_LiveRecordingWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  final _samples = <_WaveformSample>[];
  DateTime? _lastSampleAt;
  double _smoothedLevel = 0;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_advanceWaveform);
    widget.level.addListener(_recordAmplitudeSample);
    _recordAmplitudeSample();
    _animation.repeat();
  }

  @override
  void didUpdateWidget(covariant _LiveRecordingWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.level != widget.level) {
      oldWidget.level.removeListener(_recordAmplitudeSample);
      widget.level.addListener(_recordAmplitudeSample);
      _lastSampleAt = null;
    }
  }

  @override
  void dispose() {
    widget.level.removeListener(_recordAmplitudeSample);
    _animation.dispose();
    super.dispose();
  }

  void _advanceWaveform() {
    final now = DateTime.now();
    _samples.removeWhere(
      (sample) => now.difference(sample.timestamp) > _visibleDuration,
    );
  }

  void _recordAmplitudeSample() {
    final now = DateTime.now();
    final interval = Duration(
      microseconds: (Duration.microsecondsPerSecond / _sampleRate).round(),
    );
    if (_lastSampleAt != null && now.difference(_lastSampleAt!) < interval) {
      return;
    }
    _lastSampleAt = now;
    _pushSample(now);
    if (mounted) setState(() {});
  }

  void _pushSample(DateTime timestamp) {
    final level = widget.level.value.clamp(0.0, 1.0);
    final responsiveLevel = math.pow(level, _compressionExponent).toDouble();
    final smoothing = responsiveLevel < _smoothedLevel
        ? _fadeSmoothing(widget.decay)
        : 0.5;
    _smoothedLevel += (responsiveLevel - _smoothedLevel) * smoothing;
    _samples.add(_WaveformSample(timestamp: timestamp, value: _smoothedLevel));
  }

  static const _sampleRate = 60.0;

  Duration get _visibleDuration => Duration(
    microseconds: (_safeDuration * Duration.microsecondsPerSecond).round(),
  );

  double get _safeDuration => widget.duration.clamp(0.1, 20.0).toDouble();

  double _fadeSmoothing(double fade) {
    if (fade <= 1) return fade.clamp(0.0, 1.0).toDouble();
    return 1 - math.pow(0.4, fade).toDouble();
  }

  double get _compressionExponent {
    final compression = widget.compression.clamp(0.0, 1.0).toDouble();
    if (compression <= 0.5) return 1 + (0.5 - compression) * 3;
    return 1 - (compression - 0.5) * 1.4;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) => CustomPaint(
        painter: _RecordingWaveformPainter(
          samples: List<_WaveformSample>.of(_samples),
          now: DateTime.now(),
          visibleDuration: _visibleDuration,
          color: widget.color,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

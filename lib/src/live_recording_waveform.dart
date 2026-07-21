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
    required this.sampleRate,
    required this.color,
  });

  final ValueListenable<double> level;
  final double duration;
  final double decay;
  final double compression;
  final double sampleRate;
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
    _animation.repeat();
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  void _advanceWaveform() {
    final now = DateTime.now();
    final interval = Duration(
      microseconds: (Duration.microsecondsPerSecond / _safeSampleRate).round(),
    );
    var nextSampleAt = _lastSampleAt;
    if (nextSampleAt == null) {
      _pushSample(now);
      nextSampleAt = now;
    }
    while (!nextSampleAt!.add(interval).isAfter(now)) {
      nextSampleAt = nextSampleAt.add(interval);
      _pushSample(nextSampleAt);
    }
    _lastSampleAt = nextSampleAt;
    _samples.removeWhere(
      (sample) => now.difference(sample.timestamp) > _visibleDuration,
    );
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

  double get _safeSampleRate => widget.sampleRate.clamp(1.0, 240.0).toDouble();

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

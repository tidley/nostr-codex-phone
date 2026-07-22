part of '../main.dart';

class _LiveRecordingWaveform extends StatefulWidget {
  const _LiveRecordingWaveform({
    required this.level,
    required this.speed,
    required this.decay,
    required this.compression,
    required this.rmsSmoothing,
    required this.color,
  });

  final ValueListenable<double> level;
  final double speed;
  final double decay;
  final double compression;
  final double rmsSmoothing;
  final Color color;

  @override
  State<_LiveRecordingWaveform> createState() => _LiveRecordingWaveformState();
}

class _LiveRecordingWaveformState extends State<_LiveRecordingWaveform>
    with SingleTickerProviderStateMixin {
  static const _sampleRate = 96.0;
  static const _sampleCount = 360;

  late final AnimationController _animation;
  final _random = math.Random();
  final _samples = List<double>.filled(_sampleCount, 0, growable: true);
  final _rmsLevels = <double>[];
  double _lastProgress = 0;
  double _sampleCarry = 0;
  double _smoothedLevel = 0;

  @override
  void initState() {
    super.initState();
    _seedSamples();
    _animation = AnimationController(
      vsync: this,
      duration: _durationForSpeed(widget.speed),
    )..addListener(_advanceWaveform);
    _animation.repeat();
  }

  @override
  void didUpdateWidget(covariant _LiveRecordingWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.speed != widget.speed) {
      _animation.duration = _durationForSpeed(widget.speed);
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  void _advanceWaveform() {
    final progress = _animation.value;
    var delta = progress - _lastProgress;
    if (delta < 0) delta += 1;
    _lastProgress = progress;

    _sampleCarry += delta * _sampleRate * _safeSpeed;
    while (_sampleCarry >= 1) {
      _sampleCarry -= 1;
      _pushSample();
    }
  }

  void _pushSample() {
    final rawLevel = widget.level.value.clamp(0.0, 1.0).toDouble();
    final rmsWindow = math.max(
      1,
      (widget.rmsSmoothing.clamp(0.0, 1.0) * _sampleRate * _safeSpeed).round(),
    );
    _rmsLevels.add(rawLevel * rawLevel);
    if (_rmsLevels.length > rmsWindow) _rmsLevels.removeAt(0);
    final level = math.sqrt(
      _rmsLevels.reduce((total, value) => total + value) / _rmsLevels.length,
    );
    final responsiveLevel = math.pow(level, _compressionExponent).toDouble();
    final smoothing = responsiveLevel < _smoothedLevel
        ? _fadeSmoothing(widget.decay)
        : 0.5;
    _smoothedLevel += (responsiveLevel - _smoothedLevel) * smoothing;
    final envelope = 0.05 + _smoothedLevel * 0.95;
    final previous = _samples.isEmpty ? 0.0 : _samples.last;
    final noise = _random.nextDouble() * 2 - 1;
    _samples.add((previous * 0.28 + noise * 0.72) * envelope);
    if (_samples.length > _sampleCount) {
      _samples.removeRange(0, _samples.length - _sampleCount);
    }
  }

  void _seedSamples() {
    _samples
      ..clear()
      ..addAll(
        List<double>.generate(
          _sampleCount,
          (_) => (_random.nextDouble() * 2 - 1) * 0.04,
        ),
      );
  }

  double get _safeSpeed => widget.speed.clamp(0.1875, 37.5).toDouble();

  Duration _durationForSpeed(double speed) => Duration(
    milliseconds: (1450 / speed.clamp(0.1875, 37.5).toDouble()).round(),
  );

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
          samples: List<double>.of(_samples),
          progress: _animation.value,
          color: widget.color,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

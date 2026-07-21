part of '../main.dart';

class _LiveRecordingWaveform extends StatefulWidget {
  const _LiveRecordingWaveform({
    required this.level,
    required this.decay,
    required this.color,
  });

  final ValueListenable<double> level;
  final double decay;
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
  double _lastProgress = 0;
  double _sampleCarry = 0;
  double _smoothedLevel = 0;

  @override
  void initState() {
    super.initState();
    _seedSamples();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
    )..addListener(_advanceWaveform);
    _animation.repeat();
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

    _sampleCarry += delta * _sampleRate;
    while (_sampleCarry >= 1) {
      _sampleCarry -= 1;
      _pushSample();
    }
  }

  void _pushSample() {
    final level = widget.level.value.clamp(0.0, 1.0);
    final responsiveLevel = math.pow(level, 0.55).toDouble();
    final smoothing = responsiveLevel < _smoothedLevel ? widget.decay : 0.5;
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

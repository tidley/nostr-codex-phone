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

class _LiveRecordingWaveformState extends State<_LiveRecordingWaveform> {
  static const _history = Duration(milliseconds: 3500);
  late List<double> _bars;
  double _smoothedLevel = 0;
  DateTime? _lastSampleAt;

  int get _barCount => widget.barCount.clamp(12, 48).toInt();

  @override
  void initState() {
    super.initState();
    _bars = List<double>.filled(_barCount, 0);
    widget.level.addListener(_updateLevel);
  }

  @override
  void didUpdateWidget(covariant _LiveRecordingWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.level != widget.level) {
      oldWidget.level.removeListener(_updateLevel);
      widget.level.addListener(_updateLevel);
    }
    if (oldWidget.barCount != widget.barCount) {
      _bars = List<double>.filled(_barCount, 0);
      _smoothedLevel = 0;
      _lastSampleAt = null;
    }
  }

  @override
  void dispose() {
    widget.level.removeListener(_updateLevel);
    super.dispose();
  }

  void _updateLevel() {
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
    final value = _smoothedLevel < 0.015 ? 0.0 : _smoothedLevel;
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

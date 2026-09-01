import 'package:flutter/material.dart';

/// Small colored chip for a HoneyBatch's lifecycle status
/// (HARVESTED / PROCESSED / QUALITY_CHECKED / PACKAGED).
class BatchStatusBadge extends StatelessWidget {
  final String status;

  const BatchStatusBadge({super.key, required this.status});

  static const Map<String, Color> _colors = {
    'HARVESTED': Colors.amber,
    'PROCESSED': Colors.blue,
    'QUALITY_CHECKED': Colors.purple,
    'PACKAGED': Colors.green,
  };

  String get _label => status.replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    final color = _colors[status] ?? Colors.grey;
    return Chip(
      label: Text(_label, style: TextStyle(color: color.shade900, fontWeight: FontWeight.w600)),
      backgroundColor: color.shade50,
      side: BorderSide(color: color.shade200),
      visualDensity: VisualDensity.compact,
    );
  }
}

extension on Color {
  Color get shade900 => Color.lerp(this, Colors.black, 0.55)!;
  Color get shade200 => Color.lerp(this, Colors.white, 0.4)!;
  Color get shade50 => Color.lerp(this, Colors.white, 0.85)!;
}

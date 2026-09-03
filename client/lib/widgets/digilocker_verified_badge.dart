import 'package:flutter/material.dart';

/// Shows whether an apiary's FSSAI license number has been independently
/// confirmed via DigiLocker (green check) or is only self-reported
/// (grey) -- the same visual language as [BlockchainVerifiedBadge], but for
/// a separate, off-chain regulatory trust signal rather than provenance
/// data. `licenseNumber` renders underneath when non-empty.
class DigilockerVerifiedBadge extends StatelessWidget {
  final bool verified;
  final String? licenseNumber;
  final bool dense;

  const DigilockerVerifiedBadge({super.key, required this.verified, this.licenseNumber, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final color = verified ? Colors.green.shade700 : Colors.grey.shade600;
    final icon = verified ? Icons.verified_user : Icons.pending_outlined;
    final label = verified ? 'FSSAI license verified via DigiLocker' : 'FSSAI license not verified';

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: dense ? 16 : 20, color: color),
        const SizedBox(width: 6),
        Flexible(child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: dense ? 12 : 14))),
      ],
    );

    if (licenseNumber == null || licenseNumber!.isEmpty) return row;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        row,
        const SizedBox(height: 2),
        Text(
          'license: $licenseNumber',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontFamily: 'monospace'),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

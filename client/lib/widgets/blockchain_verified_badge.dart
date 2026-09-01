import 'package:flutter/material.dart';

/// Shows whether a piece of data has been independently verified against
/// the on-chain record (green check) or not (grey/red), optionally with the
/// transaction hash beneath it.
class BlockchainVerifiedBadge extends StatelessWidget {
  final bool verified;
  final String? txHash;
  final bool dense;

  const BlockchainVerifiedBadge({super.key, required this.verified, this.txHash, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final color = verified ? Colors.green.shade700 : Colors.red.shade700;
    final icon = verified ? Icons.verified : Icons.error_outline;
    final label = verified ? 'Verified on-chain' : 'Not verified';

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: dense ? 16 : 20, color: color),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: dense ? 12 : 14)),
      ],
    );

    if (txHash == null || txHash!.isEmpty) return row;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        row,
        const SizedBox(height: 2),
        Text(
          'tx: $txHash',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontFamily: 'monospace'),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

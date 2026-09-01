import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'blockchain_verified_badge.dart';

const Map<String, IconData> _stageIcons = {
  'HARVESTED': Icons.grass,
  'PROCESSED': Icons.filter_alt,
  'QUALITY_CHECKED': Icons.fact_check,
  'PACKAGED': Icons.inventory_2,
};

/// Chronological event history shared by the authenticated batch-detail
/// screens and the public consumer trace page. Each entry is a raw
/// GraphQL-shaped map with at least `eventType`, `timestamp`, `txHash`,
/// `chainStatus`; an optional `chainVerified` bool (present only on the
/// public trace query) renders a live verification badge instead of just
/// the stored chain status.
class EventTimeline extends StatelessWidget {
  final List<dynamic> events;

  const EventTimeline({super.key, required this.events});

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Text('No events recorded yet.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < events.length; i++) _EventTile(event: events[i] as Map<String, dynamic>, isLast: i == events.length - 1),
      ],
    );
  }
}

class _EventTile extends StatelessWidget {
  final Map<String, dynamic> event;
  final bool isLast;

  const _EventTile({required this.event, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final eventType = event['eventType'] as String? ?? 'UNKNOWN';
    final timestamp = DateTime.tryParse(event['timestamp'] as String? ?? '');
    final chainStatus = event['chainStatus'] as String? ?? 'PENDING';
    final hasVerifiedField = event.containsKey('chainVerified');
    final verified = event['chainVerified'] as bool? ?? (chainStatus == 'CONFIRMED');

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.amber.shade100,
                child: Icon(_stageIcons[eventType] ?? Icons.circle, size: 16, color: Colors.amber.shade900),
              ),
              if (!isLast) Expanded(child: Container(width: 2, color: Colors.amber.shade100)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(eventType.replaceAll('_', ' '), style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (timestamp != null)
                    Text(
                      DateFormat('MMM d, y  h:mm a').format(timestamp.toLocal()),
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  const SizedBox(height: 6),
                  if (hasVerifiedField || event['txHash'] != null)
                    BlockchainVerifiedBadge(verified: verified, txHash: event['txHash'] as String?, dense: true)
                  else
                    Text('Chain status: $chainStatus', style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

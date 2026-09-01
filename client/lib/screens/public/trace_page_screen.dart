import 'package:flutter/material.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../graphql/client.dart';
import '../../graphql/queries.dart';
import '../../widgets/batch_status_badge.dart';
import '../../widgets/event_timeline.dart';

/// The public consumer provenance page -- reachable at `/trace/{batchId}`
/// with NO authentication (this is exactly the URL the QR code encodes).
/// Anyone with the link can open it; it never asks for a wallet or a login.
class TracePageScreen extends StatefulWidget {
  final String batchId;

  const TracePageScreen({super.key, required this.batchId});

  @override
  State<TracePageScreen> createState() => _TracePageScreenState();
}

class _TracePageScreenState extends State<TracePageScreen> {
  late Future<Map<String, dynamic>?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>?> _load() async {
    final client = context.read<GraphQLClient>();
    final result = await client.query(QueryOptions(
      document: gql(publicTraceQuery),
      variables: {'batchId': widget.batchId},
    ));
    if (result.hasException) {
      throw Exception(friendlyGraphQLError(result.exception));
    }
    return result.data?['publicTraceByBatchId'] as Map<String, dynamic>?;
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF2),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: FutureBuilder<Map<String, dynamic>?>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: Padding(padding: EdgeInsets.all(64), child: CircularProgressIndicator()));
                  }
                  if (snapshot.hasError) {
                    return _ErrorState(message: snapshot.error.toString().replaceFirst('Exception: ', ''), onRetry: _refresh);
                  }
                  final trace = snapshot.data;
                  if (trace == null) {
                    return _ErrorState(
                      message:
                          'No public record found for batch "${widget.batchId}". It may not exist, or has not been packaged yet.',
                      onRetry: _refresh,
                    );
                  }
                  return _TraceView(trace: trace);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 64),
        Icon(Icons.search_off, size: 56, color: Colors.grey.shade400),
        const SizedBox(height: 16),
        Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 20),
        Center(child: OutlinedButton(onPressed: onRetry, child: const Text('Try again'))),
      ],
    );
  }
}

class _TraceView extends StatelessWidget {
  final Map<String, dynamic> trace;

  const _TraceView({required this.trace});

  @override
  Widget build(BuildContext context) {
    final events = (trace['events'] as List).cast<Map<String, dynamic>>();
    final allVerified = trace['allEventsChainVerified'] as bool? ?? false;
    final harvestDate = DateTime.tryParse(trace['harvestDate'] as String? ?? '');
    final hiveLabels = (trace['hiveLabels'] as List).cast<String>();
    final qualityResult = trace['qualityResult'] as String?;
    final packageCode = trace['packageCode'] as String?;
    final packagedAt = DateTime.tryParse(trace['packagedAt'] as String? ?? '');

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
      children: [
        Row(
          children: [
            const Icon(Icons.hive, size: 32, color: Color(0xFFB8860B)),
            const SizedBox(width: 10),
            Text('Honey Chain', style: Theme.of(context).textTheme.headlineSmall),
          ],
        ),
        const SizedBox(height: 4),
        const Text('Product provenance record', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 20),

        _VerificationBanner(allVerified: allVerified, eventCount: events.length),
        const SizedBox(height: 20),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(trace['batchId'] as String, style: Theme.of(context).textTheme.titleLarge),
                    BatchStatusBadge(status: trace['status'] as String? ?? ''),
                  ],
                ),
                const Divider(height: 28),
                _InfoRow(icon: Icons.location_on_outlined, label: 'Origin apiary', value: trace['apiaryName'] as String? ?? '—'),
                if ((trace['locationDescription'] as String? ?? '').isNotEmpty)
                  _InfoRow(icon: Icons.map_outlined, label: 'Location', value: trace['locationDescription'] as String),
                _InfoRow(
                  icon: Icons.calendar_today_outlined,
                  label: 'Harvest date',
                  value: harvestDate != null ? DateFormat('MMMM d, y').format(harvestDate) : '—',
                ),
                _InfoRow(icon: Icons.hive_outlined, label: 'Hives involved', value: hiveLabels.isEmpty ? '—' : hiveLabels.join(', ')),
                _InfoRow(icon: Icons.scale_outlined, label: 'Quantity', value: '${trace['quantityKg']} kg'),
                _InfoRow(icon: Icons.local_florist_outlined, label: 'Floral source', value: trace['floralSource'] as String? ?? '—'),
                _InfoRow(icon: Icons.person_outline, label: 'Beekeeper', value: trace['beekeeperUsername'] as String? ?? '—'),
                if (qualityResult != null)
                  _InfoRow(
                    icon: qualityResult == 'PASSED' ? Icons.check_circle_outline : Icons.cancel_outlined,
                    label: 'Quality verification',
                    value: qualityResult,
                    valueColor: qualityResult == 'PASSED' ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                if (packageCode != null) _InfoRow(icon: Icons.inventory_2_outlined, label: 'Package code', value: packageCode),
                if (packagedAt != null)
                  _InfoRow(icon: Icons.event_available_outlined, label: 'Packaged on', value: DateFormat('MMMM d, y').format(packagedAt)),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),
        Text('Complete history', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: EventTimeline(events: events),
          ),
        ),

        const SizedBox(height: 24),
        Center(
          child: Text(
            'This record is independently verifiable: every stage above was written to an\nEVM-compatible blockchain at the time it happened, and re-checked live against\nthe chain when this page loaded.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _VerificationBanner extends StatelessWidget {
  final bool allVerified;
  final int eventCount;

  const _VerificationBanner({required this.allVerified, required this.eventCount});

  @override
  Widget build(BuildContext context) {
    final color = allVerified ? Colors.green : Colors.orange;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.shade50,
        border: Border.all(color: color.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(allVerified ? Icons.verified : Icons.warning_amber_rounded, color: color.shade700, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  allVerified ? 'Verified against the blockchain' : 'Could not verify all records',
                  style: TextStyle(fontWeight: FontWeight.bold, color: color.shade900, fontSize: 15),
                ),
                Text(
                  allVerified
                      ? 'All $eventCount recorded stages match their on-chain hash exactly.'
                      : 'One or more stages did not match the on-chain record. Treat this history with caution.',
                  style: TextStyle(color: color.shade900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({required this.icon, required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 10),
          SizedBox(width: 140, child: Text(label, style: TextStyle(color: Colors.grey.shade600))),
          Expanded(
            child: Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: valueColor)),
          ),
        ],
      ),
    );
  }
}

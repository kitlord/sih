import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:provider/provider.dart';

import '../../graphql/client.dart';
import '../../graphql/queries.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/batch_status_badge.dart';
import '../../widgets/event_timeline.dart';

class BatchDetailScreen extends StatefulWidget {
  final String batchId;

  const BatchDetailScreen({super.key, required this.batchId});

  @override
  State<BatchDetailScreen> createState() => _BatchDetailScreenState();
}

class _BatchDetailScreenState extends State<BatchDetailScreen> {
  late Future<QueryResult> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<QueryResult> _fetch() {
    return context.read<GraphQLClient>().query(
          QueryOptions(document: gql(batchQuery), variables: {'batchId': widget.batchId}),
        );
  }

  Future<void> _refresh() async {
    final result = _fetch();
    setState(() => _future = result);
    await result;
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Batch ${widget.batchId}',
      actions: [
        IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _refresh),
      ],
      body: FutureBuilder<QueryResult>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final result = snapshot.data!;
          if (result.hasException) {
            return Center(child: Text(friendlyGraphQLError(result.exception), style: const TextStyle(color: Colors.red)));
          }
          final batch = result.data?['batch'] as Map<String, dynamic>?;
          if (batch == null) {
            return const Center(child: Text('Batch not found.'));
          }

          final apiary = batch['apiary'] as Map<String, dynamic>?;
          final hives = ((batch['hives'] as List?) ?? []).cast<Map<String, dynamic>>();
          final beekeeper = batch['beekeeper'] as Map<String, dynamic>?;
          final qualityCheck = batch['qualityCheck'] as Map<String, dynamic>?;
          final package = batch['package'] as Map<String, dynamic>?;
          final status = batch['status'] as String? ?? '';
          final events = (batch['events'] as List?) ?? [];

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Text(batch['batchId'] as String? ?? '', style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(width: 12),
                    BatchStatusBadge(status: status),
                  ],
                ),
                const SizedBox(height: 16),
                _InfoRow(label: 'Apiary', value: apiary?['name'] as String? ?? '-'),
                _InfoRow(label: 'Location', value: apiary?['locationDescription'] as String? ?? '-'),
                _InfoRow(label: 'Harvest date', value: batch['harvestDate'] as String? ?? '-'),
                _InfoRow(label: 'Quantity', value: '${batch['quantityKg'] ?? '-'} kg'),
                _InfoRow(label: 'Floral source', value: batch['floralSource'] as String? ?? '-'),
                _InfoRow(label: 'Beekeeper', value: beekeeper?['username'] as String? ?? '-'),
                _InfoRow(label: 'Hives', value: hives.map((h) => h['label']).join(', ')),
                if (status == 'HARVESTED')
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: FilledButton.icon(
                      icon: const Icon(Icons.science),
                      label: const Text('Record processing'),
                      onPressed: () => context.go('/beekeeper/batches/${widget.batchId}/process'),
                    ),
                  ),
                if (qualityCheck != null) ...[
                  const Divider(height: 32),
                  Text('Quality check', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _InfoRow(label: 'Result', value: qualityCheck['result'] as String? ?? '-'),
                  if (qualityCheck['moistureContent'] != null)
                    _InfoRow(label: 'Moisture content', value: '${qualityCheck['moistureContent']}%'),
                  if (qualityCheck['purityNotes'] != null)
                    _InfoRow(label: 'Purity notes', value: qualityCheck['purityNotes'] as String),
                  _InfoRow(label: 'Checked at', value: qualityCheck['checkedAt'] as String? ?? '-'),
                  _InfoRow(
                    label: 'Reviewed by',
                    value: (qualityCheck['reviewedBy'] as Map?)?['username'] as String? ?? '-',
                  ),
                ],
                if (package != null) ...[
                  const Divider(height: 32),
                  Text('Package', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _InfoRow(label: 'Package code', value: package['packageCode'] as String? ?? '-'),
                  _InfoRow(label: 'Units', value: '${package['unitCount'] ?? '-'}'),
                  _InfoRow(label: 'Packaged at', value: package['packagedAt'] as String? ?? '-'),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.qr_code),
                    label: const Text('View QR code'),
                    onPressed: () => context.go('/qr/${widget.batchId}'),
                  ),
                ],
                const Divider(height: 32),
                Text('History', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                EventTimeline(events: events),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: TextStyle(color: Colors.grey.shade600))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

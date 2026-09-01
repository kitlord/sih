import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../graphql/client.dart';
import '../../graphql/queries.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/batch_status_badge.dart';
import '../../widgets/event_timeline.dart';

/// Admin's full view of a single batch: everything the beekeeper recorded,
/// plus the admin-only quality-check/package actions gated on `status`.
class AdminBatchDetailScreen extends StatefulWidget {
  final String batchId;

  const AdminBatchDetailScreen({super.key, required this.batchId});

  @override
  State<AdminBatchDetailScreen> createState() => _AdminBatchDetailScreenState();
}

class _AdminBatchDetailScreenState extends State<AdminBatchDetailScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final client = context.read<GraphQLClient>();
    final result = await client.query(QueryOptions(
      document: gql(batchQuery),
      variables: {'batchId': widget.batchId},
    ));
    if (result.hasException) {
      throw Exception(friendlyGraphQLError(result.exception));
    }
    final batch = result.data?['batch'] as Map<String, dynamic>?;
    if (batch == null) {
      throw Exception('Batch ${widget.batchId} not found');
    }
    return batch;
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Batch ${widget.batchId}',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh',
          onPressed: _refresh,
        ),
      ],
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                snapshot.error.toString().replaceFirst('Exception: ', ''),
                style: const TextStyle(color: Colors.red),
              ),
            );
          }
          final batch = snapshot.data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: _buildContent(context, batch),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildContent(BuildContext context, Map<String, dynamic> batch) {
    final status = batch['status'] as String? ?? '';
    final apiary = batch['apiary'] as Map<String, dynamic>?;
    final beekeeper = batch['beekeeper'] as Map<String, dynamic>?;
    final hives = (batch['hives'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final events = (batch['events'] as List?) ?? const [];
    final qualityCheck = batch['qualityCheck'] as Map<String, dynamic>?;
    final package = batch['package'] as Map<String, dynamic>?;
    final harvestDate = DateTime.tryParse(batch['harvestDate'] as String? ?? '');

    return [
      Row(
        children: [
          Text(batch['batchId'] as String? ?? '', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(width: 12),
          BatchStatusBadge(status: status),
        ],
      ),
      const SizedBox(height: 16),
      _SectionCard(
        title: 'Batch details',
        children: [
          _InfoRow('Apiary', apiary?['name'] as String? ?? '—'),
          if ((apiary?['locationDescription'] as String?)?.isNotEmpty == true)
            _InfoRow('Location', apiary!['locationDescription'] as String),
          _InfoRow('Hives', hives.isEmpty ? '—' : hives.map((h) => h['label']).join(', ')),
          _InfoRow('Beekeeper', beekeeper?['username'] as String? ?? '—'),
          _InfoRow('Harvest date', harvestDate != null ? DateFormat('MMM d, y').format(harvestDate) : '—'),
          _InfoRow('Quantity', '${batch['quantityKg']} kg'),
          _InfoRow('Floral source', batch['floralSource'] as String? ?? '—'),
        ],
      ),
      const SizedBox(height: 16),
      if (qualityCheck != null)
        _SectionCard(
          title: 'Quality check',
          children: [
            _InfoRow('Result', qualityCheck['result'] as String? ?? '—'),
            if (qualityCheck['moistureContent'] != null)
              _InfoRow('Moisture content', '${qualityCheck['moistureContent']}%'),
            if ((qualityCheck['purityNotes'] as String?)?.isNotEmpty == true)
              _InfoRow('Purity notes', qualityCheck['purityNotes'] as String),
            _InfoRow('Reviewed by', (qualityCheck['reviewedBy'] as Map?)?['username'] as String? ?? '—'),
          ],
        ),
      if (qualityCheck != null) const SizedBox(height: 16),
      if (package != null)
        _SectionCard(
          title: 'Package',
          children: [
            _InfoRow('Package code', package['packageCode'] as String? ?? '—'),
            _InfoRow('Unit count', '${package['unitCount']}'),
            _InfoRow('Packaged by', (package['packagedBy'] as Map?)?['username'] as String? ?? '—'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => context.go('/qr/${widget.batchId}'),
              icon: const Icon(Icons.qr_code),
              label: const Text('View QR code'),
            ),
          ],
        ),
      if (package != null) const SizedBox(height: 16),
      _SectionCard(
        title: 'Admin action',
        children: [_buildActionArea(context, status)],
      ),
      const SizedBox(height: 16),
      _SectionCard(
        title: 'Event history',
        children: [EventTimeline(events: events)],
      ),
    ];
  }

  Widget _buildActionArea(BuildContext context, String status) {
    switch (status) {
      case 'PROCESSED':
        return FilledButton.icon(
          onPressed: () => context.go('/admin/batches/${widget.batchId}/quality-check'),
          icon: const Icon(Icons.fact_check),
          label: const Text('Record quality check'),
        );
      case 'QUALITY_CHECKED':
        return FilledButton.icon(
          onPressed: () => context.go('/admin/batches/${widget.batchId}/package'),
          icon: const Icon(Icons.inventory_2),
          label: const Text('Package batch'),
        );
      case 'HARVESTED':
        return const Text(
          'Waiting for the beekeeper to record processing before a quality check can be recorded.',
          style: TextStyle(color: Colors.grey),
        );
      case 'PACKAGED':
      default:
        return const Text(
          'This batch has completed its lifecycle. No further admin action is needed.',
          style: TextStyle(color: Colors.grey),
        );
    }
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: TextStyle(color: Colors.grey.shade700))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

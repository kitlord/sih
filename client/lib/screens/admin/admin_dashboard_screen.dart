import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../graphql/client.dart';
import '../../graphql/queries.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/batch_status_badge.dart';

class _StatusFilter {
  final String label;
  final String? value;
  const _StatusFilter(this.label, this.value);
}

const List<_StatusFilter> _filters = [
  _StatusFilter('All', null),
  _StatusFilter('Harvested', 'HARVESTED'),
  _StatusFilter('Processed', 'PROCESSED'),
  _StatusFilter('Quality Checked', 'QUALITY_CHECKED'),
  _StatusFilter('Packaged', 'PACKAGED'),
];

/// Admin landing page: every batch in the system (not just one beekeeper's),
/// filterable by lifecycle status. Tapping a row drills into
/// AdminBatchDetailScreen where the quality-check/package actions live.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  String? _status;
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final client = context.read<GraphQLClient>();
    final result = await client.query(QueryOptions(
      document: gql(adminAllBatchesQuery),
      variables: {'status': _status},
    ));
    if (result.hasException) {
      throw Exception(friendlyGraphQLError(result.exception));
    }
    final batches = (result.data?['adminAllBatches'] as List?) ?? const [];
    return batches.cast<Map<String, dynamic>>();
  }

  void _setFilter(String? status) {
    if (status == _status) return;
    setState(() {
      _status = status;
      _future = _load();
    });
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Admin — All Batches',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh',
          onPressed: _refresh,
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in _filters)
                  ChoiceChip(
                    label: Text(f.label),
                    selected: _status == f.value,
                    onSelected: (_) => _setFilter(f.value),
                  ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
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
                final batches = snapshot.data ?? const [];
                if (batches.isEmpty) {
                  return const Center(child: Text('No batches found.'));
                }
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: batches.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final batch = batches[index];
                      final batchId = batch['batchId'] as String;
                      final apiary = batch['apiary'] as Map<String, dynamic>?;
                      final beekeeper = batch['beekeeper'] as Map<String, dynamic>?;
                      final harvestDate = DateTime.tryParse(batch['harvestDate'] as String? ?? '');
                      final quantity = batch['quantityKg'];
                      return ListTile(
                        title: Text(batchId, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          '${apiary?['name'] ?? 'Unknown apiary'} • beekeeper: ${beekeeper?['username'] ?? 'unknown'}\n'
                          '${harvestDate != null ? DateFormat('MMM d, y').format(harvestDate) : '—'} • $quantity kg',
                        ),
                        isThreeLine: true,
                        trailing: BatchStatusBadge(status: batch['status'] as String? ?? ''),
                        onTap: () => context.go('/admin/batches/$batchId'),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

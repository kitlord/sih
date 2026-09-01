import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:provider/provider.dart';

import '../../graphql/client.dart';
import '../../graphql/queries.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/batch_status_badge.dart';

/// There is no single-apiary GraphQL query in this MVP's schema, so this
/// screen fetches the full `myApiaries` list and finds this one client-side
/// (fine at this scale), and does the same to derive "batches from this
/// apiary" out of `myBatches`.
class ApiaryDetailScreen extends StatefulWidget {
  final String apiaryId;

  const ApiaryDetailScreen({super.key, required this.apiaryId});

  @override
  State<ApiaryDetailScreen> createState() => _ApiaryDetailScreenState();
}

class _ApiaryDetailData {
  final QueryResult apiaries;
  final QueryResult batches;

  _ApiaryDetailData({required this.apiaries, required this.batches});
}

class _ApiaryDetailScreenState extends State<ApiaryDetailScreen> {
  late Future<_ApiaryDetailData> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<_ApiaryDetailData> _fetch() async {
    final client = context.read<GraphQLClient>();
    final results = await Future.wait([
      client.query(QueryOptions(document: gql(myApiariesQuery))),
      client.query(QueryOptions(document: gql(myBatchesQuery))),
    ]);
    return _ApiaryDetailData(apiaries: results[0], batches: results[1]);
  }

  Future<void> _refresh() async {
    final result = _fetch();
    setState(() => _future = result);
    await result;
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Apiary',
      actions: [
        IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _refresh),
      ],
      body: FutureBuilder<_ApiaryDetailData>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          if (data.apiaries.hasException) {
            return Center(
              child: Text(friendlyGraphQLError(data.apiaries.exception), style: const TextStyle(color: Colors.red)),
            );
          }
          final apiaries = ((data.apiaries.data?['myApiaries'] as List?) ?? []).cast<Map<String, dynamic>>();
          Map<String, dynamic>? apiary;
          for (final a in apiaries) {
            if (a['id'] == widget.apiaryId) {
              apiary = a;
              break;
            }
          }
          if (apiary == null) {
            return const Center(child: Text('Apiary not found.'));
          }
          final hives = ((apiary['hives'] as List?) ?? []).cast<Map<String, dynamic>>();

          List<Map<String, dynamic>> batches = [];
          if (!data.batches.hasException) {
            final allBatches = ((data.batches.data?['myBatches'] as List?) ?? []).cast<Map<String, dynamic>>();
            batches = allBatches.where((b) => (b['apiary'] as Map?)?['id'] == widget.apiaryId).toList();
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(apiary['name'] as String? ?? '', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  apiary['locationDescription'] as String? ?? 'No location',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Hives', style: Theme.of(context).textTheme.titleMedium),
                    TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Add hive'),
                      onPressed: () => context.go('/beekeeper/apiaries/${widget.apiaryId}/hives/new'),
                    ),
                  ],
                ),
                if (hives.isEmpty) const Text('No hives yet.'),
                for (final h in hives)
                  ListTile(
                    leading: Icon(Icons.circle, size: 12, color: (h['isActive'] as bool? ?? true) ? Colors.green : Colors.grey),
                    title: Text(h['label'] as String? ?? ''),
                    subtitle: Text(h['hiveType'] as String? ?? 'Unspecified type'),
                    trailing: Text((h['isActive'] as bool? ?? true) ? 'Active' : 'Inactive'),
                  ),
                const SizedBox(height: 24),
                Text('Batches from this apiary', style: Theme.of(context).textTheme.titleMedium),
                if (batches.isEmpty) const Text('No batches recorded yet.'),
                for (final b in batches)
                  ListTile(
                    title: Text(b['batchId'] as String? ?? ''),
                    subtitle: Text('${b['floralSource'] ?? ''} · ${b['harvestDate'] ?? ''}'),
                    trailing: BatchStatusBadge(status: b['status'] as String? ?? ''),
                    onTap: () => context.go('/beekeeper/batches/${b['batchId']}'),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

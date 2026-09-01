import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:provider/provider.dart';

import '../../graphql/client.dart';
import '../../graphql/queries.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/batch_status_badge.dart';

/// Beekeeper home: two tabs (Apiaries / Batches). Each tab owns its own
/// fetch/loading/error state; the shared FAB routes to whichever create
/// form matches the currently visible tab.
class BeekeeperDashboardScreen extends StatefulWidget {
  const BeekeeperDashboardScreen({super.key});

  @override
  State<BeekeeperDashboardScreen> createState() => _BeekeeperDashboardScreenState();
}

class _BeekeeperDashboardScreenState extends State<BeekeeperDashboardScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Honey Chain',
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            tabs: const [Tab(text: 'Apiaries'), Tab(text: 'Batches')],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [_ApiariesTab(), _BatchesTab()],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_tabController.index == 0) {
            context.go('/beekeeper/apiaries/new');
          } else {
            context.go('/beekeeper/batches/new');
          }
        },
        tooltip: _tabController.index == 0 ? 'New apiary' : 'New batch',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _ApiariesTab extends StatefulWidget {
  const _ApiariesTab();

  @override
  State<_ApiariesTab> createState() => _ApiariesTabState();
}

class _ApiariesTabState extends State<_ApiariesTab> {
  late Future<QueryResult> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<QueryResult> _fetch() {
    return context.read<GraphQLClient>().query(QueryOptions(document: gql(myApiariesQuery)));
  }

  Future<void> _refresh() async {
    final result = _fetch();
    setState(() => _future = result);
    await result;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QueryResult>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final result = snapshot.data!;
        if (result.hasException) {
          return _ErrorRetry(message: friendlyGraphQLError(result.exception), onRetry: _refresh);
        }
        final apiaries = ((result.data?['myApiaries'] as List?) ?? []).cast<Map<String, dynamic>>();
        return RefreshIndicator(
          onRefresh: _refresh,
          child: apiaries.isEmpty
              ? ListView(
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('No apiaries yet. Tap + to add one.')),
                    ),
                  ],
                )
              : ListView.builder(
                  itemCount: apiaries.length,
                  itemBuilder: (context, index) {
                    final apiary = apiaries[index];
                    final hives = (apiary['hives'] as List?) ?? [];
                    return ListTile(
                      leading: const Icon(Icons.hive),
                      title: Text(apiary['name'] as String? ?? ''),
                      subtitle: Text('${apiary['locationDescription'] ?? 'No location'} · ${hives.length} hive(s)'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.go('/beekeeper/apiaries/${apiary['id']}'),
                    );
                  },
                ),
        );
      },
    );
  }
}

class _BatchesTab extends StatefulWidget {
  const _BatchesTab();

  @override
  State<_BatchesTab> createState() => _BatchesTabState();
}

class _BatchesTabState extends State<_BatchesTab> {
  late Future<QueryResult> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<QueryResult> _fetch() {
    return context.read<GraphQLClient>().query(QueryOptions(document: gql(myBatchesQuery)));
  }

  Future<void> _refresh() async {
    final result = _fetch();
    setState(() => _future = result);
    await result;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QueryResult>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final result = snapshot.data!;
        if (result.hasException) {
          return _ErrorRetry(message: friendlyGraphQLError(result.exception), onRetry: _refresh);
        }
        final batches = ((result.data?['myBatches'] as List?) ?? []).cast<Map<String, dynamic>>();
        return RefreshIndicator(
          onRefresh: _refresh,
          child: batches.isEmpty
              ? ListView(
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('No batches yet. Tap + to record a harvest.')),
                    ),
                  ],
                )
              : ListView.builder(
                  itemCount: batches.length,
                  itemBuilder: (context, index) {
                    final batch = batches[index];
                    return ListTile(
                      title: Text(batch['batchId'] as String? ?? ''),
                      subtitle:
                          Text('${batch['floralSource'] ?? ''} · ${batch['harvestDate'] ?? ''} · ${batch['quantityKg']} kg'),
                      trailing: BatchStatusBadge(status: batch['status'] as String? ?? ''),
                      onTap: () => context.go('/beekeeper/batches/${batch['batchId']}'),
                    );
                  },
                ),
        );
      },
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorRetry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(message, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

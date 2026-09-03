import 'package:flutter/material.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:provider/provider.dart';

import '../../graphql/client.dart';
import '../../graphql/queries.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/star_rating.dart';

/// Admin-only summary of average consumer rating per apiary/location,
/// worst-rated first (see adminApiaryRatings) -- the point is to surface
/// which locations are getting poor feedback without opening every batch.
class AdminApiaryRatingsScreen extends StatefulWidget {
  const AdminApiaryRatingsScreen({super.key});

  @override
  State<AdminApiaryRatingsScreen> createState() => _AdminApiaryRatingsScreenState();
}

class _AdminApiaryRatingsScreenState extends State<AdminApiaryRatingsScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final client = context.read<GraphQLClient>();
    final result = await client.query(QueryOptions(document: gql(adminApiaryRatingsQuery)));
    if (result.hasException) {
      throw Exception(friendlyGraphQLError(result.exception));
    }
    final rows = (result.data?['adminApiaryRatings'] as List?) ?? const [];
    return rows.cast<Map<String, dynamic>>();
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Apiary Ratings',
      actions: [
        IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _refresh),
      ],
      body: FutureBuilder<List<Map<String, dynamic>>>(
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
          final rows = snapshot.data ?? const [];
          if (rows.isEmpty) {
            return const Center(child: Text('No apiaries found.'));
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: rows.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final row = rows[index];
                final apiary = row['apiary'] as Map<String, dynamic>?;
                final average = (row['averageRating'] as num?)?.toDouble();
                final reviewCount = row['reviewCount'] as int? ?? 0;
                final isLow = average != null && average < 3;
                return ListTile(
                  title: Text(apiary?['name'] as String? ?? 'Unknown apiary', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text((apiary?['locationDescription'] as String? ?? '').isEmpty
                      ? 'No location on file'
                      : apiary!['locationDescription'] as String),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      StarRating(rating: average ?? 0, size: 18),
                      const SizedBox(height: 2),
                      Text(
                        average == null ? 'No reviews yet' : '${average.toStringAsFixed(1)} · $reviewCount',
                        style: TextStyle(
                          fontSize: 12,
                          color: isLow ? Colors.red.shade700 : Colors.grey.shade600,
                          fontWeight: isLow ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

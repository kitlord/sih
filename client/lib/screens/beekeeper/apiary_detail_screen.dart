import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../graphql/client.dart';
import '../../graphql/mutations.dart';
import '../../graphql/queries.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/batch_status_badge.dart';
import '../../widgets/digilocker_verified_badge.dart';

/// There is no single-apiary GraphQL query in this MVP's schema, so this
/// screen fetches the full `myApiaries` list and finds this one client-side
/// (fine at this scale), and does the same to derive "batches from this
/// apiary" out of `myBatches`.
class ApiaryDetailScreen extends StatefulWidget {
  final String apiaryId;

  /// The `?digilocker=verified|failed` query param the backend's OAuth-style
  /// callback redirects back to after a consent flow resolves in another
  /// tab (see digilocker_views.callback_view). Null on a normal visit.
  final String? digilockerResult;

  const ApiaryDetailScreen({super.key, required this.apiaryId, this.digilockerResult});

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
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
    if (widget.digilockerResult != null) {
      // The redirect back from the consent tab landed here with a fresh
      // page load -- surface the outcome once, after the first frame so
      // ScaffoldMessenger is available.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final verified = widget.digilockerResult == 'verified';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(verified ? 'FSSAI license verified via DigiLocker.' : 'DigiLocker verification did not succeed.'),
            backgroundColor: verified ? Colors.green.shade700 : Colors.red.shade700,
          ),
        );
      });
    }
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

  Future<void> _editFssaiLicense(String current) async {
    final controller = TextEditingController(text: current);
    final entered = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('FSSAI license number'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'License number',
            helperText: 'The 14-digit FSSAI license number for this apiary',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (entered == null || entered.isEmpty || !mounted) return;

    final client = context.read<GraphQLClient>();
    final result = await client.mutate(MutationOptions(
      document: gql(setFssaiLicenseNumberMutation),
      variables: {'apiaryId': widget.apiaryId, 'licenseNumber': entered},
    ));
    if (!mounted) return;
    if (result.hasException) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyGraphQLError(result.exception))),
      );
      return;
    }
    await _refresh();
  }

  Future<void> _startVerification() async {
    setState(() => _verifying = true);
    final client = context.read<GraphQLClient>();
    final result = await client.mutate(MutationOptions(
      document: gql(startDigilockerVerificationMutation),
      variables: {'apiaryId': widget.apiaryId},
    ));
    if (!mounted) return;
    setState(() => _verifying = false);
    if (result.hasException) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyGraphQLError(result.exception))),
      );
      return;
    }
    final url = result.data?['startDigilockerVerification']['authorizationUrl'] as String;
    final opened = await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
    if (!mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open the consent page. Open this URL manually: $url')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Complete the DigiLocker consent in the new tab, then come back here and tap refresh.'),
        duration: Duration(seconds: 6),
      ),
    );
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
          final fssaiLicenseNumber = apiary['fssaiLicenseNumber'] as String? ?? '';
          final fssaiVerified = apiary['fssaiVerified'] as bool? ?? false;

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
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Regulatory verification', style: Theme.of(context).textTheme.titleMedium),
                            TextButton.icon(
                              icon: const Icon(Icons.edit_outlined),
                              label: Text(fssaiLicenseNumber.isEmpty ? 'Add FSSAI license' : 'Edit'),
                              onPressed: () => _editFssaiLicense(fssaiLicenseNumber),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        DigilockerVerifiedBadge(
                          verified: fssaiVerified,
                          licenseNumber: fssaiLicenseNumber.isEmpty ? null : fssaiLicenseNumber,
                        ),
                        if (fssaiLicenseNumber.isNotEmpty && !fssaiVerified) ...[
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            icon: _verifying
                                ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.open_in_new, size: 18),
                            label: const Text('Verify via DigiLocker'),
                            onPressed: _verifying ? null : _startVerification,
                          ),
                        ],
                      ],
                    ),
                  ),
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

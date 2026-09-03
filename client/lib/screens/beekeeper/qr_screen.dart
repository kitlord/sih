import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:provider/provider.dart';

import '../../graphql/client.dart';
import '../../graphql/queries.dart';
import '../../widgets/app_scaffold.dart';

/// Reached both from a beekeeper's batch detail screen and from the admin
/// packaging flow -- rendered purely off `batchId`, no role assumptions.
class QrScreen extends StatefulWidget {
  final String batchId;

  const QrScreen({super.key, required this.batchId});

  @override
  State<QrScreen> createState() => _QrScreenState();
}

class _QrScreenState extends State<QrScreen> {
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
      title: 'QR code',
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
          final package = batch['package'] as Map<String, dynamic>?;
          if (package == null) {
            return const Center(child: Text('This batch has not been packaged yet.'));
          }
          final qrCodeUrl = package['qrCodeUrl'] as String?;
          final publicUrl = package['publicUrl'] as String? ?? '';
          final reviewCode = package['reviewCode'] as String? ?? '';

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Batch ${batch['batchId']}', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text('Package ${package['packageCode'] ?? ''}', style: TextStyle(color: Colors.grey.shade600)),
                    const SizedBox(height: 20),
                    if (qrCodeUrl != null)
                      Image.network(qrCodeUrl, width: 280, height: 280)
                    else
                      const Text('No QR code image available.'),
                    const SizedBox(height: 20),
                    const Text(
                      'This is the URL a consumer opens when they scan the QR code:',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    SelectableText(publicUrl, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy link'),
                      onPressed: publicUrl.isEmpty
                          ? null
                          : () async {
                              await Clipboard.setData(ClipboardData(text: publicUrl));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Link copied to clipboard')),
                                );
                              }
                            },
                    ),
                    if (reviewCode.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      const Divider(),
                      const SizedBox(height: 12),
                      const Text(
                        'Print this review code separately (e.g. under the lid) -- '
                        'a consumer needs it to leave a rating, so it must NOT be '
                        'visible on the QR/trace page itself.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          border: Border.all(color: Colors.amber.shade200),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          reviewCode,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, letterSpacing: 2),
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy review code'),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: reviewCode));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Review code copied to clipboard')),
                            );
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

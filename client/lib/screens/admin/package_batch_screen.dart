import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:provider/provider.dart';

import '../../graphql/client.dart';
import '../../graphql/mutations.dart';
import '../../widgets/app_scaffold.dart';

/// Admin form for packaging a QUALITY_CHECKED batch. On success this
/// generates a QR code and advances the batch to PACKAGED, so we hand off
/// straight to the QR confirmation screen.
class PackageBatchScreen extends StatefulWidget {
  final String batchId;

  const PackageBatchScreen({super.key, required this.batchId});

  @override
  State<PackageBatchScreen> createState() => _PackageBatchScreenState();
}

class _PackageBatchScreenState extends State<PackageBatchScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _packageCodeController;
  final _unitCountController = TextEditingController(text: '1');
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _packageCodeController = TextEditingController(text: 'PKG-${widget.batchId}');
  }

  @override
  void dispose() {
    _packageCodeController.dispose();
    _unitCountController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = context.read<GraphQLClient>();
      final result = await client.mutate(MutationOptions(
        document: gql(packageBatchMutation),
        variables: {
          'batchId': widget.batchId,
          'packageCode': _packageCodeController.text.trim(),
          'unitCount': int.parse(_unitCountController.text.trim()),
        },
      ));
      if (result.hasException) {
        throw Exception(friendlyGraphQLError(result.exception));
      }
      if (mounted) context.go('/qr/${widget.batchId}');
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Package Batch',
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Batch ${widget.batchId}', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  const Text(
                    'Packaging generates a QR code and marks the batch PACKAGED.',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_error!, style: const TextStyle(color: Colors.red)),
                    ),
                  TextFormField(
                    controller: _packageCodeController,
                    decoration: const InputDecoration(
                      labelText: 'Package code',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _unitCountController,
                    decoration: const InputDecoration(
                      labelText: 'Unit count',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      final n = int.tryParse(v.trim());
                      if (n == null || n < 1) return 'Enter a whole number of at least 1';
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Package batch'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _loading ? null : () => context.go('/admin/batches/${widget.batchId}'),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

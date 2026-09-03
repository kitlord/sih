import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:provider/provider.dart';

import '../../graphql/client.dart';
import '../../graphql/mutations.dart';
import '../../widgets/app_scaffold.dart';

/// Common honey processing methods, shown in the dropdown. "Other" reveals
/// a free-text field below it -- the underlying `method` GraphQL arg stays
/// plain text either way.
const List<String> _processingMethodOptions = [
  'Cold Extraction',
  'Heat Extraction',
  'Centrifugal Extraction',
  'Crush and Strain',
  'Raw / Unprocessed',
  'Filtration',
  'Other',
];

class RecordProcessingScreen extends StatefulWidget {
  final String batchId;

  const RecordProcessingScreen({super.key, required this.batchId});

  @override
  State<RecordProcessingScreen> createState() => _RecordProcessingScreenState();
}

class _RecordProcessingScreenState extends State<RecordProcessingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _customMethod = TextEditingController();
  final _notes = TextEditingController();
  String? _method;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _customMethod.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final client = context.read<GraphQLClient>();
    final method = _method == 'Other' ? _customMethod.text.trim() : (_method ?? '');
    final result = await client.mutate(MutationOptions(
      document: gql(recordProcessingEventMutation),
      variables: {
        'batchId': widget.batchId,
        'method': method,
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      },
    ));
    if (!mounted) return;
    if (result.hasException) {
      setState(() {
        _submitting = false;
        _error = friendlyGraphQLError(result.exception);
      });
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Processing event recorded')),
    );
    context.go('/beekeeper/batches/${widget.batchId}');
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Record processing',
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Batch ${widget.batchId}', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_error!, style: const TextStyle(color: Colors.red)),
                    ),
                  DropdownButtonFormField<String>(
                    initialValue: _method,
                    decoration: const InputDecoration(labelText: 'Method', border: OutlineInputBorder()),
                    hint: const Text('Select processing method'),
                    items: _processingMethodOptions
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (v) => setState(() => _method = v),
                    validator: (v) => v == null ? 'Required' : null,
                  ),
                  if (_method == 'Other') ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _customMethod,
                      decoration: const InputDecoration(labelText: 'Specify method', border: OutlineInputBorder()),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notes,
                    decoration: const InputDecoration(labelText: 'Notes (optional)', border: OutlineInputBorder()),
                    maxLines: 4,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Save'),
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

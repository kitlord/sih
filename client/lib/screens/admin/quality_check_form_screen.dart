import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:provider/provider.dart';

import '../../graphql/client.dart';
import '../../graphql/mutations.dart';
import '../../widgets/app_scaffold.dart';

/// Admin form for recording a quality check on a PROCESSED batch. Passing
/// advances the batch to QUALITY_CHECKED; failing leaves it at PROCESSED
/// (there's no reject/retry flow in this MVP, so we just explain that).
class QualityCheckFormScreen extends StatefulWidget {
  final String batchId;

  const QualityCheckFormScreen({super.key, required this.batchId});

  @override
  State<QualityCheckFormScreen> createState() => _QualityCheckFormScreenState();
}

class _QualityCheckFormScreenState extends State<QualityCheckFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _moistureController = TextEditingController();
  final _notesController = TextEditingController();
  String _result = 'PASSED';
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _moistureController.dispose();
    _notesController.dispose();
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
      final moistureText = _moistureController.text.trim();
      final result = await client.mutate(MutationOptions(
        document: gql(recordQualityCheckMutation),
        variables: {
          'batchId': widget.batchId,
          'result': _result,
          'moistureContent': moistureText.isEmpty ? null : double.tryParse(moistureText),
          'purityNotes': _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        },
      ));
      if (result.hasException) {
        throw Exception(friendlyGraphQLError(result.exception));
      }
      if (mounted) context.go('/admin/batches/${widget.batchId}');
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Record Quality Check',
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
                  const SizedBox(height: 16),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_error!, style: const TextStyle(color: Colors.red)),
                    ),
                  Text('Result', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'PASSED', label: Text('Passed'), icon: Icon(Icons.check_circle_outline)),
                      ButtonSegment(value: 'FAILED', label: Text('Failed'), icon: Icon(Icons.highlight_off)),
                    ],
                    selected: {_result},
                    onSelectionChanged: (selection) => setState(() => _result = selection.first),
                  ),
                  const SizedBox(height: 8),
                  if (_result == 'PASSED')
                    const Text(
                      'Passing this check will advance the batch to QUALITY_CHECKED.',
                      style: TextStyle(color: Colors.grey),
                    )
                  else
                    const Text(
                      'The batch will stay at PROCESSED. There is no reject/retry flow in this MVP -- '
                      'the beekeeper would need to be informed out of band.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _moistureController,
                    decoration: const InputDecoration(
                      labelText: 'Moisture content % (optional)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      return double.tryParse(v.trim()) == null ? 'Enter a valid number' : null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'Purity notes (optional)',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    minLines: 3,
                    maxLines: 5,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Submit quality check'),
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

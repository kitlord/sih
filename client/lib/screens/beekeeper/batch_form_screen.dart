import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../graphql/client.dart';
import '../../graphql/mutations.dart';
import '../../graphql/queries.dart';
import '../../widgets/app_scaffold.dart';

/// Batch (harvest) creation form. Apiaries (with their nested hives) are
/// fetched once up front to populate the apiary dropdown and the
/// hive-checkbox list that depends on it.
class BatchFormScreen extends StatefulWidget {
  const BatchFormScreen({super.key});

  @override
  State<BatchFormScreen> createState() => _BatchFormScreenState();
}

class _BatchFormScreenState extends State<BatchFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _quantity = TextEditingController();
  final _floralSource = TextEditingController();

  late Future<QueryResult> _apiariesFuture;

  String? _selectedApiaryId;
  final Set<String> _selectedHiveIds = {};
  DateTime? _harvestDate;
  bool _submitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _apiariesFuture = _fetchApiaries();
  }

  Future<QueryResult> _fetchApiaries() {
    return context.read<GraphQLClient>().query(QueryOptions(document: gql(myApiariesQuery)));
  }

  @override
  void dispose() {
    _quantity.dispose();
    _floralSource.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _harvestDate ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) setState(() => _harvestDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedApiaryId == null) {
      setState(() => _submitError = 'Select an apiary');
      return;
    }
    if (_selectedHiveIds.isEmpty) {
      setState(() => _submitError = 'Select at least one hive');
      return;
    }
    if (_harvestDate == null) {
      setState(() => _submitError = 'Pick a harvest date');
      return;
    }
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    final client = context.read<GraphQLClient>();
    final result = await client.mutate(MutationOptions(
      document: gql(createHoneyBatchMutation),
      variables: {
        'apiaryId': _selectedApiaryId,
        'hiveIds': _selectedHiveIds.toList(),
        'harvestDate': DateFormat('yyyy-MM-dd').format(_harvestDate!),
        'quantityKg': double.parse(_quantity.text.trim()),
        'floralSource': _floralSource.text.trim(),
      },
    ));
    if (!mounted) return;
    if (result.hasException) {
      setState(() {
        _submitting = false;
        _submitError = friendlyGraphQLError(result.exception);
      });
      return;
    }
    final batchId = (result.data?['createHoneyBatch'] as Map?)?['batchId'] as String?;
    setState(() => _submitting = false);
    if (batchId != null) {
      context.go('/beekeeper/batches/$batchId');
    } else {
      context.go('/beekeeper');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Record a harvest',
      body: FutureBuilder<QueryResult>(
        future: _apiariesFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final result = snapshot.data!;
          if (result.hasException) {
            return Center(child: Text(friendlyGraphQLError(result.exception), style: const TextStyle(color: Colors.red)));
          }
          final apiaries = ((result.data?['myApiaries'] as List?) ?? []).cast<Map<String, dynamic>>();
          if (apiaries.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Create an apiary with at least one hive before recording a harvest.'),
              ),
            );
          }

          final selectedApiary = apiaries.firstWhere(
            (a) => a['id'] == _selectedApiaryId,
            orElse: () => <String, dynamic>{},
          );
          final hivesForSelected = ((selectedApiary['hives'] as List?) ?? []).cast<Map<String, dynamic>>();

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_submitError != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(_submitError!, style: const TextStyle(color: Colors.red)),
                        ),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedApiaryId,
                        decoration: const InputDecoration(labelText: 'Apiary', border: OutlineInputBorder()),
                        items: [
                          for (final a in apiaries)
                            DropdownMenuItem(value: a['id'] as String, child: Text(a['name'] as String? ?? '')),
                        ],
                        onChanged: (value) => setState(() {
                          _selectedApiaryId = value;
                          _selectedHiveIds.clear();
                        }),
                        validator: (v) => v == null ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      Text('Hives', style: Theme.of(context).textTheme.titleSmall),
                      if (_selectedApiaryId == null)
                        const Text('Select an apiary first.', style: TextStyle(color: Colors.grey))
                      else if (hivesForSelected.isEmpty)
                        const Text('This apiary has no hives yet.', style: TextStyle(color: Colors.grey))
                      else
                        for (final h in hivesForSelected)
                          CheckboxListTile(
                            value: _selectedHiveIds.contains(h['id']),
                            title: Text(h['label'] as String? ?? ''),
                            subtitle: Text(h['hiveType'] as String? ?? ''),
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: (checked) => setState(() {
                              if (checked ?? false) {
                                _selectedHiveIds.add(h['id'] as String);
                              } else {
                                _selectedHiveIds.remove(h['id']);
                              }
                            }),
                          ),
                      const SizedBox(height: 16),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          _harvestDate == null
                              ? 'Harvest date'
                              : 'Harvest date: ${DateFormat('yyyy-MM-dd').format(_harvestDate!)}',
                        ),
                        trailing: const Icon(Icons.calendar_today),
                        onTap: _pickDate,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _quantity,
                        decoration: const InputDecoration(labelText: 'Quantity (kg)', border: OutlineInputBorder()),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          if (double.tryParse(v.trim()) == null) return 'Enter a valid number';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _floralSource,
                        decoration: const InputDecoration(labelText: 'Floral source', border: OutlineInputBorder()),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _submitting ? null : _submit,
                        child: _submitting
                            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Record harvest'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

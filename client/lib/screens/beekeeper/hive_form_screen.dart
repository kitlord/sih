import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:provider/provider.dart';

import '../../graphql/client.dart';
import '../../graphql/mutations.dart';
import '../../widgets/app_scaffold.dart';

/// Common hive equipment styles, shown in the dropdown. "Other" reveals a
/// free-text field below it so an uncommon hive type can still be recorded
/// -- the underlying `hive_type` field on the backend stays plain text.
const List<String> _hiveTypeOptions = [
  'Langstroth',
  'Top Bar',
  'Warre',
  'Flow Hive',
  'Traditional / Log Hive',
  'Other',
];

class HiveFormScreen extends StatefulWidget {
  final String apiaryId;

  const HiveFormScreen({super.key, required this.apiaryId});

  @override
  State<HiveFormScreen> createState() => _HiveFormScreenState();
}

class _HiveFormScreenState extends State<HiveFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _label = TextEditingController();
  final _customHiveType = TextEditingController();
  String? _hiveType;
  bool _submitting = false;

  @override
  void dispose() {
    _label.dispose();
    _customHiveType.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final client = context.read<GraphQLClient>();
    final hiveType = _hiveType == 'Other' ? _customHiveType.text.trim() : (_hiveType ?? '');
    final result = await client.mutate(MutationOptions(
      document: gql(createHiveMutation),
      variables: {
        'apiaryId': widget.apiaryId,
        'label': _label.text.trim(),
        'hiveType': hiveType.isEmpty ? null : hiveType,
      },
    ));
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.hasException) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyGraphQLError(result.exception))),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Hive added')),
    );
    context.go('/beekeeper/apiaries/${widget.apiaryId}');
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'New hive',
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
                  TextFormField(
                    controller: _label,
                    decoration: const InputDecoration(labelText: 'Label', border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _hiveType,
                    decoration: const InputDecoration(
                      labelText: 'Hive type (optional)',
                      border: OutlineInputBorder(),
                    ),
                    hint: const Text('Select hive type'),
                    items: _hiveTypeOptions
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) => setState(() => _hiveType = v),
                  ),
                  if (_hiveType == 'Other') ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _customHiveType,
                      decoration: const InputDecoration(
                        labelText: 'Specify hive type',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Add hive'),
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

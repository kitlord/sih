import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:provider/provider.dart';

import '../../graphql/client.dart';
import '../../graphql/mutations.dart';
import '../../widgets/app_scaffold.dart';

class HiveFormScreen extends StatefulWidget {
  final String apiaryId;

  const HiveFormScreen({super.key, required this.apiaryId});

  @override
  State<HiveFormScreen> createState() => _HiveFormScreenState();
}

class _HiveFormScreenState extends State<HiveFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _label = TextEditingController();
  final _hiveType = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _label.dispose();
    _hiveType.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final client = context.read<GraphQLClient>();
    final result = await client.mutate(MutationOptions(
      document: gql(createHiveMutation),
      variables: {
        'apiaryId': widget.apiaryId,
        'label': _label.text.trim(),
        'hiveType': _hiveType.text.trim().isEmpty ? null : _hiveType.text.trim(),
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
                  TextFormField(
                    controller: _hiveType,
                    decoration: const InputDecoration(
                      labelText: 'Hive type (optional, e.g. Langstroth)',
                      border: OutlineInputBorder(),
                    ),
                  ),
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

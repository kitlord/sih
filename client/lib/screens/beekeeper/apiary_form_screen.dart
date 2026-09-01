import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:provider/provider.dart';

import '../../graphql/client.dart';
import '../../graphql/mutations.dart';
import '../../widgets/app_scaffold.dart';

class ApiaryFormScreen extends StatefulWidget {
  const ApiaryFormScreen({super.key});

  @override
  State<ApiaryFormScreen> createState() => _ApiaryFormScreenState();
}

class _ApiaryFormScreenState extends State<ApiaryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _location = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final client = context.read<GraphQLClient>();
    final result = await client.mutate(MutationOptions(
      document: gql(createApiaryMutation),
      variables: {
        'name': _name.text.trim(),
        'locationDescription': _location.text.trim().isEmpty ? null : _location.text.trim(),
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
      const SnackBar(content: Text('Apiary created')),
    );
    context.go('/beekeeper');
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'New apiary',
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
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _location,
                    decoration: const InputDecoration(labelText: 'Location (optional)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Create apiary'),
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

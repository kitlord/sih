import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../state/auth_provider.dart';

/// Shared authenticated-area scaffold (beekeeper + admin screens): an
/// AppBar with the signed-in username/role and a logout action, wrapping
/// arbitrary screen content.
class AppScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          ...?actions,
          if (auth.user != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text('${auth.user!['username']} (${auth.role})', style: const TextStyle(fontSize: 13)),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () async {
              await context.read<AuthProvider>().logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: body,
      floatingActionButton: floatingActionButton,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:provider/provider.dart';

import 'app_router.dart';
import 'graphql/client.dart';
import 'state/auth_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Renders routes as /trace/HC-2026-0001 instead of /#/trace/HC-2026-0001,
  // matching the literal QR/public URL format from the spec.
  usePathUrlStrategy();

  final auth = AuthProvider();
  await auth.restoreFromStorage();

  runApp(HoneyChainApp(auth: auth));
}

class HoneyChainApp extends StatefulWidget {
  final AuthProvider auth;

  const HoneyChainApp({super.key, required this.auth});

  @override
  State<HoneyChainApp> createState() => _HoneyChainAppState();
}

class _HoneyChainAppState extends State<HoneyChainApp> {
  late final GraphQLClient _client = buildGraphQLClient(() => widget.auth.token);
  late final GoRouter _router = buildRouter(widget.auth);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: widget.auth),
        Provider<GraphQLClient>.value(value: _client),
      ],
      child: GraphQLProvider(
        client: ValueNotifier(_client),
        child: MaterialApp.router(
          title: 'Honey Chain',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorSchemeSeed: const Color(0xFFB8860B), // dark goldenrod -- honey
            useMaterial3: true,
          ),
          routerConfig: _router,
        ),
      ),
    );
  }
}

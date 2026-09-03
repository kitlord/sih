import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/admin/admin_apiary_ratings_screen.dart';
import 'screens/admin/admin_batch_detail_screen.dart';
import 'screens/admin/admin_dashboard_screen.dart';
import 'screens/admin/package_batch_screen.dart';
import 'screens/admin/quality_check_form_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/beekeeper/apiary_detail_screen.dart';
import 'screens/beekeeper/apiary_form_screen.dart';
import 'screens/beekeeper/batch_detail_screen.dart';
import 'screens/beekeeper/batch_form_screen.dart';
import 'screens/beekeeper/beekeeper_dashboard_screen.dart';
import 'screens/beekeeper/hive_form_screen.dart';
import 'screens/beekeeper/qr_screen.dart';
import 'screens/beekeeper/record_processing_screen.dart';
import 'screens/public/trace_page_screen.dart';
import 'state/auth_provider.dart';

/// Builds the app's router. Route table (kept intentionally flat, matching
/// the plan's MVP screen list 1:1):
///
///   /                                              role-based redirect
///   /login, /register                              public, auth forms
///   /beekeeper                                      dashboard (apiaries/hives/batches tabs)
///   /beekeeper/apiaries/new
///   /beekeeper/apiaries/:apiaryId
///   /beekeeper/apiaries/:apiaryId/hives/new
///   /beekeeper/batches/new
///   /beekeeper/batches/:batchId
///   /beekeeper/batches/:batchId/process
///   /admin                                          dashboard (all batches)
///   /admin/ratings                                   apiary ratings, worst first
///   /admin/batches/:batchId
///   /admin/batches/:batchId/quality-check
///   /admin/batches/:batchId/package
///   /qr/:batchId                                    post-packaging QR confirmation
///   /trace/:batchId                                 PUBLIC, no auth, no redirect
GoRouter buildRouter(AuthProvider auth) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: auth,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      if (loc.startsWith('/trace/')) return null; // always public

      if (!auth.restored) return null; // wait for the initial storage read

      final loggingIn = loc == '/login' || loc == '/register';
      if (!auth.isAuthenticated) {
        return loggingIn ? null : '/login';
      }

      final homeForRole = auth.role == 'ADMIN' ? '/admin' : '/beekeeper';
      if (loggingIn || loc == '/') return homeForRole;
      if (loc.startsWith('/admin') && auth.role != 'ADMIN') return homeForRole;
      if (loc.startsWith('/beekeeper') && auth.role != 'BEEKEEPER') return homeForRole;
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const _Splash()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),

      GoRoute(path: '/beekeeper', builder: (context, state) => const BeekeeperDashboardScreen()),
      GoRoute(path: '/beekeeper/apiaries/new', builder: (context, state) => const ApiaryFormScreen()),
      GoRoute(
        path: '/beekeeper/apiaries/:apiaryId',
        builder: (context, state) => ApiaryDetailScreen(
          apiaryId: state.pathParameters['apiaryId']!,
          digilockerResult: state.uri.queryParameters['digilocker'],
        ),
      ),
      GoRoute(
        path: '/beekeeper/apiaries/:apiaryId/hives/new',
        builder: (context, state) => HiveFormScreen(apiaryId: state.pathParameters['apiaryId']!),
      ),
      GoRoute(path: '/beekeeper/batches/new', builder: (context, state) => const BatchFormScreen()),
      GoRoute(
        path: '/beekeeper/batches/:batchId',
        builder: (context, state) => BatchDetailScreen(batchId: state.pathParameters['batchId']!),
      ),
      GoRoute(
        path: '/beekeeper/batches/:batchId/process',
        builder: (context, state) => RecordProcessingScreen(batchId: state.pathParameters['batchId']!),
      ),

      GoRoute(path: '/admin', builder: (context, state) => const AdminDashboardScreen()),
      GoRoute(path: '/admin/ratings', builder: (context, state) => const AdminApiaryRatingsScreen()),
      GoRoute(
        path: '/admin/batches/:batchId',
        builder: (context, state) => AdminBatchDetailScreen(batchId: state.pathParameters['batchId']!),
      ),
      GoRoute(
        path: '/admin/batches/:batchId/quality-check',
        builder: (context, state) => QualityCheckFormScreen(batchId: state.pathParameters['batchId']!),
      ),
      GoRoute(
        path: '/admin/batches/:batchId/package',
        builder: (context, state) => PackageBatchScreen(batchId: state.pathParameters['batchId']!),
      ),

      GoRoute(
        path: '/qr/:batchId',
        builder: (context, state) => QrScreen(batchId: state.pathParameters['batchId']!),
      ),

      GoRoute(
        path: '/trace/:batchId',
        builder: (context, state) => TracePageScreen(batchId: state.pathParameters['batchId']!),
      ),
    ],
  );
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

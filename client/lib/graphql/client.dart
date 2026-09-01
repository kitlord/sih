import 'package:graphql_flutter/graphql_flutter.dart';

import '../config.dart';

/// Builds the app's single GraphQLClient. `getToken` is a callback (backed
/// by AuthProvider) rather than a fixed value, so the same client keeps
/// working across login/logout without being rebuilt.
GraphQLClient buildGraphQLClient(String? Function() getToken) {
  final httpLink = HttpLink(graphqlEndpoint);

  final authLink = AuthLink(
    getToken: () async {
      final token = getToken();
      return token == null ? null : 'Bearer $token';
    },
  );

  return GraphQLClient(
    link: authLink.concat(httpLink),
    // No caching of query results -- this is a small MVP and batch/apiary
    // data changes via mutations constantly during the demo; always hitting
    // the network keeps every screen trivially consistent.
    cache: GraphQLCache(store: InMemoryStore()),
    defaultPolicies: DefaultPolicies(
      query: Policies(fetch: FetchPolicy.networkOnly),
      mutate: Policies(fetch: FetchPolicy.networkOnly),
    ),
  );
}

/// Extracts the first GraphQL error message, or a generic fallback -- used
/// throughout the screens to show a readable SnackBar/error message.
String friendlyGraphQLError(OperationException? exception) {
  if (exception == null) return 'Something went wrong';
  final gqlErrors = exception.graphqlErrors;
  if (gqlErrors.isNotEmpty) return gqlErrors.first.message;
  if (exception.linkException != null) {
    return 'Could not reach the server. Is the backend running?';
  }
  return exception.toString();
}

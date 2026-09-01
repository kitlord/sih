/// Backend GraphQL endpoint. Overridable at build/run time with:
///   flutter run -d chrome --dart-define=GRAPHQL_ENDPOINT=http://127.0.0.1:8000/graphql
const String graphqlEndpoint = String.fromEnvironment(
  'GRAPHQL_ENDPOINT',
  defaultValue: 'http://127.0.0.1:8000/graphql',
);

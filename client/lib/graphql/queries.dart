import 'fragments.dart';

const String meQuery = r'''
query Me {
  me { id username email role }
}
''';

final String myApiariesQuery = r'''
query MyApiaries {
  myApiaries {
    id
    name
    locationDescription
    createdAt
    hives { id label hiveType isActive createdAt }
  }
}
''';

const String myHivesQuery = r'''
query MyHives($apiaryId: ID) {
  myHives(apiaryId: $apiaryId) { id label hiveType isActive createdAt }
}
''';

final String myBatchesQuery = '''
$honeyBatchFields
query MyBatches {
  myBatches { ...HoneyBatchFields }
}
''';

final String batchQuery = '''
$honeyBatchFields
query BatchDetail(\$batchId: String!) {
  batch(batchId: \$batchId) { ...HoneyBatchFields }
}
''';

final String adminAllBatchesQuery = '''
$honeyBatchFields
query AdminAllBatches(\$status: String) {
  adminAllBatches(status: \$status) { ...HoneyBatchFields }
}
''';

final String publicTraceQuery = '''
$publicTraceFields
query PublicTrace(\$batchId: String!) {
  publicTraceByBatchId(batchId: \$batchId) { ...PublicTraceFields }
}
''';

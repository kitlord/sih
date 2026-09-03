import 'fragments.dart';

const String registerMutation = r'''
mutation Register($username: String!, $email: String!, $password: String!) {
  register(username: $username, email: $email, password: $password) {
    token
    user { id username email role }
  }
}
''';

const String loginMutation = r'''
mutation Login($username: String!, $password: String!) {
  login(username: $username, password: $password) {
    token
    user { id username email role }
  }
}
''';

const String createApiaryMutation = r'''
mutation CreateApiary($name: String!, $locationDescription: String) {
  createApiary(name: $name, locationDescription: $locationDescription) {
    id
    name
    locationDescription
    createdAt
  }
}
''';

const String setFssaiLicenseNumberMutation = r'''
mutation SetFssaiLicenseNumber($apiaryId: ID!, $licenseNumber: String!) {
  setFssaiLicenseNumber(apiaryId: $apiaryId, licenseNumber: $licenseNumber) {
    id
    fssaiLicenseNumber
    fssaiVerified
    fssaiVerifiedAt
  }
}
''';

const String startDigilockerVerificationMutation = r'''
mutation StartDigilockerVerification($apiaryId: ID!) {
  startDigilockerVerification(apiaryId: $apiaryId) {
    requestId
    authorizationUrl
  }
}
''';

const String createHiveMutation = r'''
mutation CreateHive($apiaryId: ID!, $label: String!, $hiveType: String) {
  createHive(apiaryId: $apiaryId, label: $label, hiveType: $hiveType) {
    id
    label
    hiveType
    isActive
  }
}
''';

final String createHoneyBatchMutation = '''
$honeyBatchFields
mutation CreateHoneyBatch(\$apiaryId: ID!, \$hiveIds: [ID!]!, \$harvestDate: String!, \$quantityKg: Float!, \$floralSource: String!) {
  createHoneyBatch(apiaryId: \$apiaryId, hiveIds: \$hiveIds, harvestDate: \$harvestDate, quantityKg: \$quantityKg, floralSource: \$floralSource) {
    ...HoneyBatchFields
  }
}
''';

final String recordProcessingEventMutation = '''
$honeyBatchFields
mutation RecordProcessingEvent(\$batchId: String!, \$method: String!, \$notes: String) {
  recordProcessingEvent(batchId: \$batchId, method: \$method, notes: \$notes) {
    ...HoneyBatchFields
  }
}
''';

final String recordQualityCheckMutation = '''
$honeyBatchFields
mutation RecordQualityCheck(\$batchId: String!, \$result: String!, \$moistureContent: Float, \$purityNotes: String) {
  recordQualityCheck(batchId: \$batchId, result: \$result, moistureContent: \$moistureContent, purityNotes: \$purityNotes) {
    ...HoneyBatchFields
  }
}
''';

final String packageBatchMutation = '''
$honeyBatchFields
mutation PackageBatch(\$batchId: String!, \$packageCode: String!, \$unitCount: Int!) {
  packageBatch(batchId: \$batchId, packageCode: \$packageCode, unitCount: \$unitCount) {
    ...HoneyBatchFields
  }
}
''';

const String submitReviewMutation = r'''
mutation SubmitReview($batchId: String!, $reviewCode: String!, $rating: Int!, $comment: String, $reviewerName: String) {
  submitReview(batchId: $batchId, reviewCode: $reviewCode, rating: $rating, comment: $comment, reviewerName: $reviewerName) {
    id
    rating
    comment
    reviewerName
    submittedAt
  }
}
''';

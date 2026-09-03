/// Shared field-selection fragments, concatenated into every operation
/// document below so all screens see the same shape of data.
const String honeyBatchFields = r'''
fragment HoneyBatchFields on HoneyBatchType {
  id
  batchId
  harvestDate
  quantityKg
  floralSource
  status
  createdAt
  updatedAt
  apiary {
    id
    name
    locationDescription
    fssaiLicenseNumber
    fssaiVerified
  }
  hives {
    id
    label
    hiveType
    isActive
  }
  beekeeper {
    id
    username
    role
  }
  events {
    id
    eventType
    timestamp
    eventData
    dataHash
    txHash
    blockNumber
    chainEventIndex
    chainStatus
    actor {
      id
      username
      role
    }
  }
  qualityCheck {
    id
    moistureContent
    purityNotes
    result
    checkedAt
    reviewedBy {
      id
      username
    }
  }
  package {
    id
    packageCode
    unitCount
    qrCodeUrl
    publicUrl
    packagedAt
    packagedBy {
      id
      username
    }
  }
}
''';

const String publicTraceFields = r'''
fragment PublicTraceFields on PublicTraceType {
  batchId
  apiaryName
  locationDescription
  harvestDate
  hiveLabels
  quantityKg
  floralSource
  status
  beekeeperUsername
  qualityResult
  qualityNotes
  packageCode
  packagedAt
  allEventsChainVerified
  fssaiLicenseNumber
  fssaiVerified
  events {
    eventType
    timestamp
    eventData
    txHash
    chainStatus
    chainVerified
  }
}
''';

enum SyncProviderKind { localNetwork, googleDrive, webDav, webRtc }

class SyncRemoteObject {
  const SyncRemoteObject({required this.objectId, required this.sha256, required this.byteLength, required this.createdAt});
  final String objectId;
  final String sha256;
  final int byteLength;
  final DateTime createdAt;
}

class SyncTransportCapabilities {
  const SyncTransportCapabilities({
    required this.supportsResumableUpload,
    required this.supportsConditionalWrite,
    required this.supportsBackgroundOperation,
  });
  final bool supportsResumableUpload;
  final bool supportsConditionalWrite;
  final bool supportsBackgroundOperation;
}

/// Transports exchange encrypted immutable objects only, never plaintext notes.
abstract interface class SyncTransport {
  SyncProviderKind get kind;
  SyncTransportCapabilities get capabilities;
  Future<void> connect();
  Future<List<SyncRemoteObject>> listObjects({String? cursor});
  Future<void> uploadObject({
    required String objectId, required Stream<List<int>> encryptedBytes,
    required int byteLength, required String sha256,
  });
  Future<Stream<List<int>>> downloadObject(String objectId);
  Future<void> disconnect();
}

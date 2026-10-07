class SnoteAccountScope {
  SnoteAccountScope._();

  static const localOwner = 'local';
  static String _ownerId = localOwner;

  static String get ownerId => _ownerId;

  static void setAuthenticatedUser(String? userId) {
    final normalized = userId?.trim();
    _ownerId = normalized == null || normalized.isEmpty ? localOwner : normalized;
  }

  static bool get isCloudAccount => _ownerId != localOwner;
}

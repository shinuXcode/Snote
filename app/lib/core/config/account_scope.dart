class SnoteAccountScope {
  SnoteAccountScope._();

  /// All production notes are device-local. No user identity or cloud account exists.
  static const localOwner = 'local';
  static const ownerId = localOwner;
  static const isCloudAccount = false;
}

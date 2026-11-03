/// Conflict primitives shared by sync pack construction and remote apply.
///
/// A vector clock is compared component-wise. Concurrent edits are surfaced
/// instead of silently applying last-write-wins and destroying user content.
enum SyncClockRelation { equal, before, after, concurrent }

SyncClockRelation compareSyncClocks(
  Map<String, int> local,
  Map<String, int> remote,
) {
  var localGreater = false;
  var remoteGreater = false;
  final devices = <String>{...local.keys, ...remote.keys};
  for (final device in devices) {
    final left = local[device] ?? 0;
    final right = remote[device] ?? 0;
    if (left < 0 || right < 0) {
      throw ArgumentError('Vector clock counters cannot be negative.');
    }
    if (left > right) localGreater = true;
    if (right > left) remoteGreater = true;
  }
  if (!localGreater && !remoteGreater) return SyncClockRelation.equal;
  if (localGreater && !remoteGreater) return SyncClockRelation.after;
  if (!localGreater && remoteGreater) return SyncClockRelation.before;
  return SyncClockRelation.concurrent;
}

Map<String, int> mergeSyncClocks(
  Map<String, int> left,
  Map<String, int> right,
) {
  final merged = <String, int>{};
  for (final device in <String>{...left.keys, ...right.keys}) {
    final a = left[device] ?? 0;
    final b = right[device] ?? 0;
    if (a < 0 || b < 0) {
      throw ArgumentError('Vector clock counters cannot be negative.');
    }
    merged[device] = a > b ? a : b;
  }
  return Map.unmodifiable(merged);
}

enum SyncConflictKind {
  concurrentEdit,
  deleteVersusEdit,
  duplicateIdentity,
  missingBlob,
  unsupportedSchema,
}

class SyncConflictDecision {
  const SyncConflictDecision({
    required this.kind,
    required this.relation,
    required this.requiresUserResolution,
    required this.mergedClock,
  });

  final SyncConflictKind kind;
  final SyncClockRelation relation;
  final bool requiresUserResolution;
  final Map<String, int> mergedClock;
}

/// Returns a conservative decision. A concurrent delete/edit is never
/// auto-resolved: the tombstone and edited payload must both be retained until
/// the user chooses restore, delete, or duplicate-as-new-note.
SyncConflictDecision decideSyncConflict({
  required Map<String, int> localClock,
  required Map<String, int> remoteClock,
  required bool localDeleted,
  required bool remoteDeleted,
}) {
  final relation = compareSyncClocks(localClock, remoteClock);
  final merged = mergeSyncClocks(localClock, remoteClock);
  final deleteVersusEdit = localDeleted != remoteDeleted &&
      relation == SyncClockRelation.concurrent;
  final concurrentEdit = relation == SyncClockRelation.concurrent;
  return SyncConflictDecision(
    kind: deleteVersusEdit
        ? SyncConflictKind.deleteVersusEdit
        : SyncConflictKind.concurrentEdit,
    relation: relation,
    requiresUserResolution: concurrentEdit,
    mergedClock: merged,
  );
}

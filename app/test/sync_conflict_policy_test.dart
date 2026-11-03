import 'package:flutter_test/flutter_test.dart';
import 'package:snote/features/sync/sync_conflict_policy.dart';

void main() {
  group('compareSyncClocks', () {
    test('recognizes equal clocks with omitted zero counters', () {
      expect(
        compareSyncClocks({'a': 2}, {'a': 2, 'b': 0}),
        SyncClockRelation.equal,
      );
    });

    test('recognizes causal before and after', () {
      expect(
        compareSyncClocks({'a': 1}, {'a': 2}),
        SyncClockRelation.before,
      );
      expect(
        compareSyncClocks({'a': 3, 'b': 1}, {'a': 2, 'b': 1}),
        SyncClockRelation.after,
      );
    });

    test('recognizes concurrent edits', () {
      expect(
        compareSyncClocks({'phone': 4, 'tablet': 1}, {'phone': 3, 'tablet': 2}),
        SyncClockRelation.concurrent,
      );
    });

    test('rejects invalid negative counters', () {
      expect(
        () => compareSyncClocks({'phone': -1}, const {}),
        throwsArgumentError,
      );
    });
  });

  test('merges vector clocks component-wise', () {
    expect(
      mergeSyncClocks({'phone': 4}, {'tablet': 7, 'phone': 2}),
      {'phone': 4, 'tablet': 7},
    );
  });

  test('concurrent delete versus edit requires user resolution', () {
    final decision = decideSyncConflict(
      localClock: {'phone': 2, 'tablet': 1},
      remoteClock: {'phone': 1, 'tablet': 2},
      localDeleted: true,
      remoteDeleted: false,
    );
    expect(decision.kind, SyncConflictKind.deleteVersusEdit);
    expect(decision.requiresUserResolution, isTrue);
    expect(decision.relation, SyncClockRelation.concurrent);
  });

  test('causally newer tombstone is not treated as a concurrent conflict', () {
    final decision = decideSyncConflict(
      localClock: {'phone': 2},
      remoteClock: {'phone': 1},
      localDeleted: true,
      remoteDeleted: false,
    );
    expect(decision.relation, SyncClockRelation.after);
    expect(decision.requiresUserResolution, isFalse);
  });
}

import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared announcement feed. Uses the same Supabase project as the website.
class SnoteNotification {
  const SnoteNotification({required this.id, required this.title, required this.body, required this.category, required this.target, required this.createdAt, this.actionUrl});
  final String id;
  final String title;
  final String body;
  final String category;
  final String target;
  final DateTime? createdAt;
  final String? actionUrl;

  factory SnoteNotification.fromMap(Map<String, dynamic> map) => SnoteNotification(
    id: map['id'] as String,
    title: map['title'] as String,
    body: map['body'] as String,
    category: map['category'] as String? ?? 'update',
    target: map['target'] as String? ?? 'all',
    createdAt: DateTime.tryParse(map['published_at']?.toString() ?? map['created_at']?.toString() ?? ''),
    actionUrl: map['action_url'] as String?,
  );
}

class SnoteNotificationService {
  SnoteNotificationService(this._client);
  final SupabaseClient _client;
  RealtimeChannel? _channel;

  Future<List<SnoteNotification>> fetchLatest({int limit = 30}) async {
    final rows = await _client.from('snote_notifications')
      .select('id,title,body,category,target,action_url,created_at,published_at')
      .eq('published', true)
      .inFilter('target', ['all', 'app'])
      .order('published_at', ascending: false, nullsFirst: false)
      .limit(limit.clamp(1, 100));
    return rows.map((row) => SnoteNotification.fromMap(row)).toList(growable: false);
  }

  /// Emits refresh signals. Fetch again after a signal to respect RLS.
  Stream<void> watchChanges() {
    _channel?.unsubscribe();
    final controller = StreamController<void>.broadcast();
    _channel = _client.channel('snote-notifications-feed')
      .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'snote_notifications', callback: (_) => controller.add(null))
      .subscribe();
    return controller.stream;
  }

  Future<void> dispose() async {
    final channel = _channel;
    _channel = null;
    if (channel != null) await _client.removeChannel(channel);
  }
}

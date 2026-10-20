import '../../core/config/supabase_config.dart';
import 'supabase_service.dart';
import '../local/notification_repository.dart';

/// Imports published notices from the shared website feed into the local-first inbox.
/// The client can only read published rows; publishing is server-side in the website Control Room.
class WebsiteNotificationSyncService {
  final NotificationRepository _local = NotificationRepository();

  Future<int> syncPublished() async {
    final client = SnoteSupabase.client;
    if (!SnoteConfig.cloudEnabled || client == null) return 0;
    final now = DateTime.now().toUtc();
    final rows = await client
        .from('website_notifications')
        .select('id,title,body,category,action_url,published_at,expires_at')
        .not('published_at', 'is', null)
        .lte('published_at', now.toIso8601String())
        .order('published_at', ascending: false)
        .limit(100);
    var imported = 0;
    for (final value in rows) {
      final row = Map<String, dynamic>.from(value as Map);
      final expires = DateTime.tryParse(row['expires_at']?.toString() ?? '');
      if (expires != null && !expires.isAfter(now)) continue;
      final id = row['id']?.toString();
      final title = row['title']?.toString().trim() ?? '';
      final body = row['body']?.toString().trim() ?? '';
      if (id == null || id.isEmpty || title.isEmpty || body.isEmpty) continue;
      await _local.addOnce(
        id: 'website:$id',
        category: row['category']?.toString() ?? 'announcement',
        title: title,
        body: body,
        actionUrl: row['action_url']?.toString(),
      );
      imported++;
    }
    return imported;
  }
}

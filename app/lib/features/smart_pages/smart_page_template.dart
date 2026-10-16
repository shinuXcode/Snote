import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SmartPageTemplate {
  const SmartPageTemplate({
    required this.id, required this.title, required this.category,
    required this.icon, required this.thumbnailKey, this.isFavorite = false,
  });
  final int id;
  final String title;
  final String category;
  final String icon;
  final String thumbnailKey;
  final bool isFavorite;

  SmartPageTemplate copyWith({bool? isFavorite}) => SmartPageTemplate(
    id: id, title: title, category: category, icon: icon,
    thumbnailKey: thumbnailKey, isFavorite: isFavorite ?? this.isFavorite,
  );

  factory SmartPageTemplate.fromJson(Map<String, dynamic> json, {bool favorite = false}) =>
    SmartPageTemplate(
      id: json['id'] as int,
      title: json['title'] as String,
      category: json['category'] as String,
      icon: json['icon'] as String? ?? 'description',
      thumbnailKey: json['thumbnailKey'] as String? ?? 'default',
      isFavorite: favorite,
    );
}

class SmartPagesStore {
  SmartPagesStore._();
  static final instance = SmartPagesStore._();
  static const _storage = FlutterSecureStorage();
  static const _favoritesKey = 'snote.smart_pages.favorites.v1';

  Future<List<SmartPageTemplate>> load() async {
    final raw = await rootBundle.loadString('assets/data/smart_pages.json');
    final rows = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    final saved = await _storage.read(key: _favoritesKey);
    final favorites = saved == null
        ? <int>{}
        : (jsonDecode(saved) as List).map((e) => e as int).toSet();
    return rows.map((row) {
      final template = SmartPageTemplate.fromJson(row, favorite: favorites.contains(row['id']));
      return template;
    }).toList(growable: false);
  }

  Future<void> saveFavorites(Iterable<SmartPageTemplate> templates) async {
    final ids = templates.where((t) => t.isFavorite).map((t) => t.id).toList();
    await _storage.write(key: _favoritesKey, value: jsonEncode(ids));
  }
}

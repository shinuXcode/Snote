import 'package:flutter/material.dart';
import 'smart_page_template.dart';

/// Gallery UI is intentionally independent of the editor. [onUseTemplate]
/// should create a note/page using the selected template in the existing editor.
class SmartPagesGalleryScreen extends StatefulWidget {
  const SmartPagesGalleryScreen({super.key, required this.onUseTemplate});
  final ValueChanged<SmartPageTemplate> onUseTemplate;

  @override
  State<SmartPagesGalleryScreen> createState() => _SmartPagesGalleryScreenState();
}

class _SmartPagesGalleryScreenState extends State<SmartPagesGalleryScreen> {
  final _search = TextEditingController();
  List<SmartPageTemplate> _templates = [];
  String _category = 'All';
  bool _favoritesOnly = false;
  bool _listView = false;
  bool _loading = true;

  List<String> get _categories => ['All', 'Favorites', ...{
    for (final t in _templates) t.category
  }];

  @override
  void initState() {
    super.initState();
    _search.addListener(_refresh);
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await SmartPagesStore.instance.load();
      if (mounted) setState(() { _templates = items; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _refresh() { if (mounted) setState(() {}); }

  List<SmartPageTemplate> get _visible {
    final query = _search.text.trim().toLowerCase();
    return _templates.where((t) {
      final categoryMatches = _category == 'All' ||
          (_category == 'Favorites' ? t.isFavorite : t.category == _category);
      final favoriteMatches = !_favoritesOnly || t.isFavorite;
      return categoryMatches && favoriteMatches &&
          (query.isEmpty || t.title.toLowerCase().contains(query) ||
           t.category.toLowerCase().contains(query) ||
           t.thumbnailKey.replaceAll('-', ' ').contains(query));
    }).toList();
  }

  Future<void> _toggleFavorite(SmartPageTemplate template) async {
    setState(() {
      _templates = _templates.map((t) => t.id == template.id
          ? t.copyWith(isFavorite: !t.isFavorite) : t).toList();
    });
    await SmartPagesStore.instance.saveFavorites(_templates);
  }

  void _preview(SmartPageTemplate template) {
    showDialog<void>(context: context, builder: (dialogContext) => Dialog.fullscreen(
      child: SafeArea(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            IconButton(onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close)),
            Expanded(child: Text(template.title, style: Theme.of(context).textTheme.titleLarge)),
            IconButton(onPressed: () => _toggleFavorite(template),
              icon: Icon(template.isFavorite ? Icons.favorite : Icons.favorite_border)),
          ]),
          const SizedBox(height: 16),
          Expanded(child: Center(child: Container(
            constraints: const BoxConstraints(maxWidth: 560),
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface,
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(18)),
            child: _TemplatePreview(title: template.title, category: template.category),
          ))),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () { Navigator.pop(dialogContext); widget.onUseTemplate(template); },
            icon: const Icon(Icons.add), label: const Text('Use Template'),
          ),
        ]),
      )),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final items = _visible;
    return Scaffold(
      appBar: AppBar(title: const Text('Smart Pages'), actions: [
        IconButton(tooltip: _listView ? 'Grid view' : 'List view',
          onPressed: () => setState(() => _listView = !_listView),
          icon: Icon(_listView ? Icons.grid_view : Icons.view_list)),
        IconButton(tooltip: _favoritesOnly ? 'Show all' : 'Favorites only',
          onPressed: () => setState(() => _favoritesOnly = !_favoritesOnly),
          icon: Icon(_favoritesOnly ? Icons.favorite : Icons.favorite_border)),
      ]),
      body: _loading ? const Center(child: CircularProgressIndicator())
        : Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SearchBar(controller: _search, hintText: 'Search 200 smart pages…',
              leading: const Icon(Icons.search),
              trailing: [if (_search.text.isNotEmpty) IconButton(
                onPressed: () => _search.clear(), icon: const Icon(Icons.close))])),
          SizedBox(height: 48, child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: _categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final value = _categories[i];
              return ChoiceChip(label: Text(value), selected: _category == value,
                onSelected: (_) => setState(() => _category = value));
            },
          )),
          Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Align(alignment: Alignment.centerLeft,
              child: Text('${items.length} templates',
                style: Theme.of(context).textTheme.labelLarge))),
          Expanded(child: items.isEmpty
            ? const Center(child: Text('No templates match your search.'))
            : _listView
              ? ListView.builder(itemCount: items.length, itemBuilder: (_, i) => _listTile(items[i]))
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 240, mainAxisExtent: 172,
                    crossAxisSpacing: 12, mainAxisSpacing: 12),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _gridCard(items[i]),
                )),
        ]),
    );
  }

  Widget _gridCard(SmartPageTemplate t) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(onTap: () => _preview(t), child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.auto_awesome, color: Theme.of(context).colorScheme.primary),
          const Spacer(),
          IconButton(visualDensity: VisualDensity.compact,
            onPressed: () => _toggleFavorite(t),
            icon: Icon(t.isFavorite ? Icons.favorite : Icons.favorite_border,
              color: t.isFavorite ? Colors.red : null)),
        ]),
        const Spacer(),
        Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(t.category, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall),
      ]),
    )),
  );

  Widget _listTile(SmartPageTemplate t) => ListTile(
    leading: const CircleAvatar(child: Icon(Icons.description)),
    title: Text(t.title), subtitle: Text(t.category),
    trailing: IconButton(onPressed: () => _toggleFavorite(t),
      icon: Icon(t.isFavorite ? Icons.favorite : Icons.favorite_border)),
    onTap: () => _preview(t),
  );

  @override
  void dispose() { _search.removeListener(_refresh); _search.dispose(); super.dispose(); }
}

class _TemplatePreview extends StatelessWidget {
  const _TemplatePreview({required this.title, required this.category});
  final String title;
  final String category;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = title.toLowerCase();
    final isPlanner = name.contains('planner') || name.contains('calendar') ||
        name.contains('schedule') || name.contains('weekly');
    final isMatrix = name.contains('matrix') || name.contains('swot') ||
        name.contains('pros and cons') || name.contains('kanban');
    final isFinance = name.contains('budget') || name.contains('expense') ||
        name.contains('income') || name.contains('bill') || name.contains('finance');
    final isTracker = name.contains('tracker') || name.contains('checklist') ||
        name.contains('habit') || name.contains('log');
    Widget line(String label) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        if (isTracker) const Icon(Icons.check_box_outline_blank_rounded, size: 15),
        if (isTracker) const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: theme.textTheme.labelMedium),
          const SizedBox(height: 5),
          Container(height: 1, color: theme.colorScheme.outlineVariant),
        ])),
      ]),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(category.toUpperCase(), style: theme.textTheme.labelMedium),
      const SizedBox(height: 8),
      Text(title, style: theme.textTheme.headlineSmall),
      const SizedBox(height: 20),
      if (isMatrix)
        Expanded(child: GridView.count(
          crossAxisCount: 2, crossAxisSpacing: 8, mainAxisSpacing: 8,
          physics: const NeverScrollableScrollPhysics(),
          children: const [
            'Do first', 'Schedule', 'Delegate', 'Review'
          ].map((label) => Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(label),
          )).toList(),
        ))
      else if (isPlanner)
        Expanded(child: Column(children: [
          Row(children: List.generate(7, (i) => Expanded(
            child: Center(child: Text(
              ['M','T','W','T','F','S','S'][i],
              style: theme.textTheme.labelSmall,
            )),
          ))),
          const SizedBox(height: 10),
          Expanded(child: GridView.count(
            crossAxisCount: 7, crossAxisSpacing: 4, mainAxisSpacing: 4,
            physics: const NeverScrollableScrollPhysics(),
            children: List.generate(28, (i) => Container(
              alignment: Alignment.topLeft,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('${i + 1}', style: theme.textTheme.labelSmall),
            )),
          )),
        ]))
      else if (isFinance)
        Expanded(child: Column(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(children: [
              Expanded(child: Text('Item')),
              Text('Amount'),
            ]),
          ),
          const SizedBox(height: 10),
          for (final label in ['Planned', 'Actual', 'Difference', 'Total']) line(label),
        ]))
      else
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final label in (isTracker
              ? ['Task / item', 'Status', 'Notes', 'Next step']
              : ['Overview', 'Key points', 'Details', 'Action items']))
              line(label),
          ],
        )),
      const SizedBox(height: 8),
      Text('Preview layout • editable content is created in your note',
        style: theme.textTheme.bodySmall),
    ]);
  }
}

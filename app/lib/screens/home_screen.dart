import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/article.dart';
import '../repositories/article_repository.dart';
import '../widgets/article_card.dart';
import '../widgets/source_filter_bar.dart';
import 'about_screen.dart';
import 'article_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const int _pageSize = 30;
  static const double _loadMoreThreshold = 200;

  final ArticleRepository _repository = ArticleRepository();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  List<Article> _articles = [];
  List<Article> _filteredArticles = [];
  List<String> _sources = [];
  String? _selectedSource;
  String _searchQuery = '';
  bool _isLoading = true;
  int _offset = 0;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadSources();
    _loadArticles(reset: true);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - _loadMoreThreshold &&
        !_isLoading &&
        _hasMore) {
      _loadArticles();
    }
  }

  Future<void> _loadSources() async {
    final sources = await _repository.fetchSources();
    if (!mounted) return;
    setState(() {
      _sources = sources;
    });
  }

  Future<void> _loadArticles({bool reset = false}) async {
    if (reset) {
      setState(() {
        _articles = [];
        _filteredArticles = [];
        _offset = 0;
        _hasMore = true;
        _isLoading = true;
      });
    } else {
      setState(() {
        _isLoading = true;
      });
    }

    final results = await _repository.fetchArticles(
      limit: _pageSize,
      offset: _offset,
      source: _selectedSource,
    );

    if (!mounted) return;
    setState(() {
      _articles.addAll(results);
      _offset += results.length;
      _hasMore = results.length == _pageSize;
      _isLoading = false;
    });
    _filterArticles();
  }

  List<Article> _applyFilter(List<Article> source) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return List.of(source);
    return source.where((a) {
      final title = a.title.toLowerCase();
      final summary = a.summary?.toLowerCase() ?? '';
      return title.contains(q) || summary.contains(q);
    }).toList();
  }

  void _filterArticles() {
    setState(() {
      _filteredArticles = _applyFilter(_articles);
    });
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
    });
    _filterArticles();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
    });
    _filterArticles();
  }

  void _onSourceSelected(String? source) {
    if (source == _selectedSource) return;
    setState(() {
      _selectedSource = source;
    });
    _loadArticles(reset: true);
  }

  void _onArticleTap(Article article) {
    if (kIsWeb) {
      launchUrl(
        Uri.parse(article.url),
        mode: LaunchMode.externalApplication,
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ArticleDetailScreen(article: article),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('OpenShift News Aggregator'),
            Text(
              '${_filteredArticles.length} articles',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutScreen()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          SourceFilterBar(
            sources: _sources,
            selectedSource: _selectedSource,
            onSourceSelected: _onSourceSelected,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search articles...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _clearSearch,
                      )
                    : null,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 0,
                  horizontal: 12,
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _loadArticles(reset: true),
              child: _buildList(theme),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(ThemeData theme) {
    if (_filteredArticles.isEmpty && _searchQuery.isNotEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.search_off,
                  size: 56,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 12),
                Text('No results for "$_searchQuery"'),
                TextButton(
                  onPressed: _clearSearch,
                  child: const Text('Clear search'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (_filteredArticles.isEmpty && !_isLoading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.rss_feed,
                  size: 56,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 12),
                const Text('No articles yet'),
                const SizedBox(height: 4),
                Text('Pull to refresh', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      );
    }

    final showLoader = _isLoading;
    final itemCount = _filteredArticles.length + (showLoader ? 1 : 0);

    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index >= _filteredArticles.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final article = _filteredArticles[index];
        return ArticleCard(
          article: article,
          onTap: () => _onArticleTap(article),
        );
      },
    );
  }
}

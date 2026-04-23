import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';

import '../models/article.dart';
import '../models/cve_alert.dart';
import '../models/ocp_version.dart';
import '../repositories/article_repository.dart';
import '../services/bookmark_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_notifier.dart';
import '../utils/favicons.dart';
import '../widgets/article_card.dart';
import 'about_screen.dart';
import 'article_detail_screen.dart';
import 'bookmarks_screen.dart';
import 'digest_screen.dart';
import 'submit_screen.dart';
import 'versions_screen.dart';

const double _desktopBreakpoint = 900;
const Color _kReleaseGreen = Color(0xFF00AA44);
const Color _kSecurityOrange = Color(0xFFFF6600);
const String _kOcpVersionsSource = 'OCP Versions';

enum ViewMode { grid, list }

enum _ScraperStatus { ok, delayed, issue, unknown }

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
  Map<String, int> _stableSourceCounts = {};
  List<OcpVersion> _ocpVersions = [];
  List<CveAlert> _cveAlerts = [];
  List<String> _topTags = [];
  Map<String, bool> _bookmarkStates = {};
  DateTime? _lastScrapedAt;
  _ScraperStatus _scraperStatus = _ScraperStatus.unknown;
  String? _selectedSource;
  String? _tagFilter;
  String _searchQuery = '';
  bool _isLoading = true;
  int _offset = 0;
  bool _hasMore = true;
  int _bottomNavIndex = 0;
  ViewMode _viewMode = ViewMode.grid;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _surface => _isDark ? kSurface : kLightSurface;
  Color get _surface2 => _isDark ? kSurface2 : kLightSurface2;
  Color get _border => _isDark ? kBorder : kLightBorder;
  Color get _textPrimary => _isDark ? kTextPrimary : kLightTextPrimary;
  Color get _textSecondary =>
      _isDark ? kTextSecondary : kLightTextSecondary;
  Color get _textMuted => _isDark ? kTextMuted : kLightTextMuted;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadSources();
    _loadSourceCounts();
    _loadOcpVersions();
    _loadCveAlerts();
    _loadTopTags();
    _loadScraperStatus();
    _loadArticles(reset: true);
    _loadBookmarkStates();
  }

  Future<void> _loadTopTags() async {
    final tags = await _repository.fetchTopTags(limit: 10, days: 30);
    if (!mounted) return;
    setState(() => _topTags = tags);
  }

  Future<void> _loadScraperStatus() async {
    final last = await _repository.fetchLastScrapedAt();
    if (!mounted) return;
    if (last == null) {
      setState(() {
        _lastScrapedAt = null;
        _scraperStatus = _ScraperStatus.unknown;
      });
      return;
    }
    final age = DateTime.now().difference(last);
    setState(() {
      _lastScrapedAt = last;
      if (age.inHours < 2) {
        _scraperStatus = _ScraperStatus.ok;
      } else if (age.inHours < 4) {
        _scraperStatus = _ScraperStatus.delayed;
      } else {
        _scraperStatus = _ScraperStatus.issue;
      }
    });
  }

  Color get _scraperStatusColor {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (_scraperStatus) {
      case _ScraperStatus.ok:
        return isDark
            ? const Color(0xFF00FF88)
            : const Color(0xFF007A3D);
      case _ScraperStatus.delayed:
        return const Color(0xFFFFAA00);
      case _ScraperStatus.issue:
        return const Color(0xFFFF0000);
      case _ScraperStatus.unknown:
        return const Color(0xFF888888);
    }
  }

  String get _scraperStatusLabel {
    switch (_scraperStatus) {
      case _ScraperStatus.ok:
        return 'ALL SYSTEMS OPERATIONAL';
      case _ScraperStatus.delayed:
        return 'SCRAPER DELAYED';
      case _ScraperStatus.issue:
        return 'SCRAPER ISSUE';
      case _ScraperStatus.unknown:
        return 'STATUS UNKNOWN';
    }
  }

  String get _scraperStatusDetail {
    if (_lastScrapedAt == null) {
      return 'Unable to determine last scrape time';
    }
    final age = DateTime.now().difference(_lastScrapedAt!);
    if (age.inMinutes < 60) {
      return 'Last scraped ${age.inMinutes}m ago · runs every 60 min';
    }
    return 'Last scraped ${age.inHours}h ago · runs every 60 min';
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  DateTime? get _lastUpdate {
    if (_articles.isEmpty) return null;
    return _articles.first.publishedAt ?? _articles.first.createdAt;
  }

  List<Article> get _latestReleases => _articles
      .where((a) => a.tags.contains('release'))
      .take(3)
      .toList();

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
    setState(() => _sources = sources);
  }

  Future<void> _loadSourceCounts() async {
    final counts = await _repository.fetchSourceCounts(days: 7);
    if (!mounted) return;
    setState(() => _stableSourceCounts = counts);
  }

  Future<void> _loadOcpVersions() async {
    final versions = await _repository.fetchOcpVersions();
    if (!mounted) return;
    setState(() => _ocpVersions = versions);
  }

  Future<void> _loadCveAlerts() async {
    final alerts = await _repository.fetchCveAlerts(limit: 4);
    if (!mounted) return;
    setState(() => _cveAlerts = alerts);
  }

  Future<void> _loadBookmarkStates() async {
    final bookmarks = await BookmarkService.instance.getBookmarks();
    if (!mounted) return;
    setState(() {
      _bookmarkStates = {for (final b in bookmarks) b.url: true};
    });
  }

  Future<void> _toggleBookmark(Article article) async {
    final messenger = ScaffoldMessenger.of(context);
    await BookmarkService.instance.toggleBookmark(article);
    final bookmarked = await BookmarkService.instance.isBookmarked(article.url);
    if (!mounted) return;
    setState(() => _bookmarkStates[article.url] = bookmarked);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          bookmarked ? 'Article saved' : 'Bookmark removed',
          style: const TextStyle(fontSize: 13),
        ),
        backgroundColor: const Color(0xFF1A1A1A),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: Color(0xFF2A2A2A)),
        ),
      ),
    );
  }

  void _openBookmarks() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BookmarksScreen()),
    ).then((_) => _loadBookmarkStates());
  }

  void _openSubmit() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SubmitScreen()),
    );
  }

  List<OcpVersion> get _displayedOcpVersions {
    final active = _ocpVersions
        .where((v) => v.minorInt >= kOcpActiveMinorMinimum)
        .toList()
      ..sort((a, b) => b.minorInt.compareTo(a.minorInt));
    return active.take(4).toList();
  }

  String _buildVersionSummary() {
    final versions = _displayedOcpVersions;
    if (versions.isEmpty) return '';
    final versionStrings = versions.map((v) => v.latestStable).toList();
    if (versionStrings.length == 1) {
      return 'Latest stable version is ${versionStrings[0]}';
    }
    final allButLast = versionStrings.sublist(0, versionStrings.length - 1);
    final last = versionStrings.last;
    return 'Latest stable versions are ${allButLast.join(', ')} and $last';
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
      setState(() => _isLoading = true);
    }

    final results = await _repository.fetchArticles(
      limit: _pageSize,
      offset: _offset,
      source: _selectedSource,
      tag: _tagFilter,
    );

    if (!mounted) return;
    setState(() {
      _articles.addAll(results);
      _offset += results.length;
      _hasMore = results.length == _pageSize;
      _isLoading = false;
    });
    _filterArticles();
    _loadSourceCounts();
    _loadScraperStatus();
  }

  List<Article> _applyFilter(List<Article> source) {
    var filtered = List.of(source);
    if (_tagFilter != null) {
      filtered = filtered
          .where((a) => a.tags.contains(_tagFilter!))
          .toList();
    }
    final q = _searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      filtered = filtered.where((a) {
        final title = a.title.toLowerCase();
        final summary = a.summary?.toLowerCase() ?? '';
        return title.contains(q) || summary.contains(q);
      }).toList();
    }
    return filtered;
  }

  void _filterArticles() {
    setState(() => _filteredArticles = _applyFilter(_articles));
  }

  void _onSearchChanged(String value) {
    setState(() => _searchQuery = value);
    _filterArticles();
  }

  void _onSourceSelected(String? source) {
    if (source == _selectedSource && _tagFilter == null) return;
    setState(() {
      _selectedSource = source;
      _tagFilter = null;
    });
    _loadArticles(reset: true);
  }

  void _onTagSelected(String tag) {
    if (_tagFilter == tag) return;
    setState(() {
      _tagFilter = tag;
      _selectedSource = null;
    });
    _loadArticles(reset: true);
  }

  void _onArticleTap(Article article, {required bool desktop}) {
    if (kIsWeb || desktop) {
      launchUrl(Uri.parse(article.url), mode: LaunchMode.externalApplication);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ArticleDetailScreen(article: article),
        ),
      );
    }
  }

  void _openAbout() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AboutScreen()),
    );
  }

  void _openDigest() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DigestScreen()),
    );
  }

  void _openVersions() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const VersionsScreen()),
    );
  }

  void _comingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Coming soon'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _desktopBreakpoint) {
          return _buildDesktop(context);
        }
        return _buildMobile(context);
      },
    );
  }

  // ================= MOBILE =================

  Widget _buildMobile(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Icon(Icons.menu, color: _textSecondary, size: 20),
        title: const Text('ShiftFeed'),
        actions: [
          Icon(Icons.search, color: _textSecondary, size: 20),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              _viewMode == ViewMode.grid
                  ? Icons.view_list_rounded
                  : Icons.grid_view_rounded,
              size: 20,
              color: _textSecondary,
            ),
            onPressed: () => setState(
              () => _viewMode =
                  _viewMode == ViewMode.grid ? ViewMode.list : ViewMode.grid,
            ),
          ),
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(Icons.auto_awesome, size: 20, color: _textSecondary),
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: kRed,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
            onPressed: _openDigest,
            tooltip: 'AI Briefing',
          ),
          Consumer<ThemeNotifier>(
            builder: (context, notifier, _) => IconButton(
              icon: Icon(
                notifier.isDark ? Icons.light_mode : Icons.dark_mode,
                size: 20,
                color: _textSecondary,
              ),
              onPressed: notifier.toggle,
            ),
          ),
          GestureDetector(
            onTap: _openAbout,
            child: Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                color: kRed,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.info_outline,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(54),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(height: 1, color: kRed),
              _buildMobileFilterChips(),
            ],
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadArticles(reset: true),
        color: kRed,
        backgroundColor: _surface,
        child: _buildMobileList(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openSubmit,
        backgroundColor: kRed,
        tooltip: 'Submit a link',
        child: const Icon(Icons.add_link, color: Colors.white),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: _surface,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: kRed,
        unselectedItemColor: _textMuted,
        showUnselectedLabels: true,
        currentIndex: _bottomNavIndex,
        selectedLabelStyle: const TextStyle(fontSize: 10, letterSpacing: 1.0),
        unselectedLabelStyle: const TextStyle(fontSize: 10, letterSpacing: 1.0),
        onTap: (i) {
          if (i == 3) {
            _openAbout();
            return;
          }
          if (i == 2) {
            _openBookmarks();
            return;
          }
          if (i == 1) {
            _openVersions();
            return;
          }
          if (i == 0) {
            setState(() => _bottomNavIndex = 0);
            return;
          }
          _comingSoon();
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.rss_feed), label: 'Feed'),
          BottomNavigationBarItem(icon: Icon(Icons.terminal), label: 'Sources'),
          BottomNavigationBarItem(
            icon: Icon(Icons.bookmark_outline),
            label: 'Saved',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildMobileFilterChips() {
    final chips = <Widget>[
      _mobileChip(
        'ALL',
        _selectedSource == null && _tagFilter == null,
        () => _onSourceSelected(null),
      ),
      _mobileChip(
        'RELEASES',
        _tagFilter == 'release',
        () => _onTagSelected('release'),
        selectedColor: _kReleaseGreen,
      ),
      _mobileChip(
        'SECURITY',
        _tagFilter == 'security',
        () => _onTagSelected('security'),
        selectedColor: _kSecurityOrange,
      ),
      _mobileChip(
        'OCP',
        _selectedSource == _kOcpVersionsSource,
        () => _onSourceSelected(_kOcpVersionsSource),
        selectedColor: _kReleaseGreen,
      ),
      for (final s in _sources)
        _mobileChip(
          s.toUpperCase(),
          _selectedSource == s,
          () => _onSourceSelected(s),
        ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          for (int i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            chips[i],
          ],
        ],
      ),
    );
  }

  Widget _mobileChip(
    String label,
    bool selected,
    VoidCallback onTap, {
    Color? selectedColor,
  }) {
    final activeColor = selectedColor ?? kRed;
    return Material(
      color: selected ? activeColor : _surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected ? Colors.transparent : _border,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
              color: selected ? Colors.white : _textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileList() {
    if (_filteredArticles.isEmpty && _searchQuery.isNotEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search_off, size: 56, color: _textMuted),
                const SizedBox(height: 12),
                Text(
                  'No results for "$_searchQuery"',
                  style: TextStyle(color: _textSecondary),
                ),
                TextButton(
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
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
                Icon(Icons.rss_feed, size: 56, color: _textMuted),
                const SizedBox(height: 12),
                Text(
                  'No articles yet',
                  style: TextStyle(color: _textSecondary),
                ),
                const SizedBox(height: 4),
                Text(
                  'Pull to refresh',
                  style: TextStyle(color: _textMuted, fontSize: 11),
                ),
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
            padding: EdgeInsets.symmetric(vertical: 24),
            child: _PollingIndicator(),
          );
        }
        final article = _filteredArticles[index];
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: _viewMode == ViewMode.grid ? 6 : 4,
          ),
          child: ArticleCard(
            article: article,
            onTap: () => _onArticleTap(article, desktop: false),
            compact: _viewMode == ViewMode.list,
            showBookmarkButton: true,
            isBookmarked: _bookmarkStates[article.url] ?? false,
            onBookmarkToggle: () => _toggleBookmark(article),
          ),
        );
      },
    );
  }

  // ================= DESKTOP =================

  Widget _buildDesktop(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _buildLeftSidebar(),
          Expanded(child: _buildDesktopMain()),
          _buildRightSidebar(),
        ],
      ),
    );
  }

  Widget _buildLeftSidebar() {
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: _surface,
        border: Border(right: BorderSide(color: _border)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'ShiftFeed',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _textPrimary,
                ),
              ),
            ),
          ),
          Divider(color: _border, height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              children: [
                _navItem(
                  icon: Icons.grid_view_rounded,
                  label: 'All News',
                  selected: _selectedSource == null,
                  onTap: () => _onSourceSelected(null),
                ),
                _navItem(
                  icon: Icons.verified_outlined,
                  label: 'OCP Versions',
                  selected: false,
                  onTap: _openVersions,
                ),
                _navItem(
                  icon: Icons.bookmark_outline,
                  label: 'Saved',
                  selected: false,
                  onTap: _openBookmarks,
                ),
                _navItem(
                  icon: Icons.add_link_outlined,
                  label: 'Submit a Link',
                  selected: false,
                  onTap: _openSubmit,
                ),
              ],
            ),
          ),
          Divider(color: _border, height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'SOURCES',
                style: TextStyle(
                  fontSize: 10,
                  color: _textMuted,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final s in _sources) _sourceItem(s),
              ],
            ),
          ),
          Divider(color: _border, height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: kStatusGreen,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _lastUpdate != null
                        ? 'Last update: ${timeago.format(_lastUpdate!)}'
                        : 'Last update: n/a',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: _textMuted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: selected ? kRed : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: selected ? kRed : _textSecondary),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: selected ? _textPrimary : _textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sourceItem(String source) {
    final selected = _selectedSource == source;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onSourceSelected(source),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? _surface2 : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: selected ? kRed : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Image.asset(
                  faviconAsset(source),
                  width: 16,
                  height: 16,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                    width: 16,
                    height: 16,
                    color: _border,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  source,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: selected ? _textPrimary : _textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopMain() {
    return Column(
      children: [
        _buildDesktopTopBar(),
        _buildDesktopFeedHeader(),
        Expanded(child: _buildDesktopGrid()),
      ],
    );
  }

  Widget _buildDesktopTopBar() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: _surface,
                border: Border.all(color: _border),
                borderRadius: BorderRadius.circular(6),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: TextStyle(fontSize: 13, color: _textPrimary),
                cursorColor: kRed,
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  hintText: 'Search technical intelligence...',
                  hintStyle: TextStyle(color: _textMuted, fontSize: 13),
                  prefixIcon: Icon(
                    Icons.search,
                    color: _textMuted,
                    size: 18,
                  ),
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: Icon(Icons.refresh, color: _textSecondary),
            tooltip: 'Refresh',
            onPressed: () => _loadArticles(reset: true),
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome, size: 18, color: kRed),
            onPressed: _openDigest,
            tooltip: 'AI Daily Briefing',
          ),
          const SizedBox(width: 8),
          _ViewToggle(
            viewMode: _viewMode,
            onChanged: (mode) => setState(() => _viewMode = mode),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(Icons.notifications_none, color: _textSecondary),
            onPressed: null,
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(Icons.settings, color: _textSecondary),
            tooltip: 'About',
            onPressed: _openAbout,
          ),
          const SizedBox(width: 8),
          Consumer<ThemeNotifier>(
            builder: (context, notifier, _) => IconButton(
              icon: Icon(
                notifier.isDark ? Icons.light_mode : Icons.dark_mode,
                size: 18,
                color: _textSecondary,
              ),
              onPressed: notifier.toggle,
              tooltip: notifier.isDark ? 'Light mode' : 'Dark mode',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopFeedHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Engineering Feed',
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Aggregated insights for SRE and DevOps operations.',
                  style: TextStyle(color: _textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          _feedToggleButton('Latest', selected: true, onTap: () {}),
          const SizedBox(width: 8),
          _feedToggleButton('Top', selected: false, onTap: _comingSoon),
        ],
      ),
    );
  }

  Widget _feedToggleButton(
    String label, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: selected ? kRed : _surface2,
        foregroundColor: selected ? Colors.white : _textSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        textStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.0,
        ),
      ),
      child: Text(label.toUpperCase()),
    );
  }

  Widget _buildDesktopGrid() {
    if (_filteredArticles.isEmpty && _searchQuery.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 56, color: _textMuted),
            const SizedBox(height: 12),
            Text(
              'No results for "$_searchQuery"',
              style: TextStyle(color: _textSecondary),
            ),
            TextButton(
              onPressed: () {
                _searchController.clear();
                _onSearchChanged('');
              },
              child: const Text('Clear search'),
            ),
          ],
        ),
      );
    }

    if (_filteredArticles.isEmpty && _isLoading) {
      return const Center(child: _PollingIndicator());
    }

    if (_filteredArticles.isEmpty) {
      return Center(
        child: Text(
          'No articles yet',
          style: TextStyle(color: _textSecondary),
        ),
      );
    }

    final showLoader = _isLoading;
    final itemCount = _filteredArticles.length + (showLoader ? 1 : 0);

    if (_viewMode == ViewMode.grid) {
      return GridView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(20),
        clipBehavior: Clip.none,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 500,
          mainAxisExtent: 236,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (index >= _filteredArticles.length) {
            return const Center(child: _PollingIndicator());
          }
          final article = _filteredArticles[index];
          return ArticleCard(
            article: article,
            onTap: () => _onArticleTap(article, desktop: true),
            showBookmarkButton: true,
            isBookmarked: _bookmarkStates[article.url] ?? false,
            onBookmarkToggle: () => _toggleBookmark(article),
          );
        },
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(20),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index >= _filteredArticles.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: _PollingIndicator()),
          );
        }
        final article = _filteredArticles[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ArticleCard(
            article: article,
            onTap: () => _onArticleTap(article, desktop: true),
            compact: true,
            showBookmarkButton: true,
            isBookmarked: _bookmarkStates[article.url] ?? false,
            onBookmarkToggle: () => _toggleBookmark(article),
          ),
        );
      },
    );
  }

  Widget _buildRightSidebar() {
    final sortedSources = _stableSourceCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topSources = sortedSources.take(4).toList();
    final maxCount = _stableSourceCounts.values
        .fold(0, (a, b) => a > b ? a : b);

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: _surface,
        border: Border(left: BorderSide(color: _border)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 81, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_displayedOcpVersions.isNotEmpty) ...[
              Text(
                'LATEST OPENSHIFT RELEASES',
                style: TextStyle(
                  fontSize: 10,
                  color: _textMuted,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 12),
              for (int i = 0; i < _displayedOcpVersions.length; i++) ...[
                _ocpVersionRow(
                  _displayedOcpVersions[i],
                  _ocpVersionAccent(i),
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () {
                    final summary = _buildVersionSummary();
                    if (summary.isEmpty) return;
                    Clipboard.setData(ClipboardData(text: summary));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: Color(0xFF00AA44),
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                summary,
                                style: const TextStyle(fontSize: 12),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        backgroundColor: const Color(0xFF1A1A1A),
                        duration: const Duration(seconds: 3),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                          side: const BorderSide(color: Color(0xFF2A2A2A)),
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00AA44).withValues(alpha: 0.1),
                      border: Border.all(
                        color: const Color(0xFF00AA44).withValues(alpha: 0.4),
                        width: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.copy, size: 10, color: Color(0xFF00AA44)),
                        SizedBox(width: 3),
                        Text(
                          'COPY',
                          style: TextStyle(
                            fontSize: 9,
                            color: Color(0xFF00AA44),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Divider(color: _border),
              const SizedBox(height: 24),
            ],
            if (_cveAlerts.isNotEmpty) ...[
              Text(
                'LATEST CVES',
                style: TextStyle(
                  fontSize: 10,
                  color: _textMuted,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 12),
              for (final alert in _cveAlerts) ...[
                _cveAlertRow(alert),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 12),
              Divider(color: _border),
              const SizedBox(height: 24),
            ],
            if (_latestReleases.isNotEmpty) ...[
              Text(
                'LATEST RELEASES',
                style: TextStyle(
                  fontSize: 10,
                  color: _textMuted,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 12),
              for (final release in _latestReleases) ...[
                _latestReleaseRow(release),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 12),
              Divider(color: _border),
              const SizedBox(height: 24),
            ],
            Text(
              "THIS WEEK'S TOP SOURCES",
              style: TextStyle(
                fontSize: 10,
                color: _textMuted,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 16),
            if (_stableSourceCounts.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Loading...',
                  style: TextStyle(fontSize: 11, color: _textMuted),
                ),
              )
            else
              ...[
                for (final entry in topSources) ...[
                  _topSourceRow(entry.key, entry.value, maxCount),
                  const SizedBox(height: 12),
                ],
              ],
            const SizedBox(height: 12),
            Divider(color: _border),
            const SizedBox(height: 24),
            Text(
              'POPULAR TAGS',
              style: TextStyle(
                fontSize: 10,
                color: _textMuted,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 16),
            if (_topTags.isEmpty)
              Text(
                'Loading...',
                style: TextStyle(fontSize: 11, color: _textMuted),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _topTags.map((tag) {
                  final isSelected = _tagFilter == tag;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        if (_tagFilter == tag) {
                          _tagFilter = null;
                          _selectedSource = null;
                        } else {
                          _tagFilter = tag;
                          _selectedSource = null;
                        }
                      });
                      _loadArticles(reset: true);
                    },
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? kRed.withValues(alpha: 0.15)
                              : _surface2,
                          border: Border.all(
                            color: isSelected ? kRed : _border,
                            width: isSelected ? 1 : 0.5,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '#$tag',
                          style: TextStyle(
                            fontSize: 11,
                            color: isSelected ? kRed : _textSecondary,
                            letterSpacing: 0.5,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            const SizedBox(height: 24),
            Divider(color: _border),
            const SizedBox(height: 24),
            _systemStatusCard(),
          ],
        ),
      ),
    );
  }

  Color _ocpVersionAccent(int index) {
    if (index <= 1) return _kReleaseGreen;
    if (index <= 3) return const Color(0xFFFFAA00);
    return _textMuted;
  }

  Widget _ocpVersionRow(OcpVersion version, Color accent) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openVersions,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Icon(Icons.layers, size: 12, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: version.minorVersion,
                        style: TextStyle(
                          color: _textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(
                        text: '  →  ${version.latestStable}',
                        style: TextStyle(color: _textSecondary),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                timeago.format(version.updatedAt),
                style: TextStyle(fontSize: 10, color: _textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cveAlertRow(CveAlert alert) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => launchUrl(
          Uri.parse(alert.articleUrl),
          mode: LaunchMode.externalApplication,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              const Icon(
                Icons.shield,
                size: 12,
                color: _kSecurityOrange,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  alert.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: _textPrimary),
                ),
              ),
              if (alert.createdAt != null) ...[
                const SizedBox(width: 4),
                Text(
                  timeago.format(alert.createdAt!),
                  style: TextStyle(fontSize: 10, color: _textMuted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _latestReleaseRow(Article article) {
    final when = article.publishedAt ?? article.createdAt;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onArticleTap(article, desktop: true),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              const Icon(
                Icons.rocket_launch,
                size: 12,
                color: _kReleaseGreen,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  article.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: _textPrimary),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                timeago.format(when),
                style: TextStyle(fontSize: 10, color: _textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topSourceRow(String source, int count, int maxCount) {
    final barFraction = maxCount > 0 ? count / maxCount : 0.0;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _onSourceSelected(source),
        behavior: HitTestBehavior.opaque,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    source,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: _textPrimary),
                  ),
                ),
                Text(
                  '$count posts',
                  style: TextStyle(fontSize: 11, color: _textMuted),
                ),
              ],
            ),
            const SizedBox(height: 6),
            LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    Container(
                      height: 2,
                      width: constraints.maxWidth,
                      color: _border,
                    ),
                    Container(
                      height: 2,
                      width: constraints.maxWidth * barFraction,
                      color: kRed,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _systemStatusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface2,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'System Status',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _scraperStatusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _scraperStatusLabel,
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.5,
                  color: _scraperStatusColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _scraperStatusDetail,
            style: TextStyle(
              fontSize: 11,
              color: _textMuted,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PollingIndicator extends StatelessWidget {
  const _PollingIndicator();

  @override
  Widget build(BuildContext context) {
    final muted = textMutedOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(color: kRed, strokeWidth: 2),
        ),
        const SizedBox(height: 12),
        Text(
          'POLLING SOURCES...',
          style: TextStyle(fontSize: 11, color: muted, letterSpacing: 2),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _ViewToggle extends StatelessWidget {
  final ViewMode viewMode;
  final ValueChanged<ViewMode> onChanged;

  const _ViewToggle({required this.viewMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final border = borderOf(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(6),
        color: surfaceOf(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleBtn(
            icon: Icons.grid_view_rounded,
            selected: viewMode == ViewMode.grid,
            onTap: () => onChanged(ViewMode.grid),
          ),
          Container(width: 1, height: 28, color: border),
          _ToggleBtn(
            icon: Icons.view_list_rounded,
            selected: viewMode == ViewMode.list,
            onTap: () => onChanged(ViewMode.list),
          ),
        ],
      ),
    );
  }
}

class _ToggleBtn extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleBtn({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final secondary = textSecondaryOf(context);
    return Material(
      color: selected ? kRed.withValues(alpha: 0.15) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Center(
            child: Icon(
              icon,
              size: 16,
              color: selected ? kRed : secondary,
            ),
          ),
        ),
      ),
    );
  }
}

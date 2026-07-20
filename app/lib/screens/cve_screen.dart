import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../models/article.dart';
import '../models/cve_severity.dart';
import '../repositories/article_repository.dart';
import '../theme/app_theme.dart';
import '../utils/open_article.dart';
import '../widgets/error_state.dart';
import '../widgets/filter_pill.dart';
import '../widgets/main_app_bar.dart';
import '../widgets/offline_banner.dart';
import '../widgets/toggle_button.dart';

/// How CVE rows are ordered. Severity sort still falls back to date
/// within a bucket — a page of twenty CRITICALs in arbitrary order isn't
/// useful.
enum CveSort { date, severity }

/// The CVE list — every `cve`-tagged article, with the two stored
/// severity vocabularies collapsed onto one display scale.
///
/// Free for everyone; there is no Pro gate on viewing. See the seam
/// marked "PRO SEAM" in [_buildAppBarActions] for where the later
/// "CVE alerts (Pro)" entry point lands.
class CveScreen extends StatefulWidget {
  /// Whether this screen is the visible tab. Inside the mobile
  /// `IndexedStack` the State is kept alive, so `initState` runs only once
  /// at launch; the parent flips this when the CVE tab is selected so a
  /// previously-empty/failed load can self-heal on revisit. Defaults to
  /// true for the desktop push-route case where the screen is built fresh.
  final bool isActive;

  /// True when this screen is a bottom-nav tab: it then wears the shared
  /// [MainAppBar]. False on the desktop push-route, which keeps its own
  /// descriptive title and back arrow.
  final bool isTab;

  const CveScreen({
    super.key,
    this.isActive = true,
    this.isTab = false,
  });

  @override
  State<CveScreen> createState() => _CveScreenState();
}

class _CveScreenState extends State<CveScreen> {
  static const int _pageSize = 50;

  final ArticleRepository _repository = ArticleRepository();
  final ScrollController _scrollController = ScrollController();

  List<Article> _articles = [];
  bool _isLoading = true;
  bool _loadFailed = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  CveSort _sort = CveSort.date;
  final Set<CveSeverity> _severityFilter = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(CveScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Self-heal on tab revisit — same pattern as VersionsScreen. The
    // IndexedStack keeps this State alive, so initState only ran once at
    // launch; re-attempt a load that came up empty or failed, but skip
    // when data is already good or a load is in flight.
    if (!oldWidget.isActive &&
        widget.isActive &&
        !_isLoading &&
        (_articles.isEmpty || _loadFailed)) {
      _load();
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });
    try {
      final rows = await _repository.fetchCveArticles(limit: _pageSize);
      if (!mounted) return;
      setState(() {
        _articles = rows;
        _hasMore = rows.length == _pageSize;
        _isLoading = false;
      });
    } on RepoException {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadFailed = true;
      });
    } catch (e) {
      // Any non-repo failure — surface the recoverable error state rather
      // than a silent blank or a stuck spinner.
      debugPrint('CveScreen: load error: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _isLoading) return;
    setState(() => _isLoadingMore = true);
    try {
      final rows = await _repository.fetchCveArticles(
        limit: _pageSize,
        offset: _articles.length,
      );
      if (!mounted) return;
      setState(() {
        _articles = [..._articles, ...rows];
        _hasMore = rows.length == _pageSize;
        _isLoadingMore = false;
      });
    } catch (e) {
      // A failed *page 2+* keeps the rows already on screen — dropping to
      // the full-screen ErrorState here would throw away good data.
      debugPrint('CveScreen: loadMore error: $e');
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  /// Filter + sort applied client-side, over the pages fetched so far.
  ///
  /// Server-side would be better on both counts, but severity lives in a
  /// text[] tag rather than a column, so filtering it in Postgres means an
  /// `overlaps` against six words spanning two vocabularies — and the
  /// normalized ordering doesn't exist server-side at all. The page size
  /// keeps this cheap.
  List<Article> get _visible {
    final rows = _severityFilter.isEmpty
        ? [..._articles]
        : _articles
            .where((a) {
              final s = CveSeverity.fromTags(a.tags);
              return s != null && _severityFilter.contains(s);
            })
            .toList();

    if (_sort == CveSort.severity) {
      rows.sort((a, b) {
        final sa = CveSeverity.fromTags(a.tags)?.rank ?? 0;
        final sb = CveSeverity.fromTags(b.tags)?.rank ?? 0;
        if (sa != sb) return sb.compareTo(sa);
        // Within a severity bucket, newest first — then url, mirroring
        // the server-side tiebreaker so the order is fully determined.
        final da = a.publishedAt;
        final db = b.publishedAt;
        if (da != null && db != null && da != db) return db.compareTo(da);
        if (da == null && db != null) return 1;
        if (da != null && db == null) return -1;
        return a.url.compareTo(b.url);
      });
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final bg = bgOf(context);

    return Scaffold(
      backgroundColor: bg,
      appBar: widget.isTab
          // Nothing here responds to search or the card view mode, so both
          // stay greyed out.
          ? MainAppBar(leadingActions: _buildAppBarActions())
          : AppBar(
              title: Text(
                'CVE ALERTS',
                style: AppTextStyles.screenTitle,
              ),
              backgroundColor: bg,
              actions: _buildAppBarActions(),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Container(height: 1, color: kRed),
              ),
            ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  List<Widget> _buildAppBarActions() {
    // PRO SEAM — the "CVE alerts (Pro)" entry point lands here: a bell
    // IconButton that opens the alert-subscription sheet, gated on
    // `EntitlementService.instance.isPro()` with a PaywallSheet fallback
    // (PaywallReason.notifications). Nothing is gated today; viewing this
    // screen stays free regardless of what gets added here.
    return const [];
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: kRed));
    }

    if (_loadFailed && _articles.isEmpty) {
      return ErrorState(
        title: "Couldn't load CVEs",
        body: 'Check your connection and try again.',
        onRetry: _load,
      );
    }

    final rows = _visible;

    return RefreshIndicator(
      onRefresh: _load,
      color: kRed,
      backgroundColor: surfaceOf(context),
      child: CustomScrollView(
        controller: _scrollController,
        // Always scrollable so pull-to-refresh works even when the list is
        // empty or short — otherwise the empty state can't be refreshed.
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildControls()),
          if (rows.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildEmpty(),
            )
          else
            SliverList.separated(
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) => CveRow(
                article: rows[i],
                onTap: () => openArticle(context, rows[i]),
              ),
            ),
          if (_isLoadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: kRed,
                      strokeWidth: 2,
                    ),
                  ),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    final filtered = _severityFilter.isNotEmpty && _articles.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              filtered ? Icons.filter_alt_off : Icons.shield_outlined,
              size: 48,
              color: textMutedOf(context),
            ),
            const SizedBox(height: 16),
            Text(
              filtered
                  ? 'No CVEs match this filter'
                  : 'No CVEs tracked yet',
              textAlign: TextAlign.center,
              style: TextStyle(color: textSecondaryOf(context)),
            ),
            const SizedBox(height: 16),
            if (filtered)
              OutlinedButton.icon(
                onPressed: () => setState(_severityFilter.clear),
                icon: const Icon(Icons.clear, size: 16),
                label: const Text('Clear filter'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kRed,
                  side: BorderSide(color: kRed.withValues(alpha: 0.5)),
                ),
              )
            else
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kRed,
                  side: BorderSide(color: kRed.withValues(alpha: 0.5)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The 8dp rhythm governing the whole control block: red rule → sort
  /// row → filter row → grey divider → first CVE card. One constant so
  /// the gaps can't drift apart.
  static const double _gap = 8;

  /// Gap between a row's label and its controls.
  static const double _labelGap = 10;

  Widget _buildControls() {
    // textSecondary, not textMuted: muted is #555555, which against the
    // #0D0D0D dark background is 2.61:1 — the same contrast failure the
    // old bespoke chips had. Secondary clears 5:1.
    final labelStyle = TextStyle(
      fontSize: 9,
      color: textSecondaryOf(context),
      letterSpacing: 1.5,
      fontWeight: FontWeight.w700,
    );
    // Both labels occupy the width of the wider one, so the sort buttons
    // and the severity pills share a left edge. Measured rather than
    // hardcoded: 'FILTER' is wider than 'SORT' by an amount that depends
    // on the resolved font and the user's text scale.
    final labelWidth = _labelColumnWidth(context, labelStyle);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, _gap, 16, _gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: labelWidth,
                child: Text('SORT', style: labelStyle),
              ),
              const SizedBox(width: _labelGap),
              _sortButton('Date', CveSort.date),
              const SizedBox(width: 6),
              _sortButton('Severity', CveSort.severity),
            ],
          ),
          const SizedBox(height: _gap),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: labelWidth,
                child: Text('FILTER', style: labelStyle),
              ),
              const SizedBox(width: _labelGap),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in CveSeverity.values) _severityPill(s),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: _gap),
          Divider(color: borderOf(context), height: 1),
        ],
      ),
    );
  }

  /// Width of the widest row label, so both rows' controls start at the
  /// same x. Measures the MERGED style the [Text] will resolve to — the
  /// bare style omits the theme's font, which would under-measure and
  /// clip 'FILTER'. Same reasoning as [FilterPill.heightOf].
  double _labelColumnWidth(BuildContext context, TextStyle style) {
    final merged = DefaultTextStyle.of(context).style.merge(style);
    final scaler = MediaQuery.textScalerOf(context);
    var widest = 0.0;
    for (final label in const ['SORT', 'FILTER']) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: merged),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      if (painter.width > widest) widest = painter.width;
    }
    return widest;
  }

  Widget _sortButton(String label, CveSort value) {
    return ToggleButton(
      label: label,
      selected: _sort == value,
      // Match the severity pills' height — the two rows read as one
      // control block.
      dense: true,
      onTap: () => setState(() => _sort = value),
    );
  }

  Widget _severityPill(CveSeverity severity) {
    return FilterPill(
      label: severity.label,
      selected: _severityFilter.contains(severity),
      // The bucket's own color carries the meaning; onAccent inside
      // FilterPill keeps the label readable on it (notably the amber).
      selectedColor: severity.color,
      onTap: () => setState(() {
        // Multi-select: empty set means "all", which is why we toggle
        // rather than replace.
        if (!_severityFilter.remove(severity)) _severityFilter.add(severity);
      }),
    );
  }
}

/// One CVE row: a header line carrying the severity badge, CVSS score and
/// CVE id(s), then the title and source.
///
/// Public only so `test/cve_row_layout_test.dart` can render it at a real
/// phone width — the header's one-line layout is load-bearing (it's what
/// keeps the card short) and can only break as a render overflow, which
/// nothing but a widget test catches.
class CveRow extends StatelessWidget {
  final Article article;
  final VoidCallback onTap;

  const CveRow({super.key, required this.article, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final surface = surfaceOf(context);
    final border = borderOf(context);
    final textPrimary = textPrimaryOf(context);
    final textMuted = textMutedOf(context);

    final severity = CveSeverity.fromTags(article.tags);
    final cvss = cvssFromTags(article.tags);
    final ids = cveIdsFromTags(article.tags);
    // Severity color is spent in exactly two places: the left edge stripe
    // and the severity badge. Everything else on the row — CVE ids, CVSS
    // score, title, source — is neutral, so the color means one thing and
    // the eye isn't asked to decode it four times per card.
    final accent = severity?.color ?? kRed;
    final published = article.publishedAt;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Container(
              decoration: BoxDecoration(
                color: surface,
                border: Border.all(color: border, width: 0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 3, color: accent),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Severity, score and CVE ids share one line:
                            // they all identify the same vulnerability, and
                            // folding them together drops a whole row off
                            // every card.
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    // Order: CVE id, then CVSS, then
                                    // severity. The id is what identifies
                                    // the row, so it leads and the two
                                    // badges qualify it.
                                    children: [
                                      // One joined Text, not one child per
                                      // id. The Wrap hands it the full
                                      // remaining width and Text soft-wraps
                                      // itself, so a multi-CVE advisory
                                      // never overflows — and it lands 6dp
                                      // SHORTER than separate children,
                                      // which pay this Wrap's runSpacing to
                                      // break between ids.
                                      if (ids.isNotEmpty)
                                        Text(
                                          ids.join('  '),
                                          // textPrimary, not a literal white —
                                          // the same row renders on a light
                                          // background in light mode.
                                          style: AppTextStyles.technicalLabel
                                              .copyWith(color: textPrimary),
                                        ),
                                      if (cvss != null)
                                        // Neutral, not the severity accent:
                                        // the severity badge sits right
                                        // beside it, so coloring the number
                                        // too is redundant.
                                        _badge(
                                          'CVSS ${cvss.toStringAsFixed(1)}',
                                          textPrimary,
                                        ),
                                      if (severity != null)
                                        _badge(
                                          severity.label,
                                          severity.color,
                                        ),
                                    ],
                                  ),
                                ),
                                if (published != null) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    timeago.format(published),
                                    style: AppTextStyles.caption.copyWith(color: textMuted),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              article.title,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              article.source,
                              style: AppTextStyles.caption.copyWith(color: textMuted),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color, width: 0.5),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

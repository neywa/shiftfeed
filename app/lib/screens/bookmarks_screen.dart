import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/article.dart';
import '../repositories/article_repository.dart';
import '../services/bookmark_article_cache.dart';
import '../services/bookmark_service.dart';
import '../services/entitlement_service.dart';
import '../theme/app_theme.dart';
import '../theme/layout_notifier.dart';
import '../utils/open_article.dart';
import '../widgets/article_card.dart';
import '../widgets/error_state.dart';
import '../widgets/main_app_bar.dart';
import '../widgets/offline_banner.dart';
import '../widgets/paywall_sheet.dart';

class BookmarksScreen extends StatefulWidget {
  /// True when this screen is a bottom-nav tab: it then wears the shared
  /// [MainAppBar] (wordmark + the four actions). False on the desktop
  /// push-route, which keeps its own descriptive title and back arrow.
  final bool isTab;

  /// Whether this screen is the visible tab. Inside the mobile `IndexedStack`
  /// the State is kept alive, so `initState` runs only once at launch; the
  /// parent flips this when the Saved tab is selected so the swipe-to-delete
  /// hint replays on every visit. Defaults to true for the desktop
  /// push-route case where the screen is built fresh.
  final bool isActive;

  const BookmarksScreen({
    super.key,
    this.isTab = false,
    this.isActive = true,
  });

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

/// SharedPreferences flag: set once the user has swipe-deleted a saved
/// article. Until then the first card demos the gesture on every visit.
const String _kSwipeHintDonePref = 'saved_swipe_hint_done';

/// How far left the first card slides during the hint — clears the 24px
/// trash icon plus its 20px right padding.
const double _kHintPeek = 88.0;

/// Beat between the screen settling and the hint playing, so the user's eyes
/// are on the list before the card moves.
const Duration _kHintDelay = Duration(milliseconds: 400);

class _BookmarksScreenState extends State<BookmarksScreen>
    with SingleTickerProviderStateMixin {
  final ArticleRepository _repo = ArticleRepository();

  // URL → Article cache used to render rich cards from the URL-only stream.
  // Hydrated from [BookmarkArticleCache] on initState so the screen is
  // immediately useful offline; live fetches update it in place.
  final Map<String, Article> _articleCache = {};

  // The set of URLs whose Article rows we've already requested in this
  // session — avoids re-fetching the same URL multiple times.
  final Set<String> _fetchedUrls = {};

  bool _fetchingArticles = false;
  bool _hydratedFromCache = false;
  bool _resolveFailed = false;

  // Swipe-to-delete hint. `_hintDone` is the persisted "user has learned the
  // gesture" flag; `_hintArmed` means a visit is pending a demo — it is set
  // on activation and cleared when the animation is scheduled, so a single
  // visit plays the hint exactly once even though `build` runs many times.
  late final AnimationController _hintController;
  late final Animation<double> _hint;
  bool _hintDone = true;
  bool _hintArmed = false;

  @override
  void initState() {
    super.initState();
    _hintController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    // Slide out, then bounce home. `bounceOut` (not `elasticOut`) because it
    // never overshoots past its end value: the card settles at rest without
    // ever sliding right of its origin, and the trash icon stays visible
    // through the bounces — which is the point of the demo.
    _hint = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0).chain(
          CurveTween(curve: Curves.easeOut),
        ),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0).chain(
          CurveTween(curve: Curves.bounceOut),
        ),
        weight: 70,
      ),
    ]).animate(_hintController);
    _hydrateFromCache();
    _loadHintState();
  }

  @override
  void didUpdateWidget(BookmarksScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The IndexedStack keeps this State alive, so initState only ran once at
    // launch. Re-arm on the false -> true edge so the demo replays every time
    // the user comes back to the tab.
    if (!oldWidget.isActive && widget.isActive) {
      _hintArmed = true;
    }
  }

  @override
  void dispose() {
    _hintController.dispose();
    super.dispose();
  }

  /// Reads the persisted "already learned it" flag. Starts pessimistic
  /// (`_hintDone = true`) so a slow prefs read can't flash the hint at a user
  /// who has already dismissed an article by swiping.
  Future<void> _loadHintState() async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool(_kSwipeHintDonePref) ?? false;
    if (!mounted || done) return;
    setState(() {
      _hintDone = false;
      _hintArmed = widget.isActive;
    });
  }

  /// Records that the user swiped an article away — the gesture is learned,
  /// so the hint retires for good. Called only from the Dismissible's
  /// `onDismissed`; removing a bookmark with the in-card icon is a different
  /// gesture and must not count.
  Future<void> _markHintDone() async {
    if (_hintDone) return;
    setState(() {
      _hintDone = true;
      _hintArmed = false;
    });
    _hintController.reset();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSwipeHintDonePref, true);
  }

  /// Plays the demo once the list actually has a card to move. Called from
  /// `_buildBody`, since articles resolve asynchronously and the first card
  /// may not exist yet at the moment the tab becomes active.
  void _maybePlayHint() {
    if (!_hintArmed || _hintDone) return;
    _hintArmed = false;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(_kHintDelay);
      if (!mounted || _hintDone || !widget.isActive) return;
      _hintController.forward(from: 0);
    });
  }

  Future<void> _hydrateFromCache() async {
    final cached = await BookmarkArticleCache.instance.load();
    if (!mounted || cached.isEmpty) {
      if (mounted) setState(() => _hydratedFromCache = true);
      return;
    }
    setState(() {
      _articleCache.addAll(cached);
      _hydratedFromCache = true;
    });
  }

  Future<void> _resolveMissing(List<String> urls) async {
    final missing = urls.where((u) => !_fetchedUrls.contains(u)).toList();
    if (missing.isEmpty) return;
    _fetchingArticles = true;
    _fetchedUrls.addAll(missing);
    try {
      final articles = await _repo.fetchArticlesByUrls(missing);
      if (!mounted) return;
      setState(() {
        for (final a in articles) {
          _articleCache[a.url] = a;
        }
        _fetchingArticles = false;
        _resolveFailed = false;
      });
      // Persist resolved bodies so the Saved screen is usable offline
      // on the next cold start. Prune the on-disk cache to the current
      // bookmark URL list so removed bookmarks don't leak storage.
      await BookmarkArticleCache.instance.save(articles);
      await BookmarkArticleCache.instance.pruneToUrls(urls);
    } on RepoException {
      if (!mounted) return;
      // Allow a future call to retry these URLs once back online.
      _fetchedUrls.removeAll(missing);
      setState(() {
        _fetchingArticles = false;
        _resolveFailed = true;
      });
    }
  }

  void _openArticle(Article article) {
    openArticle(context, article);
  }

  /// Removes [url] from bookmarks and shows a theme-aware SnackBar with
  /// an Undo action that re-adds it via [BookmarkService.addBookmark].
  /// Used by both the in-card bookmark icon and the swipe-to-dismiss
  /// gesture so the two removal paths behave consistently.
  void _removeWithUndo(BuildContext context, String url) {
    final messenger = ScaffoldMessenger.of(context);
    BookmarkService.instance.removeBookmark(url);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Removed from saved',
          style: TextStyle(
            fontSize: 13,
            color: textPrimaryOf(context),
          ),
        ),
        backgroundColor: surfaceOf(context),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: borderOf(context)),
        ),
        action: SnackBarAction(
          label: 'Undo',
          textColor: kRed,
          onPressed: () => BookmarkService.instance.addBookmark(url),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final secondary = textSecondaryOf(context);
    final muted = textMutedOf(context);
    // Saved honours the app bar's view-mode toggle, same as the feed.
    final compact = context.watch<LayoutNotifier>().mode == ViewMode.list;

    return StreamBuilder<List<String>>(
      stream: BookmarkService.instance.watchBookmarks(),
      initialData: const [],
      builder: (context, snapshot) {
        final urls = snapshot.data ?? const <String>[];
        // Kick off any missing-article fetches without awaiting in build.
        if (urls.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _resolveMissing(urls),
          );
        }
        final articles = <Article>[
          for (final url in urls)
            if (_articleCache[url] != null) _articleCache[url]!,
        ];

        return Scaffold(
          backgroundColor: bgOf(context),
          appBar: widget.isTab
              // The cards here honour the view mode, so that toggle stays
              // live; there is no search on this screen, so it greys out.
              ? const MainAppBar(viewToggleEnabled: true)
              : AppBar(
                  backgroundColor: bgOf(context),
                  title: const Text(
                    'SAVED',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 2,
                    ),
                  ),
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(1),
                    child: Container(height: 1, color: kRed),
                  ),
                ),
          body: Column(
            children: [
              const OfflineBanner(),
              Expanded(
                child: _buildBody(urls, articles, secondary, muted, compact),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(
    List<String> urls,
    List<Article> articles,
    Color secondary,
    Color muted,
    bool compact,
  ) {
    if (urls.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmark_outline, size: 64, color: muted),
            const SizedBox(height: 16),
            Text(
              'No saved articles',
              style: TextStyle(
                fontSize: 16,
                color: secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the bookmark icon on any article to save it',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: muted),
            ),
          ],
        ),
      );
    }

    // Got bookmark URLs but no rendered articles: distinguish three
    // states so the screen never sits forever on a stuck spinner.
    if (articles.isEmpty) {
      // (1) Cache hydration in flight OR a fetch is in flight — short
      // spinner. Both finish quickly in practice.
      if (!_hydratedFromCache || _fetchingArticles) {
        return const Center(
          child: CircularProgressIndicator(color: kRed),
        );
      }
      // (2) Cache is empty AND the network fetch failed — clear
      // offline-unavailable message with a retry, NOT a stuck spinner
      // or a lone upsell banner.
      if (_resolveFailed) {
        return ErrorState(
          title: 'Saved articles unavailable offline',
          body: 'Open this screen once online to cache your bookmarks '
              'for offline reading.',
          onRetry: () {
            _fetchedUrls.removeAll(urls);
            _resolveMissing(urls);
          },
        );
      }
    }

    // Only once there is a card to demo the gesture on: a bookmark whose
    // Article row hasn't resolved yet renders nothing to slide.
    if (articles.isNotEmpty) _maybePlayHint();

    // 8dp rhythm, matching the feed: divider -> banner -> card -> card, with
    // 12dp of run-off under the last card. The gap sits below each item
    // rather than in a separator so the upsell banner — which collapses to
    // nothing for Pro users and on web — leaves no ghost gap when hidden.
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      itemCount: articles.length + 1, // +1 for the upsell banner slot
      itemBuilder: (context, index) {
        if (index == 0) {
          return const _UpsellBanner();
        }
        final article = articles[index - 1];
        final isLast = index == articles.length;
        Widget card = ArticleCard(
          article: article,
          onTap: () => _openArticle(article),
          compact: compact,
          showBookmarkButton: true,
          isBookmarked: true,
          onBookmarkToggle: () => _removeWithUndo(context, article.url),
        );
        if (index == 1 && !_hintDone) {
          card = _wrapWithHint(card);
        }
        return Dismissible(
          key: Key(article.url),
          direction: DismissDirection.endToStart,
          background: _deleteReveal(context),
          onDismissed: (_) {
            _removeWithUndo(context, article.url);
            _markHintDone();
          },
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
            child: card,
          ),
        );
      },
    );
  }

  /// What sits behind a card as it slides left — the plain screen background
  /// with a trash icon on it. Shared by the Dismissible's drag reveal and the
  /// hint animation so the demo shows exactly what the real gesture shows.
  Widget _deleteReveal(BuildContext context) => Container(
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.only(right: 20),
    child: Icon(Icons.delete_outline, color: textMutedOf(context)),
  );

  /// Drives the first card through the swipe demo. The overlay only exists
  /// while the animation is running — at rest the card is returned untouched,
  /// so nothing interferes with the Dismissible's own drag.
  Widget _wrapWithHint(Widget card) {
    return Listener(
      // A real touch always wins: yield instantly rather than fighting the
      // Dismissible's drag offset with our own transform.
      onPointerDown: (_) {
        if (_hintController.isAnimating) _hintController.reset();
      },
      child: AnimatedBuilder(
        animation: _hint,
        builder: (context, child) {
          if (_hint.value == 0) return child!;
          return Stack(
            children: [
              Positioned.fill(child: _deleteReveal(context)),
              Transform.translate(
                offset: Offset(-_hint.value * _kHintPeek, 0),
                child: child,
              ),
            ],
          );
        },
        child: card,
      ),
    );
  }
}

class _UpsellBanner extends StatelessWidget {
  const _UpsellBanner();

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();
    return FutureBuilder<bool>(
      future: EntitlementService.instance.isPro(),
      builder: (context, snap) {
        if (snap.data == true) return const SizedBox.shrink();
        final theme = Theme.of(context);
        return Padding(
          // Owns the gap to the first card, so a hidden banner leaves none.
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: theme.dividerColor),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.cloud_sync_outlined, color: kRed, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Upgrade to Pro to sync bookmarks across all your '
                      'devices',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => PaywallSheet.show(
                      context,
                      reason: PaywallReason.sync,
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: kRed,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Upgrade',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

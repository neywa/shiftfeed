import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/article.dart';
import '../repositories/article_repository.dart';
import '../services/bookmark_service.dart';
import '../services/entitlement_service.dart';
import '../services/export_service.dart';
import '../services/user_service.dart';
import '../theme/app_theme.dart';
import '../widgets/article_card.dart';
import '../widgets/paywall_sheet.dart';

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  final ArticleRepository _repo = ArticleRepository();

  // URL → Article cache used to render rich cards from the URL-only stream.
  final Map<String, Article> _articleCache = {};

  // The set of URLs whose Article rows we've already requested in this
  // session — avoids re-fetching the same URL multiple times.
  final Set<String> _fetchedUrls = {};

  bool _fetchingArticles = false;

  Future<void> _resolveMissing(List<String> urls) async {
    final missing = urls.where((u) => !_fetchedUrls.contains(u)).toList();
    if (missing.isEmpty) return;
    _fetchingArticles = true;
    _fetchedUrls.addAll(missing);
    final articles = await _repo.fetchArticlesByUrls(missing);
    if (!mounted) return;
    setState(() {
      for (final a in articles) {
        _articleCache[a.url] = a;
      }
      _fetchingArticles = false;
    });
  }

  void _openArticle(Article article) {
    launchUrl(
      Uri.parse(article.url),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _showExportSheet() async {
    final scaffoldContext = context;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.text_snippet_outlined),
                title: const Text('Export as Markdown'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  ExportService.instance.shareBookmarks(
                    scaffoldContext,
                    asPdf: false,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: const Text('Export as PDF'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  ExportService.instance.shareBookmarks(
                    scaffoldContext,
                    asPdf: true,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
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

  Future<void> _showClearConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all bookmarks?'),
        content: const Text('This will remove all saved articles.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: kRed),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await BookmarkService.instance.clearAll();
  }

  @override
  Widget build(BuildContext context) {
    final secondary = textSecondaryOf(context);
    final muted = textMutedOf(context);

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
          appBar: AppBar(
            backgroundColor: bgOf(context),
            title: const Text(
              'SAVED',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 2,
              ),
            ),
            actions: [
              if (urls.isNotEmpty)
                _ExportAction(onTriggered: _showExportSheet),
              const _SyncIndicator(),
              if (urls.isNotEmpty)
                IconButton(
                  icon: Icon(Icons.delete_sweep_outlined, color: secondary),
                  tooltip: 'Clear all',
                  onPressed: _showClearConfirmation,
                ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(height: 1, color: kRed),
            ),
          ),
          body: _buildBody(urls, articles, secondary, muted),
        );
      },
    );
  }

  Widget _buildBody(
    List<String> urls,
    List<Article> articles,
    Color secondary,
    Color muted,
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

    if (articles.isEmpty && _fetchingArticles) {
      return const Center(
        child: CircularProgressIndicator(color: kRed),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: articles.length + 1, // +1 for the upsell banner slot
      itemBuilder: (context, index) {
        if (index == 0) {
          return const _UpsellBanner();
        }
        final article = articles[index - 1];
        return Dismissible(
          key: Key(article.url),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: Colors.red.withValues(alpha: 0.8),
            child: const Icon(Icons.delete_outline, color: Colors.white),
          ),
          onDismissed: (_) => _removeWithUndo(context, article.url),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ArticleCard(
              article: article,
              onTap: () => _openArticle(article),
              showBookmarkButton: true,
              isBookmarked: true,
              onBookmarkToggle: () => _removeWithUndo(context, article.url),
            ),
          ),
        );
      },
    );
  }
}

class _ExportAction extends StatelessWidget {
  final VoidCallback onTriggered;
  const _ExportAction({required this.onTriggered});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();
    return FutureBuilder<bool>(
      future: EntitlementService.instance.isPro(),
      builder: (context, snap) {
        final isPro = snap.data ?? false;
        return IconButton(
          icon: Icon(Icons.ios_share, color: textSecondaryOf(context)),
          tooltip: 'Export bookmarks',
          onPressed: () {
            if (isPro) {
              onTriggered();
            } else {
              PaywallSheet.show(context, reason: PaywallReason.briefing);
            }
          },
        );
      },
    );
  }
}

class _SyncIndicator extends StatelessWidget {
  const _SyncIndicator();

  Future<bool> _shouldShow() async {
    if (!UserService.instance.isSignedIn) return false;
    return EntitlementService.instance.isPro();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _shouldShow(),
      builder: (context, snap) {
        if (snap.data != true) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Tooltip(
            message: 'Bookmarks synced across devices',
            child: Icon(
              Icons.cloud_done_outlined,
              size: 20,
              color: textSecondaryOf(context),
            ),
          ),
        );
      },
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
          padding: const EdgeInsets.only(bottom: 12),
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

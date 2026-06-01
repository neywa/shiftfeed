import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../models/article.dart';

const List<String> _monthAbbr = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDate(DateTime d) {
  final day = d.day.toString().padLeft(2, '0');
  return '$day ${_monthAbbr[d.month - 1]} ${d.year}';
}

// OCP Versions scraper — single source of truth for OpenShift release
// articles (see scraper/sources/ocp_versions.py).
const String _kOcpVersionsSource = 'OCP Versions';
final RegExp _kOcpPatchVersionPattern = RegExp(r'\b4\.\d+\.\d+\b');

/// Whether [raw] is an `http`/`https` URL that is safe to load in the
/// WebView or hand to the external browser.
///
/// A custom-feed article's link is the feed entry `<link>`, controlled by
/// a third-party feed operator. A `javascript:`, `data:`, `file://` or
/// custom-scheme link would otherwise execute inside the WebView (JS is
/// enabled) or read local files, so every other scheme is refused — both
/// for the initial load and for in-page navigations/redirects.
bool _isSafeWebUrl(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null) return false;
  final scheme = uri.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https';
}

/// Returns the OpenShift Release Status dashboard URL for [article], or
/// null if the article isn't from the OCP Versions scraper or no
/// patch-level version (`4.X.Y`) appears in title/summary.
String? _releaseStatusUrl(Article article) {
  if (article.source != _kOcpVersionsSource) return null;
  final haystack = '${article.title} ${article.summary ?? ''}';
  final match = _kOcpPatchVersionPattern.firstMatch(haystack);
  if (match == null) return null;
  return 'https://openshift-release.apps.ci.l2s4.p1.openshiftapps.com'
      '/releasestream/4-stable/release/${match.group(0)}';
}

class ArticleDetailScreen extends StatefulWidget {
  final String url;
  final String title;

  /// The full [Article] when the reader was opened from a feed/saved
  /// tap. Null when opened by URL only (e.g. an AI-digest "top story"
  /// entry, which carries no source/date/summary/tags) — the body and
  /// AppBar fall back gracefully in that case rather than displaying
  /// fabricated values.
  final Article? article;

  const ArticleDetailScreen._({
    super.key,
    required this.url,
    required this.title,
    this.article,
  });

  factory ArticleDetailScreen({Key? key, required Article article}) =>
      ArticleDetailScreen._(
        key: key,
        url: article.url,
        title: article.title,
        article: article,
      );

  factory ArticleDetailScreen.url({
    Key? key,
    required String url,
    String? title,
  }) =>
      ArticleDetailScreen._(
        key: key,
        url: url,
        title: title ?? '',
      );

  @override
  State<ArticleDetailScreen> createState() => _ArticleDetailScreenState();
}

class _ArticleDetailScreenState extends State<ArticleDetailScreen> {
  bool _isLoading = true;
  WebViewController? _controller;

  /// True when the article URL used an unsupported (non-http/https) scheme
  /// so we refused to load it into the WebView and showed the safe
  /// fallback card instead. Only ever set on WebView-capable platforms.
  bool _blockedUnsafeScheme = false;

  /// Computed once from [Article.title] + [Article.summary]. Non-null only
  /// for OCP Versions articles where a patch version was extractable —
  /// always null when the screen was opened via [ArticleDetailScreen.url].
  late final String? _releaseUrl = widget.article == null
      ? null
      : _releaseStatusUrl(widget.article!);

  bool get _supportsWebView =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    if (_supportsWebView) {
      _initWebView();
    }
  }

  void _initWebView() {
    // Refuse to load anything but http/https. The article URL can be an
    // attacker-controlled custom-feed link; loading a javascript:/data:/
    // file:// scheme here would execute it in the WebView. Fall back to
    // the article card + "open in browser" affordance instead.
    if (!_isSafeWebUrl(widget.url)) {
      _blockedUnsafeScheme = true;
      return;
    }

    // Use Android-specific creation params so file access can be locked
    // down below; other platforms get the default params.
    final params = WebViewPlatform.instance is AndroidWebViewPlatform
        ? AndroidWebViewControllerCreationParams()
        : const PlatformWebViewControllerCreationParams();

    final controller = WebViewController.fromPlatformCreationParams(params)
      // Many article pages need JS to render (lazy images, CMS shells), so
      // JS stays unrestricted for readability — but the scheme check above
      // and the onNavigationRequest below bound what URLs can ever load.
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          // Block in-page redirects/links to non-http(s) schemes
          // (javascript:, data:, file://, intent://, custom schemes);
          // allow normal http/https article browsing.
          onNavigationRequest: (request) => _isSafeWebUrl(request.url)
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() => _isLoading = false);
          },
        ),
      );

    // Android: disable filesystem access so a file:// URL that somehow
    // reaches the WebView can't read local files. The related
    // allowFileAccessFromFileURLs / allowUniversalAccessFromFileURLs
    // settings aren't surfaced by webview_flutter_android and already
    // default to false on modern Android; file:// is also blocked at the
    // navigation layer above.
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setAllowFileAccess(false);
    }

    controller.loadRequest(Uri.parse(widget.url));
    _controller = controller;
  }

  Future<void> _openInBrowser() async {
    // The escape hatch must not become a bypass: never hand a non-http(s)
    // (e.g. javascript:/file://) article URL to the external launcher.
    if (!_isSafeWebUrl(widget.url)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("This link can't be opened safely.")),
      );
      return;
    }
    await launchUrl(
      Uri.parse(widget.url),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _openReleaseStatus() async {
    final url = _releaseUrl;
    if (url == null) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appBarTitle = widget.article?.source ?? widget.title;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          appBarTitle,
          style: theme.textTheme.titleSmall,
        ),
        actions: [
          if (_releaseUrl != null)
            IconButton(
              icon: const Icon(Icons.fact_check_outlined),
              tooltip: 'Release Status',
              onPressed: _openReleaseStatus,
            ),
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            onPressed: _openInBrowser,
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {},
          ),
        ],
      ),
      body: (_supportsWebView && _controller != null)
          ? _buildWebView()
          : _buildFallback(theme),
    );
  }

  Widget _buildWebView() {
    // Wrap in SafeArea so the WebView's PlatformView doesn't paint under
    // the Android system nav / gesture bar — Flutter's edge-to-edge
    // default lets the Scaffold body extend behind it otherwise. AppBar
    // handles the top inset already, so only bottom is needed here.
    return SafeArea(
      top: false,
      child: Stack(
        children: [
          Positioned.fill(
            child: WebViewWidget(controller: _controller!),
          ),
          if (_isLoading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Widget _buildFallback(ThemeData theme) {
    final article = widget.article;
    final publishedAt = article?.publishedAt ?? article?.createdAt;
    final summary = article?.summary;
    final tags = article?.tags ?? const <String>[];
    final sourceColor = article == null
        ? null
        : HSLColor.fromAHSL(
            1.0,
            (article.source.hashCode % 360).toDouble().abs(),
            0.6,
            0.4,
          ).toColor();
    final onSurface = theme.colorScheme.onSurface;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_blockedUnsafeScheme) ...[
            Card(
              elevation: 0,
              color: theme.colorScheme.errorContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This link uses an unsupported address and was not '
                        'opened in the reader for your safety.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: theme.dividerColor),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (article != null && sourceColor != null) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Chip(
                        label: Text(article.source),
                        backgroundColor: sourceColor.withValues(alpha: 0.15),
                        labelStyle: TextStyle(
                          color: sourceColor,
                          fontWeight: FontWeight.w600,
                        ),
                        side: BorderSide(
                          color: sourceColor.withValues(alpha: 0.4),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    widget.title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      height: 1.3,
                    ),
                  ),
                  if (publishedAt != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          _formatDate(publishedAt),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '·',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeago.format(publishedAt),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (summary != null && summary.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      summary,
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                    ),
                  ],
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: tags
                          .map(
                            (t) => Chip(
                              label: Text(t),
                              visualDensity: VisualDensity.compact,
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            icon: const Icon(Icons.open_in_browser),
            label: const Text('Open in Browser'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: _openInBrowser,
          ),
          if (_releaseUrl != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Open Release Status'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _openReleaseStatus,
            ),
          ],
        ],
      ),
    );
  }
}

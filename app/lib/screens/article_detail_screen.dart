import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/article.dart';

const List<String> _monthAbbr = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDate(DateTime d) {
  final day = d.day.toString().padLeft(2, '0');
  return '$day ${_monthAbbr[d.month - 1]} ${d.year}';
}

class ArticleDetailScreen extends StatefulWidget {
  final Article article;

  const ArticleDetailScreen({super.key, required this.article});

  @override
  State<ArticleDetailScreen> createState() => _ArticleDetailScreenState();
}

class _ArticleDetailScreenState extends State<ArticleDetailScreen> {
  bool _isLoading = true;
  WebViewController? _controller;

  bool get _supportsWebView =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    if (_supportsWebView) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (_) {
              if (!mounted) return;
              setState(() => _isLoading = false);
            },
          ),
        )
        ..loadRequest(Uri.parse(widget.article.url));
    }
  }

  Future<void> _openInBrowser() async {
    await launchUrl(
      Uri.parse(widget.article.url),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.article.source,
          style: theme.textTheme.titleSmall,
        ),
        actions: [
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
      body: _supportsWebView ? _buildWebView() : _buildFallback(theme),
    );
  }

  Widget _buildWebView() {
    return Stack(
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
    );
  }

  Widget _buildFallback(ThemeData theme) {
    final article = widget.article;
    final publishedAt = article.publishedAt ?? article.createdAt;
    final sourceColor = HSLColor.fromAHSL(
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
                  Text(
                    article.title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      height: 1.3,
                    ),
                  ),
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
                  if (article.summary != null &&
                      article.summary!.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      article.summary!,
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                    ),
                  ],
                  if (article.tags.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: article.tags
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
        ],
      ),
    );
  }
}

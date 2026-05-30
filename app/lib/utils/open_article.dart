import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/article.dart';
import '../screens/article_detail_screen.dart';

/// Single entry point for opening an article from any screen.
///
/// On web or when the caller is rendering the desktop layout, opens the
/// URL in the user's external browser via [url_launcher]. Otherwise
/// pushes the in-app [ArticleDetailScreen] which embeds a WebView on
/// Android / iOS (and falls back to a "open in browser" prompt on other
/// platforms it doesn't support).
///
/// [desktop] is a layout hint, not a platform check — the desktop
/// sidebars on home_screen pass `true` because a full-screen WebView
/// reader isn't the right UX in those contexts.
void openArticle(
  BuildContext context,
  Article article, {
  bool desktop = false,
}) {
  _openInReader(
    context,
    url: article.url,
    desktop: desktop,
    detailBuilder: () => ArticleDetailScreen(article: article),
  );
}

/// Opens an article identified only by its URL (+ optional title)
/// through the same routing as [openArticle]. Use this when the caller
/// doesn't have a full [Article], e.g. the AI digest "top stories" list
/// where each item is a bare `{title, url}` map rather than a row from
/// the `articles` table.
///
/// No-op when [url] is empty so callers don't have to guard a missing
/// digest URL themselves.
void openArticleUrl(
  BuildContext context, {
  required String url,
  String? title,
  bool desktop = false,
}) {
  if (url.isEmpty) return;
  _openInReader(
    context,
    url: url,
    desktop: desktop,
    detailBuilder: () => ArticleDetailScreen.url(url: url, title: title),
  );
}

void _openInReader(
  BuildContext context, {
  required String url,
  required bool desktop,
  required Widget Function() detailBuilder,
}) {
  if (kIsWeb || desktop) {
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } else {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => detailBuilder()),
    );
  }
}

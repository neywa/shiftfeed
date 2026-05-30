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

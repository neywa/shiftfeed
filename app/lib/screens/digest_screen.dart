import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../models/digest.dart';
import '../repositories/article_repository.dart';
import '../services/export_service.dart';
import '../theme/app_theme.dart';
import '../utils/open_article.dart';
import '../widgets/error_state.dart';
import '../widgets/offline_banner.dart';

const Color _kSecurityOrange = Color(0xFFFF6600);
const Color _kReleaseGreen = Color(0xFF00AA44);

class DigestScreen extends StatefulWidget {
  const DigestScreen({super.key});

  @override
  State<DigestScreen> createState() => _DigestScreenState();
}

class _DigestScreenState extends State<DigestScreen> {
  final ArticleRepository _repository = ArticleRepository();

  Digest? _digest;
  bool _isLoading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _loadDigest();
  }

  Future<void> _loadDigest() async {
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });
    try {
      final digest = await _repository.fetchLatestDigest();
      if (!mounted) return;
      setState(() {
        _digest = digest;
        _isLoading = false;
      });
    } on RepoException {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textSecondary = textSecondaryOf(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, size: 20, color: textSecondary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'AI BRIEFING',
          style: AppTextStyles.screenTitle,
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.ios_share,
              size: 20,
              color: textSecondary,
            ),
            tooltip: 'Share briefing',
            onPressed: (_isLoading || _digest == null)
                ? null
                : () => ExportService.instance.shareDigest(_digest!.summary),
          ),
        ],
        backgroundColor: bgOf(context),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: kRed),
        ),
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: kRed),
      );
    }

    if (_loadFailed && _digest == null) {
      return ErrorState(
        title: "Couldn't load briefing",
        body: 'Check your connection and try again.',
        onRetry: _loadDigest,
      );
    }

    if (_digest == null) {
      final textMuted = textMutedOf(context);
      final textSecondary = textSecondaryOf(context);
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.article_outlined, size: 48, color: textMuted),
            const SizedBox(height: 16),
            Text(
              'No digest available yet',
              style: TextStyle(color: textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              'Check back after the next scrape run',
              style: AppTextStyles.caption.copyWith(color: textMuted),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context, _digest!),
          _buildSummary(context, _digest!),
          _buildTopArticles(context, _digest!),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Digest digest) {
    final surface = surfaceOf(context);
    final border = borderOf(context);
    final textMuted = textMutedOf(context);
    final textSecondary = textSecondaryOf(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surface,
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: kRed,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'LIVE BRIEFING',
                style: TextStyle(
                  fontSize: 11,
                  color: kRed,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                timeago.format(digest.generatedAt),
                style: AppTextStyles.caption.copyWith(color: textMuted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            DateFormat('EEEE, MMMM d yyyy').format(digest.digestDate),
            style: TextStyle(fontSize: 13, color: textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(BuildContext context, Digest digest) {
    final lines = digest.summary.split('\n');
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _renderLine(context, line),
            ),
        ],
      ),
    );
  }

  Widget _renderLine(BuildContext context, String raw) {
    final line = raw.trimRight();
    final textPrimary = textPrimaryOf(context);
    final textSecondary = textSecondaryOf(context);

    if (line.trim().isEmpty) {
      return const SizedBox(height: 12);
    }

    if (line.startsWith('🔴')) {
      return Text(
        line,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
      );
    }

    final trimmed = line.trim();
    if (trimmed.startsWith('**') &&
        trimmed.endsWith('**') &&
        trimmed.length > 4) {
      final inner = trimmed.substring(2, trimmed.length - 2);
      return Text(
        inner,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: kRed,
          letterSpacing: 1,
        ),
      );
    }

    final bulletMatch = RegExp(r'^\s*([•\-])\s+(.*)$').firstMatch(line);
    if (bulletMatch != null) {
      final text = bulletMatch.group(2) ?? '';
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                color: kRed,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: textSecondary,
                height: 1.6,
              ),
            ),
          ),
        ],
      );
    }

    if (line.startsWith('⚠️')) {
      return Text(
        line,
        style: const TextStyle(
          fontSize: 13,
          color: _kSecurityOrange,
          height: 1.6,
        ),
      );
    }

    if (line.startsWith('🚀')) {
      return Text(
        line,
        style: const TextStyle(
          fontSize: 13,
          color: _kReleaseGreen,
          height: 1.6,
        ),
      );
    }

    return Text(
      line,
      style: TextStyle(
        fontSize: 13,
        color: textSecondary,
        height: 1.6,
      ),
    );
  }

  Widget _buildTopArticles(BuildContext context, Digest digest) {
    if (digest.topArticles.isEmpty) return const SizedBox.shrink();

    final border = borderOf(context);
    final textMuted = textMutedOf(context);
    final textPrimary = textPrimaryOf(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TOP STORIES',
            style: AppTextStyles.sectionLabel.copyWith(color: textMuted),
          ),
          const SizedBox(height: 16),
          for (final article in digest.topArticles) ...[
            InkWell(
              onTap: () {
                final url = article['url'];
                if (url == null || url.isEmpty) return;
                openArticleUrl(
                  context,
                  url: url,
                  title: article['title'],
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        article['title'] ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: textPrimary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.open_in_new,
                      size: 14,
                      color: textMuted,
                    ),
                  ],
                ),
              ),
            ),
            Divider(color: border, height: 1),
          ],
        ],
      ),
    );
  }
}

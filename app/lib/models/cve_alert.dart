class CveAlert {
  final String cveId;
  final String title;
  final String articleUrl;

  /// When the scraper first saw this CVE (`cve_alerts.detected_at`) — NOT a
  /// publish date. The CVE's real publication date is never stored on this
  /// table; it only exists as `articles.published_at`.
  final DateTime? detectedAt;

  const CveAlert({
    required this.cveId,
    required this.title,
    required this.articleUrl,
    this.detectedAt,
  });

  /// Parses a `cve_alerts` row.
  ///
  /// The timestamp column is `detected_at`. It is deliberately NOT
  /// `created_at`: that column does not exist on this table, and reading it
  /// silently yielded null for every row — which flattened the sort in
  /// `ArticleRepository.fetchCveAlerts` and left the sidebar showing
  /// arbitrary CVEs. `articles` is the table with a real `created_at`.
  factory CveAlert.fromJson(Map<String, dynamic> json) {
    final detectedAtStr = json['detected_at'] as String?;
    return CveAlert(
      cveId: json['cve_id'] as String,
      title: json['title'] as String,
      articleUrl: json['article_url'] as String,
      detectedAt: detectedAtStr != null
          ? DateTime.parse(detectedAtStr).toLocal()
          : null,
    );
  }
}

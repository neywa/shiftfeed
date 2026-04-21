const _defaultFavicon = 'https://icons.duckduckgo.com/ip3/redhat.com.ico';

const _faviconMap = {
  'Red Hat Blog': 'https://icons.duckduckgo.com/ip3/redhat.com.ico',
  'Red Hat Developer':
      'https://icons.duckduckgo.com/ip3/developers.redhat.com.ico',
  'Kubernetes Blog': 'https://icons.duckduckgo.com/ip3/kubernetes.io.ico',
  'CNCF Blog': 'https://icons.duckduckgo.com/ip3/cncf.io.ico',
  'Hacker News':
      'https://icons.duckduckgo.com/ip3/news.ycombinator.com.ico',
  'Reddit r/openshift': 'https://icons.duckduckgo.com/ip3/reddit.com.ico',
  'GitHub Releases': 'https://icons.duckduckgo.com/ip3/github.com.ico',
};

String faviconUrl(String source) => _faviconMap[source] ?? _defaultFavicon;

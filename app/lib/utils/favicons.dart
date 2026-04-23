const _defaultFavicon = 'assets/favicons/redhat.png';

const _faviconMap = {
  'Red Hat Blog': 'assets/favicons/redhat.png',
  'Red Hat Developer': 'assets/favicons/developers-redhat.png',
  'Red Hat Security': 'assets/favicons/redhat.png',
  'Kubernetes Blog': 'assets/favicons/kubernetes.png',
  'CNCF Blog': 'assets/favicons/cncf.png',
  'Hacker News': 'assets/favicons/hackernews.png',
  'Reddit r/openshift': 'assets/favicons/reddit.png',
  'GitHub Releases': 'assets/favicons/github.png',
  'HackerNoon': 'assets/favicons/hackernoon.png',
  'Istio Blog': 'assets/favicons/istio.png',
};

String faviconAsset(String source) => _faviconMap[source] ?? _defaultFavicon;

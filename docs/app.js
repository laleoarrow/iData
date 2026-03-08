const revealNodes = document.querySelectorAll('.reveal');

const revealObserver = new IntersectionObserver(
  (entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add('is-visible');
        revealObserver.unobserve(entry.target);
      }
    });
  },
  { threshold: 0.14, rootMargin: '0px 0px -8% 0px' }
);

revealNodes.forEach((node, index) => {
  node.dataset.delay = String(index % 4);
  revealObserver.observe(node);
});

const releaseBadge = document.getElementById('release-badge');
const releasePublished = document.getElementById('release-published');
const releaseVersion = document.getElementById('release-version');
const releaseDate = document.getElementById('release-date');
const releaseAsset = document.getElementById('release-asset');
const latestDownloadLink = document.getElementById('download-latest');
const releaseNotesLink = document.getElementById('view-release-notes');

const formatDate = (value) => {
  if (!value) {
    return 'Not available';
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return 'Not available';
  }

  return new Intl.DateTimeFormat('en', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  }).format(date);
};

const findPreferredAsset = (assets) => {
  if (!Array.isArray(assets) || assets.length === 0) {
    return null;
  }

  return (
    assets.find((asset) => asset.name?.endsWith('.dmg')) ||
    assets.find((asset) => asset.name?.endsWith('.zip')) ||
    assets[0]
  );
};

const applyReleaseData = (release) => {
  if (!release) {
    throw new Error('Missing release payload');
  }

  const preferredAsset = findPreferredAsset(release.assets);
  const publishedLabel = formatDate(release.published_at);
  const versionLabel = release.tag_name || release.name || 'Latest release';
  const assetLabel = preferredAsset ? preferredAsset.name : 'See release assets on GitHub';
  const assetHref = preferredAsset?.browser_download_url || release.html_url;

  releaseBadge.textContent = preferredAsset?.name?.endsWith('.dmg')
    ? `${versionLabel} · DMG ready`
    : versionLabel;
  releasePublished.textContent = `Published ${publishedLabel}`;
  releaseVersion.textContent = versionLabel;
  releaseDate.textContent = publishedLabel;
  releaseAsset.textContent = assetLabel;

  if (release.html_url) {
    releaseNotesLink.href = release.html_url;
  }

  if (assetHref) {
    latestDownloadLink.href = assetHref;
  }
};

const applyReleaseFallback = () => {
  releaseBadge.textContent = 'Latest release';
  releasePublished.textContent = 'GitHub release feed';
  releaseVersion.textContent = 'Latest release';
  releaseDate.textContent = 'Check GitHub releases';
  releaseAsset.textContent = 'Open GitHub to view available assets';
};

fetch('https://api.github.com/repos/laleoarrow/iData/releases/latest')
  .then((response) => (response.ok ? response.json() : null))
  .then((release) => {
    if (!release) {
      applyReleaseFallback();
      return;
    }

    applyReleaseData(release);
  })
  .catch(() => {
    applyReleaseFallback();
  });

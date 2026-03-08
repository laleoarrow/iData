const revealObserver = new IntersectionObserver(
  (entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add('is-visible');
      }
    });
  },
  { threshold: 0.16 }
);

document.querySelectorAll('.reveal').forEach((node) => revealObserver.observe(node));

const releaseBadge = document.getElementById('release-badge');
if (releaseBadge) {
  fetch('https://api.github.com/repos/laleoarrow/iData/releases/latest')
    .then((response) => response.ok ? response.json() : null)
    .then((release) => {
      if (!release) return;
      const assetNames = Array.isArray(release.assets) ? release.assets.map((asset) => asset.name) : [];
      const hasDMG = assetNames.find((name) => name.endsWith('.dmg'));
      releaseBadge.textContent = hasDMG ? `${release.tag_name} · DMG available` : release.tag_name;
    })
    .catch(() => {
      releaseBadge.textContent = 'Latest release';
    });
}

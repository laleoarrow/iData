const releaseVersionNodes = document.querySelectorAll('[data-release-version]');
const releaseDateNodes = document.querySelectorAll('[data-release-date]');
const latestDownloadLinks = document.querySelectorAll('[data-download-latest]');
const releaseNotesLinks = [
  document.getElementById('view-release-notes'),
  document.getElementById('footer-release-notes'),
].filter(Boolean);

const formatDate = (value) => {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return null;
  }

  return new Intl.DateTimeFormat('en', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  }).format(date);
};

const preferredReleaseAsset = (assets) => {
  if (!Array.isArray(assets)) {
    return null;
  }

  return (
    assets.find((asset) => asset.name?.endsWith('.dmg')) ||
    assets.find((asset) => asset.name?.endsWith('.zip')) ||
    null
  );
};

const applyRelease = (release) => {
  const version = release.tag_name || release.name;
  const publishedDate = formatDate(release.published_at);
  const asset = preferredReleaseAsset(release.assets);

  if (version) {
    releaseVersionNodes.forEach((node) => {
      node.textContent = version;
    });
  }

  if (publishedDate) {
    releaseDateNodes.forEach((node) => {
      node.textContent = publishedDate;
      if (node.tagName === 'TIME') {
        node.dateTime = release.published_at;
      }
    });
  }

  if (asset?.browser_download_url) {
    latestDownloadLinks.forEach((link) => {
      link.href = asset.browser_download_url;
    });
  }

  if (release.html_url) {
    releaseNotesLinks.forEach((link) => {
      link.href = release.html_url;
    });
  }
};

fetch('https://api.github.com/repos/laleoarrow/iData/releases/latest')
  .then((response) => (response.ok ? response.json() : null))
  .then((release) => {
    if (release) {
      applyRelease(release);
    }
  })
  .catch(() => {
    // The page ships with a current static release fallback.
  });

const copyToast = document.querySelector('.copy-toast');
let toastTimer;

const showCopyToast = (message) => {
  if (!copyToast) {
    return;
  }

  window.clearTimeout(toastTimer);
  copyToast.textContent = message;
  copyToast.classList.add('is-visible');
  toastTimer = window.setTimeout(() => {
    copyToast.classList.remove('is-visible');
  }, 1800);
};

const writeClipboard = async (text) => {
  if (navigator.clipboard?.writeText) {
    await navigator.clipboard.writeText(text);
    return;
  }

  const textarea = document.createElement('textarea');
  textarea.value = text;
  textarea.setAttribute('readonly', '');
  textarea.style.position = 'fixed';
  textarea.style.opacity = '0';
  document.body.appendChild(textarea);
  textarea.select();
  document.execCommand('copy');
  textarea.remove();
};

document.querySelectorAll('[data-copy-text]').forEach((button) => {
  button.addEventListener('click', async () => {
    const text = button.dataset.copyText;
    const icon = button.querySelector('i');

    try {
      await writeClipboard(text);
      button.classList.add('is-copied');
      button.setAttribute('aria-label', 'Homebrew command copied');
      if (icon) {
        icon.className = 'ph ph-check';
      }
      showCopyToast('Homebrew command copied');

      window.setTimeout(() => {
        button.classList.remove('is-copied');
        button.setAttribute('aria-label', 'Copy Homebrew command');
        if (icon) {
          icon.className = 'ph ph-copy';
        }
      }, 1800);
    } catch {
      showCopyToast('Copy failed — select the command manually');
    }
  });
});

const copyrightYear = document.getElementById('copyright-year');
if (copyrightYear) {
  copyrightYear.textContent = String(new Date().getFullYear());
}

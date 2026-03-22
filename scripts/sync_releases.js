const fs = require("node:fs");
const path = require("node:path");

const RELEASES_API_URL = "https://api.github.com/repos/typst/typst/releases";
const RELEASES_FILE = path.join(__dirname, "..", "public", "releases.json");

function trimAsset(asset) {
  if (!asset.name || !asset.browser_download_url) {
    return null;
  }

  return {
    name: asset.name,
    url: asset.browser_download_url,
    digest: asset.digest ?? null,
  };
}

function trimRelease(release) {
  return {
    tag_name: release.tag_name || "",
    published_at: release.published_at || "",
    draft: Boolean(release.draft),
    prerelease: Boolean(release.prerelease),
    assets: (release.assets || []).map(trimAsset).filter(Boolean),
  };
}

function loadJsonFile(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

async function fetchReleases() {
  const headers = {
    Accept: "application/vnd.github+json",
    "User-Agent": "vfox-typst-release-sync",
    "X-GitHub-Api-Version": "2022-11-28",
  };

  if (process.env.GITHUB_TOKEN) {
    headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
  }

  const response = await fetch(RELEASES_API_URL, {
    headers,
  });

  if (!response.ok) {
    throw new Error(
      `GitHub API request failed: ${response.status} ${response.statusText}`,
    );
  }

  const releases = await response.json();
  return releases.map(trimRelease);
}

function sortReleases(releases) {
  return releases.slice().sort((a, b) => {
    const aValue = a.published_at;
    const bValue = b.published_at;
    return bValue.localeCompare(aValue);
  });
}

function mergeMissingReleases(existingReleases, fetchedReleases) {
  const existingTags = new Set(
    existingReleases.map((release) => release.tag_name),
  );
  const missingReleases = fetchedReleases.filter(
    (release) => !existingTags.has(release.tag_name),
  );

  return {
    mergedReleases: missingReleases.concat(existingReleases),
    missingReleases,
  };
}

function writeReleases(filePath, releases) {
  fs.writeFileSync(filePath, `${JSON.stringify(releases, null, 2)}\n`, "utf8");
}

async function main() {
  try {
    if (!fs.existsSync(RELEASES_FILE)) {
      throw new Error(`Releases file not found: ${RELEASES_FILE}`);
    }

    const existingReleases = loadJsonFile(RELEASES_FILE);
    const fetchedReleases = await fetchReleases();

    const { mergedReleases, missingReleases } = mergeMissingReleases(
      existingReleases,
      fetchedReleases,
    );

    if (missingReleases.length === 0) {
      console.log("No new releases found.");
      return;
    }

    const sortedMergedReleases = sortReleases(mergedReleases);
    writeReleases(RELEASES_FILE, sortedMergedReleases);
    
    console.log(
      `Added ${missingReleases.length} release(s): ${missingReleases.map((release) => release.tag_name).join(", ")}`,
    );
  } catch (error) {
    console.error(error.message || String(error));
    process.exit(1);
  }
}

main();

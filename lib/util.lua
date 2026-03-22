local http = require("http")
local json = require("json")
require("constants")

local util = {}

local function normalizeVersion(tagName)
    return string.gsub(tagName or "", "^v", "")
end

local function parseSha256Digest(digest)
    if digest == nil then
        return nil
    end
    return string.match(digest, "^sha256:(.+)$")
end

local function getPlatformCandidates()
    local osType = RUNTIME.osType
    local archType = RUNTIME.archType

    if osType == "darwin" then
        if archType == "arm64" then
            return {
                "typst%-aarch64%-apple%-darwin",
            }
        elseif archType == "amd64" then
            return {
                "typst%-x86_64%-apple%-darwin",
            }
        end
    elseif osType == "windows" then
        if archType == "arm64" then
            return {
                "typst%-aarch64%-pc%-windows%-msvc",
            }
        elseif archType == "amd64" then
            return {
                "typst%-x86_64%-pc%-windows%-msvc",
            }
        end
    elseif osType == "linux" then
        if archType == "amd64" then
            return {
                "typst%-x86_64%-unknown%-linux%-musl",
                "typst%-x86_64%-unknown%-linux%-gnu",
            }
        elseif archType == "arm64" then
            return {
                "typst%-aarch64%-unknown%-linux%-musl",
                "typst%-aarch64%-unknown%-linux%-gnu",
            }
        elseif archType == "386" then
            return {
                "typst%-i686%-unknown%-linux%-musl",
                "typst%-i686%-unknown%-linux%-gnu",
            }
        elseif archType == "arm" then
            return {
                "typst%-armv7%-unknown%-linux%-musleabi",
                "typst%-armv7%-unknown%-linux%-gnueabi",
            }
        end
    end

    return {}
end

local function findMatchingAsset(assets)
    local candidates = getPlatformCandidates()
    if #candidates == 0 then
        return nil
    end

    for _, candidate in ipairs(candidates) do
        for _, asset in ipairs(assets or {}) do
            local name = asset.name or ""
            if string.match(name, "^" .. candidate .. "[.]") then
                return asset
            end
        end
    end

    return nil
end

local function getReleaseNote(release)
    if release.draft then
        return "draft"
    end
    if release.prerelease then
        return "pre-release"
    end
    return "stable"
end

function util:getReleases()
    local resp, err = http.get({
        url = TYPST_RELEASES_URL
    })
    if err ~= nil or resp.status_code ~= 200 then
        error("parsing release info failed." .. (err or ""))
    end

    local body = json.decode(resp.body)
    table.sort(body, function(a, b)
        return (a.published_at or "") > (b.published_at or "")
    end)

    local result = {}
    for _, release in ipairs(body) do
        local asset = findMatchingAsset(release.assets)
        if asset ~= nil then
            table.insert(result, {
                version = normalizeVersion(release.tag_name),
                url = asset.url,
                note = getReleaseNote(release),
                sha256 = parseSha256Digest(asset.digest),
            })
        end
    end

    return result
end

function util:findRelease(version)
    local releases = self:getReleases()
    if version == "latest" then
        return releases[1] or {}
    end

    local normalizedVersion = normalizeVersion(version)
    for _, release in ipairs(releases) do
        if release.version == normalizedVersion then
            return release
        end
    end

    return {}
end

return util
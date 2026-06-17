#!/usr/bin/env bash
# Locks version consistency so CI fails on drift.
# Single source of truth: ./VERSION
#
# Enforced invariants:
#   1. VERSION exists and is valid semver (X.Y.Z).
#   2. install.sh / package_app.sh / build_and_run.sh DERIVE the version
#      (read ./VERSION or resolve the latest release) and never hardcode it.
#   3. The Homebrew cask is valid semver, carries a real sha256, and is not
#      ahead of VERSION (it tracks the latest published release, so <= VERSION).
#   4. When git tags are available (local), the cask must equal the latest tag.
#      CI checkouts are usually shallow without tags, so this check self-skips.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail=0
err() { echo "  FAIL: $*" >&2; fail=1; }
ok() { echo "  ok:   $*"; }

semver_re='^[0-9]+\.[0-9]+\.[0-9]+$'

# 1. VERSION is the single source of truth.
if [[ ! -f VERSION ]]; then
  echo "FAIL: VERSION file is missing (it is the single source of truth)." >&2
  exit 1
fi
VERSION="$(tr -d '[:space:]' <VERSION)"
echo "Canonical VERSION = $VERSION"
if [[ "$VERSION" =~ $semver_re ]]; then
  ok "VERSION is valid semver"
else
  err "VERSION '$VERSION' is not X.Y.Z"
fi

# 2. Build/install scripts must derive the version, never hardcode it.
#    MIN_SYSTEM_VERSION (e.g. 13.0) is a macOS version and is allowed.
for s in script/install.sh script/package_app.sh script/build_and_run.sh; do
  if grep -qE 'VERSION="\$\{[^}]*:-[0-9]+\.[0-9]+\.[0-9]+' "$s"; then
    err "$s hardcodes an app version in its VERSION assignment; read ./VERSION or resolve the latest release instead."
  else
    ok "$s does not hardcode the app version"
  fi
done

# 3. Homebrew cask tracks a published release.
CASK="Casks/cmd-ime.rb"
CASK_VERSION=""
if [[ -f "$CASK" ]]; then
  CASK_VERSION="$(sed -nE 's/^[[:space:]]*version[[:space:]]+"([^"]+)".*/\1/p' "$CASK" | head -1)"
  echo "Cask version      = $CASK_VERSION (tracks the latest published release)"
  if [[ "$CASK_VERSION" =~ $semver_re ]]; then
    ok "cask version is valid semver"
  else
    err "cask version '$CASK_VERSION' is not X.Y.Z"
  fi
  if [[ "$CASK_VERSION" =~ $semver_re && "$VERSION" =~ $semver_re ]]; then
    highest="$(printf '%s\n%s\n' "$VERSION" "$CASK_VERSION" | sort -V | tail -1)"
    if [[ "$CASK_VERSION" != "$VERSION" && "$highest" == "$CASK_VERSION" ]]; then
      err "cask version ($CASK_VERSION) is AHEAD of VERSION ($VERSION); the cask must track a release <= VERSION."
    else
      ok "cask version <= VERSION"
    fi
  fi
  if [[ -n "$CASK_VERSION" && "$CASK_VERSION" != "$VERSION" ]]; then
    echo "  note: cask ($CASK_VERSION) != VERSION ($VERSION) — expected between releases; bump the cask when you publish $VERSION."
  fi
  if grep -qE 'sha256 "[0-9a-f]{64}"' "$CASK"; then
    ok "cask sha256 is a 64-char hex digest"
  else
    err "cask sha256 is missing or not a 64-char hex digest."
  fi
else
  err "$CASK not found"
fi

# 4. Local-only: cask must equal the latest git tag (skipped without tags, e.g. shallow CI).
if git rev-parse --git-dir >/dev/null 2>&1; then
  LATEST_TAG="$(git tag --list 'v*' | sed 's/^v//' | sort -V | tail -1 || true)"
  if [[ -n "${LATEST_TAG:-}" && -n "$CASK_VERSION" ]]; then
    echo "Latest git tag    = v$LATEST_TAG"
    if [[ "$CASK_VERSION" == "$LATEST_TAG" ]]; then
      ok "cask version matches latest git tag"
    else
      err "cask version ($CASK_VERSION) != latest git tag (v$LATEST_TAG); point the cask at the most recent release."
    fi
  else
    echo "  note: no git tags available; skipping cask == latest-tag check."
  fi
fi

if [[ "$fail" -ne 0 ]]; then
  echo "Version consistency check FAILED." >&2
  exit 1
fi
echo "Version consistency check passed."

#!/usr/bin/env bash
#
# fetch-engines.sh — pin and check out the emulation engines at known-good SHAs.
#
# Run on macOS (needs git only). Produces:
#   engines/flycast/   Flycast        (Dreamcast)   GPL-2.0-or-later
#   engines/Play-/     Play!          (PS2, eval)   GPL-3.0  — not integrated yet
#   engines/pcsx2/     PCSX2          (PS2, eval)   LGPL-3.0 — not integrated yet
#
# Play! and PCSX2 are fetched for continued evaluation only. Phase 1 integrates
# nothing but Flycast. See docs/PHASE1-FEASIBILITY.md section 7.
#
# WHY PINNED SHAs: Flycast's iOS support was explicitly DROPPED upstream
# ("Due to persistent harassment from an iOS user, support for this platform has
# been dropped." — README.md). We cannot rely on master staying buildable for
# iOS, so we pin and carry patches under patches/.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINES="$ROOT/engines"
mkdir -p "$ENGINES"

# --- Pins ---------------------------------------------------------------------
# Verified against upstream default branches on 2026-10-10 (see docs/PINS.md).
FLYCAST_REPO="https://github.com/flyinghead/flycast.git"
FLYCAST_SHA="ed953fcbfdd1b8a7521d2966b13cc700c7e2d233"

PLAY_REPO="https://github.com/jpd002/Play-.git"
PLAY_SHA="83700b2c31e593bc94e845b4b31b797be84dda59"

PCSX2_REPO="https://github.com/PCSX2/pcsx2.git"
PCSX2_SHA="6bdd913a67ae701101780ddc4d693acfb892fe2f"

checkout() {
  local name="$1" repo="$2" sha="$3" recursive="${4:-no}"
  local dir="$ENGINES/$name"

  if [ ! -d "$dir/.git" ]; then
    echo "==> cloning $name"
    git clone --filter=blob:none "$repo" "$dir"
  fi

  echo "==> $name -> $sha"
  git -C "$dir" fetch --depth 1 origin "$sha" || git -C "$dir" fetch origin
  git -C "$dir" checkout --detach "$sha"

  if [ "$recursive" = "yes" ]; then
    # Flycast has 23 submodules (glslang, SDL, libchdr, Vulkan-Headers, ...).
    # A build will fail confusingly if these are missing.
    echo "==> $name: initialising submodules (this takes a while)"
    git -C "$dir" submodule update --init --recursive --depth 1
  fi

  echo "    $name at $(git -C "$dir" rev-parse --short HEAD)"
}

# Flycast is the only engine Phase 1 actually builds.
checkout flycast "$FLYCAST_REPO" "$FLYCAST_SHA" yes

# Evaluation-only clones; submodules NOT fetched (they are huge and unused).
checkout Play-   "$PLAY_REPO"   "$PLAY_SHA"   no
checkout pcsx2   "$PCSX2_REPO"  "$PCSX2_SHA"  no

# --- Apply Deez Retro patches -------------------------------------------------
if [ -d "$ROOT/patches" ]; then
  shopt -s nullglob
  for p in "$ROOT/patches"/*.patch; do
    echo "==> applying $(basename "$p")"
    git -C "$ENGINES/flycast" apply --3way "$p" || {
      echo "!!! patch failed: $p" >&2
      exit 1
    }
  done
fi

echo
echo "Done. Next: scripts/build-flycast-ios.sh"

# Upstream pins

Every engine is pinned to an exact commit. Nothing tracks a moving branch.

Inspected and recorded on **2026-10-10** by shallow-cloning each repository's
default branch and reading the files cited below.

| Engine | Role | Repository | Commit | Commit date |
|---|---|---|---|---|
| Flycast | Sega Dreamcast | `flyinghead/flycast` | `ed953fcbfdd1b8a7521d2966b13cc700c7e2d233` | 2026-10-10 |
| Play! | Sony PlayStation 2 (evaluation) | `jpd002/Play-` | `83700b2c31e593bc94e845b4b31b797be84dda59` | 2026-09-03 |
| PCSX2 | Sony PlayStation 2 (evaluation) | `PCSX2/pcsx2` | `6bdd913a67ae701101780ddc4d693acfb892fe2f` | 2026-10-10 |

Upstream commit subjects at those SHAs, for traceability:

- Flycast — `Fetch translations & Recreate libretro_core_options_intl.h`
- Play! — `Merge pull request #1614 from jpd002/dependabot/github_actions/actions/setup-java-6`
- PCSX2 — `GS/HW: Try to use barriers first if depth buffer isn't safe to read on shuffles.`

## Why pin instead of track

Flycast is the one engine this project depends on, and its iOS support is
**not maintained**. `README.md` currently reads:

> ### iOS
> Due to persistent harassment from an iOS user, support for this platform has been dropped.

The iOS code path still exists and still compiles in principle, but nothing
obliges upstream to keep it working. There is also no iOS job in
`.github/workflows/` (present workflows: `android.yml`, `bsd.yml`, `c-cpp.yml`,
`switch.yml`, `uwp.yml`, `crowdin_*.yml`). A pinned SHA plus patches under
`patches/` is the only defensible arrangement.

## Flycast submodules

Flycast uses 23 git submodules (`.gitmodules`). The ones that matter for an
iPadOS build:

| Submodule | Needed on iOS? | Note |
|---|---|---|
| `core/deps/glslang` | No | Vulkan only; iOS forces `USE_VULKAN=OFF` |
| `core/deps/Vulkan-Headers` | No | Vulkan only |
| `core/deps/VulkanMemoryAllocator` | No | Vulkan only |
| `core/deps/SDL` | No | `USE_HOST_SDL` defaults OFF on Apple |
| `core/deps/libchdr` | Yes | CHD disc images (`USE_HOST_LIBCHDR` OFF) |
| `core/deps/libzip` | Yes | via `USE_HOST_LIBZIP=ON`, so system libzip |
| `core/deps/rcheevos` | Yes | compiled unconditionally when not LIBRETRO |
| `core/deps/tinygettext` | Yes | i18n (`intl/`) |
| `core/deps/freetype` | Yes | on-screen text |
| `core/deps/xxHash`, `core/deps/glm` | Yes | added via `add_subdirectory` unconditionally |
| `core/deps/breakpad` | No | `USE_BREAKPAD=NO` |
| `core/deps/luabridge`, `core/deps/asio`, `core/deps/websocketpp` | Yes | `USE_LUA=ON` default |

`git submodule update --init --recursive --depth 1` is required before any build;
a missing `core/deps/glslang/CMakeLists.txt` is the check the upstream bootstrap
script itself performs (`shell/apple/generate_xcode_project.command:178`).

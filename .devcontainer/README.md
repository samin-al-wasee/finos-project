# Dev containers

Two configurations, both built from `Dockerfile` via separate targets so the
Flutter install is defined once.

| Configuration | Use it for | Disk |
| --- | --- | --- |
| **FinOS (analysis & tests)** — the default | `flutter analyze`, `flutter test`, `dart format`, `dart run build_runner build` | ~2.1 GB |
| **FinOS (Android toolchain)** — `android/` | everything above plus `flutter build apk` | ~5.7 GB |

Sizes are filesystem usage measured inside each image. They share the Flutter
layers, so having both costs about 5.7 GB rather than the sum. Note that
`docker images` reports notably smaller numbers on Docker Desktop because it
shows compressed layer sizes.

Most of the light image is the Flutter SDK and its precached artifacts; the C
toolchain adds roughly 250 MB. In the Android image the NDK alone is 2.2 GB.

VS Code offers both when you run **Dev Containers: Reopen in Container**. Pick the
light one unless you specifically need to build an APK.

## What these containers cannot do

**iOS — anything.** iOS builds need macOS and Xcode, which cannot run in a Linux
container. `flutter build ios`, `pod install`, and the simulator all stay on a
Mac. Since FinOS targets iOS as a first-class platform
(`docs/REQUIREMENTS.md` NFR-UI-01), a dev container is a supplement to a Mac
checkout, not a replacement for one.

**Run an Android emulator.** The emulator needs nested virtualisation (KVM),
which is unavailable in a typical container. Use a physical device or an emulator
on the host.

**Verify the share sheet or file picker.** The backup export/import flows go
through `share_plus` and `file_selector`, which need a real Android or iOS
runtime. They are covered by tests only through the `BackupFileStore` fake — see
`docs/ARCHITECTURE.md` §26.

## Versions and why they are pinned

| Thing | Value | Where it comes from |
| --- | --- | --- |
| Flutter | `3.41.6` | matches `.metadata`, and the build **fails** if the tag's revision differs from the one recorded there |
| Java | 17 | `sourceCompatibility` in `android/app/build.gradle.kts` |
| compileSdk / targetSdk | 36 | this Flutter version's `FlutterExtension` defaults |
| minSdk | 24 | same |
| NDK | `28.2.13676358` | same — and genuinely required, see below |

When you move the Flutter pin, move `FLUTTER_REVISION` with it and re-check the
Android levels against `FlutterExtension.kt` in the new SDK.

## Two non-obvious requirements

**A C toolchain, even for `flutter test`.** `package:sqlite3` 3.x compiles SQLite
from C source through a Dart build hook (`native_toolchain_c`), so `clang` is
installed in *both* images. Without it `flutter test` fails before running a
single test — which matters, because every database test builds an in-memory
SQLite instance.

**The Android NDK.** Same reason, one layer down: that build hook compiles SQLite
for each Android ABI using the NDK's clang. It is not optional for
`flutter build apk`, and it is most of why the Android image is large.

## Caches

Named volumes, not bind mounts, so a container rebuild does not discard them:

- `finos-pub-cache` → `~/.pub-cache`
- `finos-dart-tool` → `.dart_tool` (build_runner's output cache)
- `finos-gradle-cache` → `~/.gradle` (Android configuration only)

Keeping `.dart_tool` in a volume also stops the container's generated files from
fighting with the host's when both are used against the same checkout.

To start clean:

```bash
docker volume rm finos-pub-cache finos-dart-tool finos-gradle-cache
```

## Building outside VS Code

```bash
# Light image
docker build --target lite -t finos-dev:lite -f .devcontainer/Dockerfile .devcontainer

# Run the suite against the working tree
docker run --rm -v "$PWD":/work -w /work finos-dev:lite \
  bash -lc 'git config --global --add safe.directory /work && flutter pub get && flutter test'
```

This is exactly how the light image was verified: `flutter analyze` reports no
issues and the full suite passes inside it. Expect the container run to be slower
than the host — roughly 25 s to analyse and 23 s to run the tests on Apple
Silicon, against about 3 s and 19 s natively.

## Host architecture — read this before using the Android image

The images build for the host architecture. On an Apple Silicon Mac that means
`linux/arm64`, where the **light image works normally** — verified.

**The Android image builds on arm64 but cannot build an APK there**, and it fails
in a way designed to mislead you. `flutter doctor` reports:

```text
[✓] Android toolchain - develop for Android devices (Android SDK version 36.0.0)
```

because it never checks whether the SDK's binaries can actually execute. They
cannot: Google ships the Linux NDK and `adb` as x86-64 only, so running the NDK's
clang on an arm64 container gives

```text
rosetta error: failed to open elf at /lib64/ld-linux-x86-64.so.2
Trace/breakpoint trap
```

Since `package:sqlite3` compiles SQLite through that clang for every ABI, an APK
build dies there — after several minutes of Gradle work, with an error that looks
nothing like an architecture problem.

On an **x86-64 host** (most CI runners, Intel Macs, Linux desktops) the Android
image works as intended.

On **Apple Silicon**, build it for amd64 and accept the emulation penalty:

```bash
docker build --platform linux/amd64 --target android \
  -t finos-dev:android -f .devcontainer/Dockerfile .devcontainer
```

or uncomment the `runArgs` line in `android/devcontainer.json`. That path is the
standard workaround but has not been verified here — an emulated build of this
image takes far longer than a native one.

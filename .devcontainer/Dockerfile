# syntax=docker/dockerfile:1
#
# Two images from one file, so the Flutter install is defined once:
#
#   --target lite     analysis, tests, codegen        (~1.5 GB)
#   --target android  everything above plus APK builds (~9 GB)
#
# iOS is absent from both on purpose: it needs macOS and Xcode and cannot run in
# a Linux container at all. iOS work stays on a Mac.

# ---------------------------------------------------------------------------
# Flutter SDK, pinned to the exact revision in .metadata
# ---------------------------------------------------------------------------
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04 AS flutter-base

# Pinned by tag for a shallow clone, then verified against the revision that
# .metadata records. If the two ever disagree the build fails loudly rather than
# silently handing you a different SDK than the repo was written against.
ARG FLUTTER_VERSION=3.41.6
ARG FLUTTER_REVISION=db50e20168db8fee486b9abf32fc912de3bc5b6a

ENV FLUTTER_HOME=/opt/flutter
ENV PATH=${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin:${PATH}

# Neither tool should phone home from a dev container.
ENV FLUTTER_SUPPRESS_ANALYTICS=true
ENV DART_CLI_DISABLE_ANALYTICS=true

RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get install -y --no-install-recommends \
        curl file git unzip xz-utils zip \
        # package:sqlite3 compiles SQLite from C source through a Dart build
        # hook (native_toolchain_c), so a C toolchain is not optional here —
        # without clang, `flutter test` cannot even start.
        clang libc6-dev pkg-config \
        # Not required by the app; useful for opening a database by hand.
        sqlite3 \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "${FLUTTER_VERSION}" \
        https://github.com/flutter/flutter.git "${FLUTTER_HOME}" \
    && actual="$(git -C "${FLUTTER_HOME}" rev-parse HEAD)" \
    && if [ "${actual}" != "${FLUTTER_REVISION}" ]; then \
         echo "Flutter revision mismatch." >&2; \
         echo "  tag ${FLUTTER_VERSION} is at ${actual}" >&2; \
         echo "  .metadata expects   ${FLUTTER_REVISION}" >&2; \
         exit 1; \
       fi \
    && chown -R vscode:vscode "${FLUTTER_HOME}"

USER vscode

# Flutter runs git against its own checkout, which it does not own by default.
RUN git config --global --add safe.directory "${FLUTTER_HOME}"

# Builds the flutter_tools snapshot and fetches the shared artifacts that
# `flutter test` needs, so the first command in a fresh container is not a
# multi-minute download. Platform artifacts are deliberately left out here.
RUN flutter precache --universal && flutter --version

# ---------------------------------------------------------------------------
# lite — the default: analyse, test, format, run build_runner
# ---------------------------------------------------------------------------
FROM flutter-base AS lite
# Nothing further. Kept as a named stage so the intent is explicit and the
# android stage has something to build on.

# ---------------------------------------------------------------------------
# android — adds JDK 17 and the Android SDK so `flutter build apk` works
# ---------------------------------------------------------------------------
FROM flutter-base AS android

USER root

# Levels come from this Flutter version's FlutterExtension defaults, which are
# what android/app/build.gradle.kts resolves `flutter.compileSdkVersion` and
# friends to. Bump these together with the Flutter pin.
ARG ANDROID_COMPILE_SDK=36
ARG ANDROID_BUILD_TOOLS=36.0.0
# Required, not optional: package:sqlite3's build hook compiles SQLite for each
# Android ABI using the NDK's clang.
ARG ANDROID_NDK=28.2.13676358
ARG CMDLINE_TOOLS=13114758
# Supplied by BuildKit, but only after being declared. Without this line it
# expands to nothing and JAVA_HOME below points at a path that does not exist.
ARG TARGETARCH

ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=${ANDROID_HOME}
ENV PATH=${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}

# Gradle needs a JDK; 17 matches the sourceCompatibility in
# android/app/build.gradle.kts.
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get install -y --no-install-recommends openjdk-17-jdk-headless \
    && rm -rf /var/lib/apt/lists/*
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-${TARGETARCH}

RUN mkdir -p "${ANDROID_HOME}/cmdline-tools" \
    && curl -fsSL -o /tmp/tools.zip \
        "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS}_latest.zip" \
    && unzip -q /tmp/tools.zip -d "${ANDROID_HOME}/cmdline-tools" \
    && mv "${ANDROID_HOME}/cmdline-tools/cmdline-tools" \
          "${ANDROID_HOME}/cmdline-tools/latest" \
    && rm /tmp/tools.zip

# Licences must be accepted before sdkmanager will install anything.
RUN yes | sdkmanager --licenses > /dev/null \
    && sdkmanager --install \
        "platform-tools" \
        "platforms;android-${ANDROID_COMPILE_SDK}" \
        "build-tools;${ANDROID_BUILD_TOOLS}" \
        "ndk;${ANDROID_NDK}" \
    && chown -R vscode:vscode "${ANDROID_HOME}"

USER vscode
RUN flutter config --android-sdk "${ANDROID_HOME}" && flutter precache --android

# Project-agnostic Android build environment, shared by every Android project
# onboarded onto this Jenkins after mobility-tracker-poc. Deliberately contains NO
# project-specific platforms;android-XX / build-tools;XX.0.0 packages - those are
# resolved by AGP's own SDK auto-download mechanism at build time, into a persistent
# named volume mounted at ANDROID_SDK_ROOT (see the Jenkins Shared Library that runs
# this image). Confirmed during mobility-tracker-poc's CI work: once the SDK root is
# writable and licenses are pre-accepted, sdkmanager successfully auto-downloads any
# missing package on demand - nothing project-specific needs to be baked into this
# image.
FROM eclipse-temurin:17.0.13_11-jdk-jammy

ENV ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_HOME=/opt/android-sdk \
    CMDLINE_TOOLS_VERSION=11076708 \
    HOME=/home/builder \
    GRADLE_USER_HOME=/home/builder/.gradle \
    JAVA_TOOL_OPTIONS=-Duser.home=/home/builder

ENV PATH=${PATH}:${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools

# Same user.home / getpwuid() breakage as mobility-tracker-poc's image (Jenkins' Docker
# Pipeline plugin runs the container as a passwd-less host UID). Fixes are unchanged
# since the root cause is a Jenkins/JVM issue, not a project-specific one.
RUN mkdir -p ${GRADLE_USER_HOME}

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl \
      unzip \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p ${ANDROID_SDK_ROOT}/cmdline-tools \
    && curl -fsSL -o /tmp/cmdline-tools.zip \
       "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip" \
    && unzip -q /tmp/cmdline-tools.zip -d ${ANDROID_SDK_ROOT}/cmdline-tools \
    && mv ${ANDROID_SDK_ROOT}/cmdline-tools/cmdline-tools ${ANDROID_SDK_ROOT}/cmdline-tools/latest \
    && rm /tmp/cmdline-tools.zip

# Accept every current SDK license (cheap, no download) and install only
# platform-tools (adb etc. - small, genuinely project-agnostic). Deliberately NOT
# installing any platforms;android-XX or build-tools;XX.0.0 here - see header comment.
RUN yes | sdkmanager --licenses > /dev/null \
    && sdkmanager --install "platform-tools" > /dev/null

# Fix ownership LAST, same reasoning as mobility-tracker-poc's image: any RUN step
# above could write root-owned files under these trees (sdkmanager's own ~/.android
# side effects included). Also matters for a new reason here: a fresh named volume
# mounted onto ANDROID_SDK_ROOT copies this image's existing content in on first use,
# so this chmod is what makes that first-mount copy already world-writable - required
# for AGP's runtime auto-download (running as the jenkins UID) to write new packages
# into that same volume.
RUN chmod -R a+rwX ${ANDROID_SDK_ROOT} ${HOME}

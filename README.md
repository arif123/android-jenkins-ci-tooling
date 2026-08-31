# jenkins-ci-tooling

Shared Android CI infrastructure for Jenkins: a generic Docker build image plus a
Jenkins Shared Library, so any Android project can be built through Jenkins without
adding a Dockerfile or Jenkinsfile to that project's own repository. Also includes a
standalone script to build any Android project's APK with only Docker installed - no
Jenkins required.

See `docs/Android-CI-User-Manual.pdf` (or `docs/user-manual.html`) for the full guide
covering day-to-day usage, onboarding a new project, and troubleshooting. This README
is just the one-time setup on a new machine.

## What's in this repo

- `docker/android-generic-image/` - the build image (JDK 17 + Android SDK
  cmdline-tools). Deliberately contains no project-specific platform/build-tools
  versions - those are resolved automatically per project at build time and cached in
  a shared Docker volume.
- `vars/androidBuildPipeline.groovy` - the Jenkins Shared Library step used by every
  project onboarded through Jenkins.
- `scripts/build-apk.sh` - build any Android project locally, Docker-only, no Jenkins
  needed.
- `docs/` - the full user manual (HTML + PDF).

## Setup on a new machine

**Prerequisites**: Docker installed and running; Jenkins installed and running as a
service, with the Pipeline, Git, JUnit, Credentials Binding, and Docker Pipeline
plugins (these ship with most default Jenkins installs - if Docker Pipeline isn't
present, install it from Manage Jenkins → Plugins).

1. **Clone this repo** somewhere on the machine running Jenkins:
   ```bash
   git clone <this-repo-location> /path/to/jenkins-ci-tooling
   ```

2. **Allow Jenkins to check out local git repositories.** This repo, and typically the
   per-project repos you point Jenkins at for local-path testing, live on local disk
   rather than a remote host, which Git treats as a security boundary by default:
   ```bash
   sudo git config --system --add safe.directory '*'
   ```

3. **Allow Jenkins' Git plugin to check out from local filesystem paths.** Blocked by
   default as a separate security guard:
   ```bash
   sudo mkdir -p /etc/systemd/system/jenkins.service.d
   sudo tee /etc/systemd/system/jenkins.service.d/override.conf > /dev/null <<'EOF'
   [Service]
   Environment="JAVA_OPTS=-Djava.awt.headless=true -Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true"
   EOF
   sudo systemctl daemon-reload
   sudo systemctl restart jenkins
   ```
   If your Jenkins install already sets other `JAVA_OPTS`, merge them into this line
   instead of replacing it. If Jenkins isn't run via systemd on your machine, set the
   same `-D` flag through whatever mechanism starts its JVM instead.

   > If every project you'll build is hosted on GitHub/GitLab/etc. rather than checked
   > out from a local path, steps 2 and 3 aren't strictly required - they only matter
   > for local-filesystem git access. Doing them anyway is harmless.

4. **Build the generic Docker image once:**
   ```bash
   docker build -t android-generic-build:latest /path/to/jenkins-ci-tooling/docker/android-generic-image
   ```
   Re-run this whenever `docker/android-generic-image/Dockerfile` changes.

5. **Register the Shared Library in Jenkins**: Manage Jenkins → System → **Global
   Trusted Pipeline Libraries** → Add:
   - Name: `android-ci`
   - Default version: `main`
   - Retrieval method: Modern SCM → Git
   - Project Repository: `/path/to/jenkins-ci-tooling` (wherever you cloned it in step 1)
   - Credentials: none needed for a local path
   - Load implicitly: leave unchecked
   - Save

You're now ready to build any Android project - see `docs/Android-CI-User-Manual.pdf`
for onboarding a project into Jenkins, building locally with `scripts/build-apk.sh`,
and troubleshooting.

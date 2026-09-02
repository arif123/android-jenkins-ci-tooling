#!/usr/bin/env bash
# One-shot setup for a new machine that will run Jenkins with this repo's Android CI
# tooling. Installs Docker + Jenkins, applies the local-checkout permission fixes
# documented in README.md's "Setup on a new machine" section, clones this repo, and
# builds the generic build image.
#
# Usage:
#   sudo ./scripts/setup-new-machine.sh [repo-clone-url] [install-dir]
#
# Defaults to this project's own GitHub origin, installed into /opt/jenkins-ci-tooling.
set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

REPO_URL="${1:-https://github.com/arif123/android-jenkins-ci-tooling.git}"
INSTALL_DIR="${2:-/opt/jenkins-ci-tooling}"
REAL_USER="${SUDO_USER:-$USER}"

echo "==> Installing Docker and git"
apt-get update
apt-get install -y docker.io git curl ca-certificates gnupg

systemctl enable --now docker
usermod -aG docker "$REAL_USER"

echo "==> Installing Jenkins (official LTS repo)"
if ! command -v jenkins &>/dev/null; then
  apt-get install -y openjdk-21-jre
  curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key \
    | tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
  echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
    | tee /etc/apt/sources.list.d/jenkins.list > /dev/null
  apt-get update
  apt-get install -y jenkins
fi
systemctl enable --now jenkins
usermod -aG docker jenkins

echo "==> Allowing Jenkins to check out local git repositories"
if ! git config --system --get-all safe.directory 2>/dev/null | grep -qx '\*'; then
  git config --system --add safe.directory '*'
fi

echo "==> Allowing Jenkins' Git plugin to check out from local filesystem paths"
mkdir -p /etc/systemd/system/jenkins.service.d
cat > /etc/systemd/system/jenkins.service.d/override.conf <<'EOF'
[Service]
Environment="JAVA_OPTS=-Djava.awt.headless=true -Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true"
EOF
systemctl daemon-reload
systemctl restart jenkins

echo "==> Cloning jenkins-ci-tooling into $INSTALL_DIR"
if [[ -d "$INSTALL_DIR/.git" ]]; then
  git -C "$INSTALL_DIR" pull
else
  git clone "$REPO_URL" "$INSTALL_DIR"
fi
chown -R "$REAL_USER":"$REAL_USER" "$INSTALL_DIR"

echo "==> Building the generic Android build image"
docker build -t android-generic-build:latest "$INSTALL_DIR/docker/android-generic-image"

cat <<EOF

Setup complete.

Jenkins is running at http://localhost:8080
Initial admin password:
$(cat /var/lib/jenkins/secrets/initialAdminPassword 2>/dev/null || echo "  (not found yet - Jenkins may still be starting; check again shortly)")

Remaining manual step (per README.md): register the Shared Library in
Jenkins -> Manage Jenkins -> System -> Global Trusted Pipeline Libraries:
  Name: android-ci
  Default version: main
  Retrieval method: Modern SCM -> Git
  Project Repository: $INSTALL_DIR

Note: '$REAL_USER' was added to the 'docker' group - log out and back in
(or reboot) for that to take effect in your shell.
EOF

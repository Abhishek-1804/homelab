#!/usr/bin/env bash
# Download pinned kind/kubectl/helm/helmfile/yq binaries into BIN (default ./bin).
# No system package manager — works on macOS and Linux (amd64/arm64).
set -euo pipefail

BIN="${1:-${BIN:-$(pwd)/bin}}"
# keep the helm-diff plugin local to the repo
export HELM_DATA_HOME="$BIN/.helm"

# pinned versions
KUBECTL_VERSION="v1.30.2"
KIND_VERSION="v0.23.0"
YQ_VERSION="v4.44.2"
HELM_VERSION="v3.17.3"
HELMFILE_VERSION="0.166.0"
HELM_DIFF_VERSION="v3.9.13"

# normalise uname output to release-artifact naming (darwin/linux, amd64/arm64)
case "$(uname -s)" in
    Darwin) OS="darwin" ;;
    Linux)  OS="linux" ;;
    *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
    x86_64)         ARCH="amd64" ;;
    arm64|aarch64)  ARCH="arm64" ;;
    *) echo "unsupported arch: $(uname -m)" >&2; exit 1 ;;
esac

mkdir -p "$BIN"

[ -x "$BIN/kubectl" ] || { echo "→ kubectl $KUBECTL_VERSION"; \
    curl -fsSL "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/$OS/$ARCH/kubectl" -o "$BIN/kubectl"; }

[ -x "$BIN/kind" ] || { echo "→ kind $KIND_VERSION"; \
    curl -fsSL "https://github.com/kubernetes-sigs/kind/releases/download/$KIND_VERSION/kind-$OS-$ARCH" -o "$BIN/kind"; }

[ -x "$BIN/yq" ] || { echo "→ yq $YQ_VERSION"; \
    curl -fsSL "https://github.com/mikefarah/yq/releases/download/$YQ_VERSION/yq_${OS}_${ARCH}" -o "$BIN/yq"; }

[ -x "$BIN/helm" ] || { echo "→ helm $HELM_VERSION"; \
    curl -fsSL "https://get.helm.sh/helm-$HELM_VERSION-$OS-$ARCH.tar.gz" | tar -xz -O "$OS-$ARCH/helm" > "$BIN/helm"; }

[ -x "$BIN/helmfile" ] || { echo "→ helmfile $HELMFILE_VERSION"; \
    curl -fsSL "https://github.com/helmfile/helmfile/releases/download/v$HELMFILE_VERSION/helmfile_${HELMFILE_VERSION}_${OS}_${ARCH}.tar.gz" | tar -xz -O helmfile > "$BIN/helmfile"; }

chmod +x "$BIN/kubectl" "$BIN/kind" "$BIN/yq" "$BIN/helm" "$BIN/helmfile"

# helm-diff: required by `helmfile apply`
"$BIN/helm" plugin list 2>/dev/null | grep -q '^diff' || { echo "→ helm-diff plugin $HELM_DIFF_VERSION"; \
    "$BIN/helm" plugin install https://github.com/databus23/helm-diff --version "$HELM_DIFF_VERSION" 2>/dev/null || true; }

echo "dependencies ready in $BIN"

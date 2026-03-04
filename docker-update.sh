#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="."
BRANCH="main"
GIT_IMAGE="alpine/git:latest"

# 1) git pull через docker
STEP_START=$(date +%s)
docker run --rm \
  -v "$(cd "$REPO_DIR" && pwd)":/repo \
  -v "$HOME/.ssh":/root/.ssh:ro \
  -w /repo \
  "$GIT_IMAGE" \
  checkout "$BRANCH"

docker run --rm \
  -v "$(cd "$REPO_DIR" && pwd)":/repo \
  -v "$HOME/.ssh":/root/.ssh:ro \
  -w /repo \
  "$GIT_IMAGE" \
  pull origin "$BRANCH"

STEP_END=$(date +%s)
echo "✅ Шаг 1: git pull выполнен успешно за $((STEP_END - STEP_START)) сек."

# 2) build Dockerfile в репе
STEP_START=$(date +%s)
docker build -t openclaw:local -f "$REPO_DIR/Dockerfile.mod" "$REPO_DIR"
STEP_END=$(date +%s)
echo "✅ Шаг 2: docker build выполнен успешно за $((STEP_END - STEP_START)) сек."

# 3) docker compose up -d в той же папке
STEP_START=$(date +%s)
docker compose up -d
STEP_END=$(date +%s)
echo "✅ Шаг 3: docker compose up -d выполнен успешно за $((STEP_END - STEP_START)) сек."
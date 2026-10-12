#!/usr/bin/env bash
# 本地只负责创建自定义版标签；源码版本始终跟随上游。GitHub Actions 会校验、构建、
# 部署 Pages、上传安装包，
# 最后才公开 Release。发布失败时 Release 保持草稿，便于修复后重跑。
#
# 用法：scripts/release.sh <upstream-version>-custom.<revision>
#   scripts/release.sh 0.8.2-custom.1
set -euo pipefail

VER="${1:?用法: scripts/release.sh <upstream-version>-custom.<revision>}"
TAG="v${VER}"
cd "$(dirname "$0")/.."

if [[ ! "${VER}" =~ ^([0-9]+\.[0-9]+\.[0-9]+)-custom\.([1-9][0-9]*)$ ]]; then
  echo "!! 版本必须是 <上游版本>-custom.<修订号>，例如 0.8.2-custom.1"
  exit 1
fi
SOURCE_VER="${BASH_REMATCH[1]}"
PACKAGE_VER="$(node -p "require('./package.json').version")"
TAURI_VER="$(node -p "require('./src-tauri/tauri.conf.json').version")"
CARGO_VER="$(sed -n 's/^version = "\([^"]*\)"/\1/p' src-tauri/Cargo.toml | head -n 1)"
if [[ "${SOURCE_VER}" != "${PACKAGE_VER}" || "${SOURCE_VER}" != "${TAURI_VER}" || "${SOURCE_VER}" != "${CARGO_VER}" ]]; then
  echo "!! 标签基准版本 ${SOURCE_VER} 与源码版本不一致：package=${PACKAGE_VER}, Tauri=${TAURI_VER}, Cargo=${CARGO_VER}"
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "!! 工作区不干净，请先提交或暂存现有修改"
  exit 1
fi
BRANCH="$(git branch --show-current)"
if [ "${BRANCH}" != "custom/main" ]; then
  echo "!! 只能从 custom/main 发布，当前分支是 ${BRANCH:-（detached HEAD）}"
  exit 1
fi
if git rev-parse "${TAG}" >/dev/null 2>&1; then
  echo "!! 标签 ${TAG} 已存在"
  exit 1
fi

git push origin custom/main
git tag -s "${TAG}" -m "${TAG}"
git push origin "${TAG}"

REPO="$(gh repo view "$(git remote get-url origin)" --json nameWithOwner --jq .nameWithOwner)"
echo "==> ${TAG} 已交给 GitHub Actions 自动发布"
echo "    https://github.com/${REPO}/actions/workflows/build.yml"

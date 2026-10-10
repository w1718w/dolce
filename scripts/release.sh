#!/usr/bin/env bash
# 本地只负责 bump 版本并推标签；GitHub Actions 会校验、构建、部署 Pages、上传安装包，
# 最后才公开 Release。发布失败时 Release 保持草稿，便于修复后重跑。
#
# 用法：scripts/release.sh <version>
#   scripts/release.sh 0.8.3
set -euo pipefail

VER="${1:?用法: scripts/release.sh <version>}"
TAG="v${VER}"
cd "$(dirname "$0")/.."

if [ -n "$(git status --porcelain)" ]; then
  echo "!! 工作区不干净，请先提交或暂存现有修改"
  exit 1
fi
if git rev-parse "${TAG}" >/dev/null 2>&1; then
  echo "!! 标签 ${TAG} 已存在"
  exit 1
fi

echo "==> bump 版本 → ${VER}"
sed -i '' "s/\"version\": \"[0-9][0-9.]*\"/\"version\": \"${VER}\"/" package.json src-tauri/tauri.conf.json
sed -i '' "s/^version = \"[0-9][0-9.]*\"/version = \"${VER}\"/" src-tauri/Cargo.toml
sed -i '' "s/\"softwareVersion\": \"[0-9][0-9.]*\"/\"softwareVersion\": \"${VER}\"/" index.html seo/head.en.html
( cd src-tauri && cargo update -p dolce --precise "${VER}" >/dev/null 2>&1 || true )

git add package.json index.html seo/head.en.html src-tauri/tauri.conf.json src-tauri/Cargo.toml src-tauri/Cargo.lock
git commit -m "发布 ${TAG}"
git tag "${TAG}"
git push origin HEAD:main
git push origin "${TAG}"

REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
echo "==> ${TAG} 已交给 GitHub Actions 自动发布"
echo "    https://github.com/${REPO}/actions/workflows/build.yml"

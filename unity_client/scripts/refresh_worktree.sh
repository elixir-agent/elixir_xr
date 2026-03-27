#!/bin/bash
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_ROOT="/mnt/d/tmp/vrex_client"

mkdir -p "$TARGET_ROOT"

rsync -a --delete \
  --exclude 'Library/' \
  --exclude 'Build/' \
  --exclude 'Logs/' \
  --exclude 'UserSettings/' \
  --exclude '.utmp/' \
  --exclude 'Temp/' \
  --exclude 'Obj/' \
  "$SOURCE_ROOT/Assets/" "$TARGET_ROOT/Assets/"

rsync -a --delete "$SOURCE_ROOT/Packages/" "$TARGET_ROOT/Packages/"
rsync -a --delete "$SOURCE_ROOT/ProjectSettings/" "$TARGET_ROOT/ProjectSettings/"
rsync -a "$SOURCE_ROOT/build.sh" "$TARGET_ROOT/build.sh"
rsync -a "$SOURCE_ROOT/.gitignore" "$TARGET_ROOT/.gitignore"

if [ -f "$SOURCE_ROOT/QUEST3_BUILD_GUIDE.md" ]; then
  rsync -a "$SOURCE_ROOT/QUEST3_BUILD_GUIDE.md" "$TARGET_ROOT/QUEST3_BUILD_GUIDE.md"
fi

echo "✓ Unity ワークツリーを同期: $TARGET_ROOT"

#!/bin/bash
# ───────────────────────────────────────────────────────────────
# Vrex Quest 3 APK ビルドスクリプト
# 使い方: bash build.sh [オプション]
#
# オプション:
#   -o <path>   出力 APK パス（デフォルト: Build/Vrex.apk）
#   -u <path>   Unity 実行ファイルのパス（自動検出を上書き）
#   -d          Quest に直接インストール（adb 必要）
# ───────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKTREE_ROOT="/mnt/d/tmp/vrex_client"

if [ "$SCRIPT_DIR" != "$WORKTREE_ROOT" ]; then
  "$SCRIPT_DIR/scripts/refresh_worktree.sh"
  cd "$WORKTREE_ROOT"
  exec bash ./build.sh "$@"
fi

OUTPUT="Build/Vrex.apk"
DEPLOY=0
UNITY_PATH=""

# ── 引数パース ────────────────────────────────────────────────
while getopts "o:u:d" opt; do
  case $opt in
    o) OUTPUT="$OPTARG" ;;
    u) UNITY_PATH="$OPTARG" ;;
    d) DEPLOY=1 ;;
    *) echo "Usage: $0 [-o output.apk] [-u unity_path] [-d]"; exit 1 ;;
  esac
done

# ── Unity パスの自動検出 ──────────────────────────────────────
if [ -z "$UNITY_PATH" ]; then
  # macOS
  if [ -d "/Applications/Unity/Hub/Editor" ]; then
    UNITY_PATH=$(find /Applications/Unity/Hub/Editor -name "Unity" -type f | sort -V | tail -1)
  fi
  # Linux
  if [ -z "$UNITY_PATH" ] && [ -d "$HOME/.local/share/unity-hub" ]; then
    UNITY_PATH=$(find "$HOME/.local/share/unity-hub" -name "Unity" -type f | sort -V | tail -1)
  fi
  # Windows (WSL) - D: ドライブの手動インストール優先
  if [ -z "$UNITY_PATH" ] && [ -d "/mnt/d/Tools/Unity" ]; then
    UNITY_PATH=$(find "/mnt/d/Tools/Unity" -name "Unity.exe" | sort -V | tail -1)
  fi
  if [ -z "$UNITY_PATH" ] && [ -d "/mnt/c/Program Files/Unity/Hub/Editor" ]; then
    UNITY_PATH=$(find "/mnt/c/Program Files/Unity/Hub/Editor" -name "Unity.exe" | sort -V | tail -1)
  fi
fi

if [ -z "$UNITY_PATH" ]; then
  echo "❌ Unity が見つかりません。-u オプションでパスを指定してください。"
  echo "   例: bash build.sh -u \"/Applications/Unity/Hub/Editor/2022.3.55f1/Unity.app/Contents/MacOS/Unity\""
  exit 1
fi

echo "✓ Unity: $UNITY_PATH"
echo "✓ 出力:  $OUTPUT"

# ── ビルド実行 ────────────────────────────────────────────────
mkdir -p "$(dirname "$OUTPUT")"

# WSL 環境では wslpath -w で Windows パスに変換して Unity.exe を直接呼ぶ
if [[ "$UNITY_PATH" == *.exe ]]; then
  "$UNITY_PATH" \
    -batchmode \
    -quit \
    -projectPath "$(wslpath -w "$(pwd)")" \
    -buildTarget Android \
    -executeMethod BuildScript.BuildAndroid \
    -buildOutput "$(wslpath -w "$(pwd)/$OUTPUT")" \
    -logFile "$(wslpath -w "$(pwd)/Build/build.log")"
else
  "$UNITY_PATH" \
    -batchmode \
    -quit \
    -projectPath "$(pwd)" \
    -buildTarget Android \
    -executeMethod BuildScript.BuildAndroid \
    -buildOutput "$OUTPUT" \
    -logFile Build/build.log
fi

BUILD_RESULT=$?

if [ $BUILD_RESULT -eq 0 ]; then
  APK_SIZE=$(du -sh "$OUTPUT" | cut -f1)
  echo ""
  echo "✅ ビルド成功!"
  echo "   APK: $OUTPUT ($APK_SIZE)"
else
  echo ""
  echo "❌ ビルド失敗 (終了コード: $BUILD_RESULT)"
  echo "   ログ: Build/build.log"
  tail -50 Build/build.log
  exit $BUILD_RESULT
fi

# ── Quest への自動インストール ────────────────────────────────
if [ $DEPLOY -eq 1 ]; then
  echo ""
  echo "📱 Quest にインストール中..."
  DEVICES=$(cmd.exe /c "cd /d C:\ && adb devices" | tr -d '\r' | grep -v "List of devices" | grep "device$" | wc -l)

  if [ "$DEVICES" -eq 0 ]; then
    echo "❌ Quest が接続されていません。USB-C で接続し、デバッグを許可してください。"
    exit 1
  fi

  WIN_APK=$(wslpath -m "$(pwd)/$OUTPUT")
  cmd.exe /c "cd /d C:\ && adb install -r \"$WIN_APK\""
  echo "✅ インストール完了!"
  echo ""
  echo "Quest のライブラリ →「不明なソース」→ Vrex から起動できます。"
fi

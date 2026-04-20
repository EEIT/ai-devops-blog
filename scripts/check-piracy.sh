#!/usr/bin/env bash
# check-piracy.sh — 從每篇文章抽取 2 段獨特片語，產生 Google 搜尋 URL 清單
#
# 用法：
#   ./scripts/check-piracy.sh                 # 輸出所有文章的搜尋 URL
#   ./scripts/check-piracy.sh --open          # 直接用預設瀏覽器開啟（慎用，會開十幾個頁籤）
#   ./scripts/check-piracy.sh --post 01       # 只跑單一文章（依檔名前綴）
#
# 策略：
#   取文章 frontmatter 的 description（最精煉的獨特句），以及正文中長度 20–35 字的代表性句子。
#   用 "完整引號" 包起來，Google 搜尋若出現非本站網域的結果，即為疑似轉載。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
POSTS_DIR="$REPO_ROOT/content/posts"

OPEN_IN_BROWSER=0
POST_FILTER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --open) OPEN_IN_BROWSER=1; shift ;;
    --post) POST_FILTER="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *) echo "未知參數: $1" >&2; exit 1 ;;
  esac
done

if [[ ! -d "$POSTS_DIR" ]]; then
  echo "找不到文章目錄：$POSTS_DIR" >&2
  exit 1
fi

urlencode() {
  # 純 bash 的 URL-encode（UTF-8 安全版）。
  # 關鍵：LC_ALL=C 讓 bash 逐 byte 迭代而非逐 Unicode code point，
  #       配合 printf '%%%02X' 即可正確產出多 byte 字元的百分比編碼。
  local LC_ALL=C
  local string="$1" encoded="" pos c o
  for (( pos=0; pos<${#string}; pos++ )); do
    c="${string:$pos:1}"
    case "$c" in
      [-_.~a-zA-Z0-9]) o="$c" ;;
      *) printf -v o '%%%02X' "'$c" ;;
    esac
    encoded+="$o"
  done
  printf '%s' "$encoded"
}

process_post() {
  local file="$1"
  local basename
  basename="$(basename "$file" .md)"

  echo ""
  echo "═══════════════════════════════════════════════════════════"
  echo "  $basename"
  echo "═══════════════════════════════════════════════════════════"

  # 抽 description（frontmatter 內 description: "..." 這行）
  local desc
  desc="$(awk '/^description:/ { sub(/^description: *"?/, ""); sub(/"?$/, ""); print; exit }' "$file" || true)"
  if [[ -n "$desc" ]]; then
    local encoded
    encoded="$(urlencode "\"$desc\"")"
    echo "  [1] 描述片語："
    echo "      原文：$desc"
    echo "      搜尋：https://www.google.com/search?q=$encoded"
    [[ "$OPEN_IN_BROWSER" -eq 1 ]] && open_url "https://www.google.com/search?q=$encoded"
  fi

  # 從正文（frontmatter 第二個 --- 之後）抽一段中文字數 20–35 的代表句。
  # awk 的 length() 對 UTF-8 計 byte 不計字元，中文 1 字 = 3 bytes，
  # 所以以 bytes 60–105 作為過濾條件（約 20–35 中文字）。
  local body_sentence
  body_sentence="$(
    awk '
      BEGIN { fm = 0 }
      /^---$/ { fm++; next }
      fm < 2 { next }
      {
        line = $0
        # 跳過空行、標題、程式碼圍欄、清單、引用、連結卡片
        if (line ~ /^[[:space:]]*$/) next
        if (line ~ /^(#|```|> |- |\* |[0-9]+\.|!\[|\[|\|)/ ) next
        # 表格列內容也排除
        if (line ~ /\|.*\|/) next
        # 按中文句號／驚嘆／問號切
        n = split(line, parts, /[。！？]/)
        for (i = 1; i <= n; i++) {
          s = parts[i]
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
          gsub(/[*`\[\]()]/, "", s)
          blen = length(s)
          if (blen >= 60 && blen <= 105) {
            print s
            exit
          }
        }
      }
    ' "$file" || true
  )"
  if [[ -n "$body_sentence" ]]; then
    local encoded2
    encoded2="$(urlencode "\"$body_sentence\"")"
    echo "  [2] 正文特徵句："
    echo "      原文：$body_sentence"
    echo "      搜尋：https://www.google.com/search?q=$encoded2"
    [[ "$OPEN_IN_BROWSER" -eq 1 ]] && open_url "https://www.google.com/search?q=$encoded2"
  fi
}

open_url() {
  local url="$1"
  if command -v start.exe >/dev/null 2>&1; then
    start.exe "$url"
  elif command -v cmd.exe >/dev/null 2>&1; then
    cmd.exe /c start "" "$url"
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url"
  elif command -v open >/dev/null 2>&1; then
    open "$url"
  else
    echo "找不到可用的瀏覽器啟動器，請手動開啟 URL" >&2
  fi
}

echo "AI 輔助維運工程 — 盜版偵測搜尋清單"
echo "掃描目錄：$POSTS_DIR"
[[ -n "$POST_FILTER" ]] && echo "過濾條件：檔名前綴 = $POST_FILTER"

shopt -s nullglob
for file in "$POSTS_DIR"/*.md; do
  [[ "$(basename "$file")" == search.md ]] && continue
  [[ "$(basename "$file")" == 00-series-index.md ]] && continue
  if [[ -n "$POST_FILTER" ]]; then
    [[ "$(basename "$file")" == "$POST_FILTER"* ]] || continue
  fi
  process_post "$file"
done

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "完成。建議行動："
echo "  1. 逐條開啟搜尋 URL，若首頁出現非本站結果 → 列入嫌疑名單"
echo "  2. 對嫌疑網頁執行浮水印驗證（見 docs/PIRACY-MONITORING.md §1.4）"
echo "  3. 確認為盜版後，依 §2 處置流程行動"
echo "═══════════════════════════════════════════════════════════"

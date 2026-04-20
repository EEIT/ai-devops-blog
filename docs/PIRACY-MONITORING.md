# 盜版監控 SOP

本站採用 **CC BY-NC 4.0** 授權。個人分享與改作歡迎（需署名並註明原文），但禁止商業使用。
本文件說明如何定期偵測商業盜用與未署名搭便車，並在發現時採取行動。

---

## 1. 偵測層（由低成本到高成本）

### 1.1 Google Alerts — 被動監控（每週 5 分鐘維護）

1. 進入 https://www.google.com/alerts
2. 針對**每篇文章**，選出 1–2 段語感獨特的片語（15–25 字，建議包含作者特有的用字風格）
3. 用完整引號包起來建立快訊：`"你的獨特片語"`，例如：
   - `"從 Claude Code 的運作機制,到企業導入的商務與技術治理"`
   - `"為 infra 工程師而寫的 Claude Code 深度系列"`
4. 頻率設「即時」，來源設「全部」，語言設「任何語言」（抓翻譯盜版）
5. 結果寄到 `st333117@gmail.com`，Gmail 加 filter 自動歸檔到 `Label: piracy-watch`

> 所有獨特片語的產生可由 `scripts/check-piracy.sh` 半自動化，見 §3。

### 1.2 Google Search Console — 反向索引監控（每月 1 次）

網站已在 GSC 驗證（`googleSiteVerification` 已設定）。每月固定檢查：

| 報表位置 | 關注什麼 |
|---------|---------|
| **連結 → 最常連結的網站** | 出現不認識的 referring domain？可能是盜站的「原文出處」連結 |
| **效能 → 查詢** | 有文章標題直接出現在別人的查詢中，但點擊落在零次？可能有人在別處排名更高 |
| **索引 → 網頁 → 重複網頁未使用使用者選取的標準網頁** | Google 認為你的內容在別的 URL 是正本 → 嚴重警訊 |

### 1.3 手動 Fingerprint 搜尋（每季 1 次）

執行 `scripts/check-piracy.sh`，產生每篇文章的「獨特片語 Google 搜尋 URL」。
用瀏覽器逐一開啟（約 20 個頁籤），快速掃視是否有非本站的結果。

### 1.4 隱形浮水印驗證（有嫌疑時才做）

文章已於 `layouts/partials/invisible_watermark.html` 注入 `sha1(.Permalink)` 的 160 位元指紋。

**驗證步驟**：

```bash
# 1. 從嫌疑網頁複製疑似盜版的文字內容到 suspect.txt
# 2. 抽出只含 U+200B (0) 與 U+200C (1) 的字元序列
python3 -c "
import sys
text = open('suspect.txt', encoding='utf-8').read()
bits = ''.join('0' if c == '\u200b' else '1' if c == '\u200c' else '' for c in text)
print(f'擷取 {len(bits)} bits')
# 每 4 bits 轉 hex
hex_str = ''.join(f'{int(bits[i:i+4], 2):x}' for i in range(0, len(bits) - (len(bits) % 4), 4))
print(f'Hex: {hex_str}')
"

# 3. 計算原文 permalink 的 sha1
echo -n "https://你的網址/posts/01-why-claude-code-is-different/" | sha1sum

# 4. 兩者比對 — 完全相同 = 強力證據
```

---

## 2. 處置流程（發現盜版後）

### 2.1 分類

| 類型 | 處置優先級 | 範例 |
|------|-----------|------|
| **完整保留署名與連結的個人轉載** | 無需處理 — 完全符合授權 | 個人部落格完整轉載並 credit |
| **刪除署名或偽稱原創** | 高 — 立即發函 | 公司電子報匿名刊登 |
| **商業使用**（付費電子報、廣告站、培訓教材） | 高 — 立即發函 + 法律備案 | Medium 會員訂閱牆後方、付費課程講義 |
| **改作／翻譯後未署名或去除原文連結** | 高 — 立即發函要求補齊署名 | 中→英翻譯但未標示原作者 |
| **AI 訓練語料蒐集站** | 中 — 發 `robots.txt` + DMCA | `commoncrawl.org` 等可用 robots 擋 |

### 2.2 DMCA Takedown 模板（英文／繁中雙語）

儲存於 `docs/templates/dmca-notice.md`（待使用者首次使用時建立）。
基本結構：

1. **Identification of copyrighted work** — 提供原文 URL 與發布日
2. **Identification of infringing material** — 盜文 URL 逐一列出
3. **Good faith statement** — 聲明未授權
4. **Accuracy statement under penalty of perjury** — 具結陳述
5. **Contact info** — 作者實名、email、地址
6. **Physical or electronic signature** — 電子簽名

發送對象：
- 盜文網站本身的 abuse / legal 信箱（whois 查詢）
- CDN / 主機商（Cloudflare `abuse@cloudflare.com`、AWS `abuse@amazonaws.com`、GCP `network-abuse@google.com`）
- 搜尋引擎索引移除（Google Legal Removal: https://reportcontent.google.com/forms/dmca_search）

### 2.3 存證

每次發現盜版，在 `docs/piracy-incidents.md`（使用者自行建立）記錄：
- 發現日期 / 盜文 URL / 浮水印比對結果 / 處置動作 / 結案日期

稅務需要（若涉及商業授權求償）可拿此做為證據。

---

## 3. 自動化工具

- `scripts/check-piracy.sh` — 從 `content/posts/*.md` 抽取 N-gram，產生 Google 搜尋 URL 清單
- （可選）未來可擴充：接 Google Custom Search API 自動查詢、比對結果

---

## 4. 首次設定檢查表

- [ ] `hugo.toml` 的 `baseURL` 已改為正式網址（否則 canonical URL 無效）
- [ ] 每篇 Post 的 frontmatter 都有 `author` 欄位（目前都已有）
- [ ] Google Alerts 已為系列的 10 篇各建 1 條快訊
- [ ] GSC 已驗證（已完成 `googleSiteVerification`）
- [ ] 部署後用 `view-source:` 驗證網頁 head 有 `<link rel="canonical">` 且指向正確網址
- [ ] 用 `curl -s 你的網址/posts/01-xxx/ | grep -c '&#8203;\|&#8204;'` 驗證浮水印已輸出
- [ ] RSS feed 的 `<content:encoded>` 末尾確實出現「本文原刊於...」區塊
- [ ] LICENSE 檔在 GitHub repo 首頁正確顯示授權標示（GitHub 會自動識別 CC BY-NC 並顯示 badge）

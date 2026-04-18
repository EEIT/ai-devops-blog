---
title: "Sub-agent 與 Agent Team:分身 vs 分工(上)—— Sub-agent 的真實樣貌"
date: 2026-04-15
weight: 5
draft: false
author: "鄧景仁 (Scott Teng)"
series: ["AI 輔助維運工程"]
series_order: 4
tags: ["Claude Code", "Sub-agent", "Agent Architecture", "AI Coding"]
categories: ["AI 輔助維運工程"]
description: "把 Sub-agent 這個被誤解最深的概念講透。四種隔離模式、Fork 的 prompt cache 共享設計、遞迴防護、為什麼 Claude Code 每週 spawn 數千萬個 Explore agent 卻不會爆 token。這是技術篇,下篇會談 Agent Team 的治理意義。"
---

> 本文為《AI 輔助維運工程:從 Claude Code 機制到企業落地》系列第 4 篇,分上下兩集。上集聚焦 Sub-agent 的技術機制,下集談 Agent Team 的分工設計與兩者的搭配。

## 兩個被混為一談的概念

我在跟同事討論 Claude Code 的時候,常發現同一個場景被用兩種完全不同的方式描述。有人會說「我請 Claude 派了幾個 subagent 去平行跑搜尋」,另一個人會說「我用多個 agent 分工處理這個任務」。聽起來像同一件事,但這兩句話背後指的是**兩個不同層級、解決不同問題的機制**。把它們視為同義詞,是很多人上手 Claude Code 之後的第一個盲點。

為了把這件事講清楚,這篇我只談 Sub-agent,下一篇才談 Agent Team。你會看到兩者雖然名字相近,但設計目的、壽命、使用情境、對 token 的影響都完全不同。上篇讀完之後,你會知道 Sub-agent 是 Claude Code 內部的一個精巧執行機制。下篇讀完之後,你才會明白 Agent Team 其實不是技術問題,是工程治理問題。

## 先從一個比喻開始

想像你是一位主編,在寫一份重要的專題報告。這份報告需要你去查證五個不同來源的資料:翻三份期刊、比對兩份歷史檔案。你手上有五個實習生可以派遣,而你要盡快把報告完成。

你會怎麼做?最笨的方法是自己一個接一個去查,五件事做完再開始寫。聰明一點的做法是:把這五件查證任務**同時**交給五位實習生,你就在辦公室繼續思考結構,等他們陸續帶著結果回來。每位實習生只需要知道你交辦的那一件事的上下文,不需要理解整份報告的全貌。他們查完、回報、任務結束,這位實習生對你而言就「用完了」——下一份報告如果還要查證,會派遣新的實習生,不是同一個人。

這就是 Sub-agent 的運作本質。當 Claude Code 遇到一個可以切割的子任務,它會衍生出一個「分身」去處理這件事。分身的生命週期就只有這個任務——做完回報給主 agent,然後就消失。它不會被記住、不會累積經驗、也不會跟其他分身協調。它的存在目的只有一個:**讓主 agent 能專注在整體決策,不被瑣碎的子任務細節吃掉注意力與 context**。

理解這點之後,有一個重要觀念要先立:**Sub-agent 是 Claude Code 給自己用的機制,不是給你用的**。你不用親自去「指派」sub-agent,大多數時候 Claude Code 會判斷什麼時候派、派幾個、派去做什麼。你頂多是透過 prompt 暗示它「這件事可以平行查」,實際要不要開分身,是它決定的。

## 你一直在用 Sub-agent,只是沒發現

當你在 Claude Code 裡請它「幫我找出所有使用 deprecated API 的檔案」,你看起來只是提了一個問題。但如果你打開 verbose 模式觀察,會發現事情沒那麼簡單。Claude Code 很可能會先開一個名為 `Explore` 的分身,這個分身專門做唯讀搜尋,不會修改任何東西。它會用 `grep`、`glob` 這些工具快速掃過整個 codebase,把結果彙整成一份清單回傳。主 agent 拿到清單後,才開始做後續的分析或修改。

從你的角度看,這只是一次對話。實際上背後發生了「主 agent → 衍生 Explore 分身 → 分身執行 → 結果回傳 → 主 agent 繼續」這樣的流程。Explore 分身完成任務之後就消失了,它的對話歷史不會進入你的主 session。

這個機制之所以重要,是因為它直接解決了前一篇講的 context 問題。如果 Claude Code 把搜尋過程的所有細節(每個 grep 的完整輸出、每次嘗試的正則表達式、失敗的路徑)都塞進主對話,你的 context window 會在幾輪就爆掉。有了 Explore 這類 sub-agent,主 session 只看到「我派了一個分身去搜尋,它回傳這份清單」,過程細節都留在分身的獨立 context 裡,分身結束就隨之消失。

Claude Code 內建幾種不同用途的 sub-agent。除了剛提到的 Explore(唯讀搜尋),還有 Plan(唯讀規劃)、General Purpose(通用子任務)、Verification(驗證,某些版本是 feature-gated 的)、以及少數比較冷門的 agent 如 Statusline Setup、Claude Code Guide。這些 agent 的行為邊界由 Claude Code 自己定義,你不會直接呼叫它們,但你可以透過 prompt 引導 Claude Code 使用對應的類型。例如你說「先探索 codebase 再決定怎麼改」,Claude Code 有很大機會會先派 Explore 出去。

## 四種隔離模式:Sub-agent 的真正技術深度

上面講的是「為什麼要有 sub-agent」。接下來進入這篇文章最核心的部分——sub-agent 彼此之間、以及與主 agent 之間,到底是怎麼分工的?這就是「隔離模式」(isolation model)要回答的問題。

Claude Code 定義了四種隔離模式,每一種適合不同的場景。它們在四個維度上有差異:取消訊號的傳遞範圍、應用程式狀態的共用程度、權限提示是否顯示、以及 extended thinking 是否啟用。

**Sync 模式**,可以理解為「貼身的分身」。主 agent 和 sub-agent 共用同一個 AbortController——也就是說,你按 Esc 取消主 agent,sub-agent 也會一起停下。應用程式狀態(例如當前檔案、正在開啟的面板)也是共用的,sub-agent 做的改變主 agent 看得到。這個模式下,如果 sub-agent 要執行一個需要確認的危險操作(例如 `rm -rf`),會正常彈出權限對話框等你批准。Extended thinking(模型的內部推理)是從父 agent 繼承的。

這個模式的典型場景是:主 agent 派一個分身去完成某個需要用戶注意的小任務,主 agent 本身也會等這個分身完成之後再繼續。主 agent 和 sub-agent 其實是同一個「工作流」,只是暫時切換角色。

**Async 模式**和 Sync 剛好相反,可以理解為「背景執行的分身」。它有自己獨立的 AbortController——你按 Esc 取消主 agent,async sub-agent 還在背景跑自己的。應用程式狀態是隔離的(修改被當成 no-op,不會影響主環境)。這是一個關鍵設計:因為分身在背景跑,使用者可能正在忙其他事,**這時候彈出權限對話框是極糟糕的體驗**。所以 Async 模式預設 auto-deny,遇到需要權限的操作直接拒絕,分身帶著「這個動作做不到」的結果回傳。Extended thinking 也被停用,因為背景 agent 通常不需要深度推理,控制 output token 成本比較重要。

Async 模式的典型場景是:你讓 Claude Code 背景跑一個長時間的任務(例如掃描某個大型 codebase 找出所有 TODO 標記),你想繼續跟它對話其他事。這個背景分身默默完成工作,結束後把結果整合到主 session 裡。

**Fork 模式**是四種裡面設計最精巧、也最有趣的一種,下面會用整整一節深入拆解。先簡單說它的特性:Fork 分身繼承父的**完整對話歷史**——不是片段,是整段——同時擁有獨立的 AbortController。應用程式狀態是共用的,但透過一個叫 `rootSetAppState` 的機制間接存取。權限提示會以「冒泡」(bubble up)方式往上通知父 agent。Extended thinking 繼承自父 agent。

**Worktree 模式**是最實用也最安全的一種。它繼承了 Async 模式的許多特性——獨立的 AbortController、隔離的應用程式狀態、權限自動拒絕、thinking 停用——但多了一個關鍵特徵:**分身在 git worktree 裡運作**。Git worktree 允許你在同一個 repository 下開出多個獨立的工作目錄,每個目錄有自己的 branch、自己的 staging area、自己的檔案狀態。也就是說,Worktree 分身修改任何檔案都不會影響主工作目錄,分身結束後你可以選擇合併變更、丟棄、或審查後再決定。

這個模式的使用場景極有價值:當你想讓 Claude Code 嘗試一個「可能成功、可能搞砸」的大型重構,但又不想冒險動到主工作目錄,Worktree 就是天然的沙箱。如果分身做得漂亮,你合併它的變更;做得糟糕,整個 worktree 刪掉,你的主工作目錄毫髮無傷。

為了讓你一眼看到四個模式的差異,這裡用一個對照表總結。這是我整篇文章唯一用表格表達的地方,因為這四個維度太多,純文字描述會讓讀者比較困難:

| 模式 | AbortController | setAppState | Permission | Thinking | 典型用途 |
|------|----------------|-------------|-----------|----------|---------|
| Sync | 共享父的 | 共享父的 | 顯示對話框 | 繼承父的 | 貼身子任務 |
| Async | 獨立 | 隔離 (no-op) | Auto-deny | 停用 | 背景任務 |
| Fork | 獨立 | 共享(間接) | Bubble up | 繼承父的 | 平行探索 |
| Worktree | 獨立 | 隔離 | Auto-deny | 停用 | 沙箱實驗 |

看完這張表,你可能會問一個關鍵問題:為什麼 Async 和 Worktree 模式要自動拒絕權限?這不是很不方便嗎?答案其實很務實:**當 sub-agent 在背景或隔離環境運行時,彈出權限對話框會中斷使用者正在做的其他事**。更重要的是,自動化場景(例如腳本化呼叫 Claude Code)根本沒有人在螢幕前按「同意」。如果分身隨便跳出對話框,整個自動化流程就卡死了。auto-deny 是一種「寧可做不到也不要打擾使用者」的選擇。

這個設計還有一個巧妙的補充:Async 和 Worktree 模式雖然預設 deny,但如果你有設定 PreToolUse hook(第 6 篇會詳細講),hook 可以在 deny 之前先介入,做自動化的檢查。只有當 hook 也沒辦法決定時,才真的拒絕。這讓 sub-agent 在隔離模式下,仍然有機會透過 hook 完成需要權限的操作——前提是你有寫這個 hook。

## 深入 Fork:為什麼 byte-identical 這麼重要

四種模式裡面,Fork 最值得深入。原因是它涉及了 LLM 時代才有的成本優化策略——**Prompt Cache 共享**。

要理解 Fork 的巧妙,我們必須先回顧一個事實:每次 Claude Code 呼叫 Anthropic 的 API,都是把整段對話歷史重新送一次。這個成本在長 session 裡非常可觀。Anthropic 提供了 Prompt Cache 機制:如果你在一段時間內用相同的前綴(prefix)發出多個請求,後面幾次的這個共同前綴可以**以 cache 讀取**,成本只有正常 input token 的一小部分。

這個機制的關鍵限制是:prefix 必須完全相同——**逐 byte 相同**。哪怕差一個空白字元、差一個標點符號、差一個 message 的順序,cache 就 miss,整個 prefix 都要重新付費。

現在回到 Fork 的設計。當主 agent 想要派出**多個**分身平行做不同的事情,每個分身都要帶著父的完整 context。最直觀的做法是:把父的對話歷史原封不動複製 N 份,每份後面接上給那個分身的特定指令。聽起來合理,但這會產生什麼問題?

假設主 agent 的對話歷史裡,剛好有一段還沒處理完的 tool call(例如模型說「我要去跑一個 Bash 指令」,但這個指令還沒執行)。如果把這段原封不動複製到每個分身,分身看到一個「懸空的 tool call」會困惑。所以要做一點改造——把這個 tool call 填一個 placeholder result,讓它「看起來像已經完成」。

問題來了:**每個分身填的 placeholder 能不能一模一樣?** 如果不一樣(例如分身 A 填「請稍候」、分身 B 填「處理中」),這兩個 request 的 prefix 就變得不同,cache 會分裂成兩個不同的條目,命中率掉到趨近於零。

Claude Code 的解決方式是:**強制所有 Fork 分身使用完全相同的 placeholder 字串**。具體來說,所有未解決的 tool call 都被填上同一個固定字串,例如 `Fork started — processing in background`。所有分身的 message 結構長得一模一樣:父的對話歷史完全保留、所有 tool_use 都被填上相同的 placeholder、然後最後才是「給這個分身的 directive text」——只有這最後一小段 directive 是每個分身不同的。

結果是什麼?**所有 Fork 分身的 API request prefix 完全 byte-identical**,只有最後那一小段 directive 不同。這意味著 cache 命中率可以達到最高,即使同時派出 10 個分身,你付的 cache 以外的成本只有那 10 份 directive text 的差異,而不是 10 份完整 context 的重複費用。

這個設計有多精妙?你可以這樣想:如果沒有 Fork 的 byte-identical 策略,Claude Code 的平行搜尋、平行探索功能會變得非常貴,貴到 Anthropic 可能不會預設啟用,使用者也會有強烈的成本焦慮。有了這個設計,平行操作的邊際成本降到幾乎可以忽略,所以 Claude Code 才敢在使用者沒察覺的情況下,大量派出 Explore 分身去平行掃 codebase。

根據公開的逆向工程分析,Claude Code 每週光是 Explore 類型的 agent spawn 次數就達到**數千萬次**這個級別。這個數字聽起來很誇張,但正是因為有 Fork 的 cache 共享機制,這個規模才成本可控。

## 遞迴防護:避免分身無限繁殖

Fork 的設計解了 cache 問題,但帶來一個新問題:**如果 Fork 分身自己也有 Agent tool(允許它再 Fork 更多分身),會不會造成無限遞迴?**

答案在技術上是「可能」。主 agent Fork 一個子,子 Fork 一個孫,孫 Fork 一個曾孫……理論上可以無限展開。每一層都消耗 token,但不會產生什麼有意義的工作,這是明顯的災難。

Claude Code 的處理方式很務實:**允許 Fork 分身擁有 Agent tool 的宣告(為了保持 tool definitions 的 byte-identical),但在呼叫時攔截**。具體做法是,每個 Fork 分身的 message 歷史裡會帶一個特殊標記(可以想成一個隱形的 tag,例如 `<fork-boilerplate>`)。當任何 agent 要 Fork 時,先檢查自己的 context 裡有沒有這個標記。有的話,就拒絕這次 Fork 請求。這樣一來,只有「根」層的主 agent 能 Fork,所有分身都是一代而已。

搭配這個防護,Fork 分身的系統 prompt 還會加入一段非常強硬的行為規範:

```
你就是那個 Fork 分身。你的任務是完成主 agent 交辦的特定 directive。
你不被允許做以下事情:
- 再次 Fork(你就是那個 Fork)
- 跟主 agent 閒聊或提問
- 建議下一步該做什麼
- 延伸討論不相干的事
你必須直接使用工具完成任務,並以以下格式回報:
  Scope: 你做了什麼範圍的工作
  Result: 結果
  Key files: 有用到的重要檔案
  Files changed: 修改過的檔案清單
  Issues: 遇到的問題(如果有)
```

這段 prompt 的精神是:**分身就是分身,它不該演變成主 agent 的替代品**。它做完交辦的事,按格式回報,就結束。這個設計讓 Fork 在工程上可控,不會因為模型「自作聰明」而失控。

## Sub-agent 對 Token 的實際影響

聊了這麼多技術細節,我們回到一個更實際的問題:sub-agent 的存在,對使用者的 token 消耗到底是好事還是壞事?

直覺上會覺得:開這麼多分身,每個分身都有自己的 API call,token 一定會暴增吧?這個直覺在「如果沒有任何優化」的情況下是對的。但我們已經看到 Claude Code 做了至少三種重要優化來降低這個成本。

第一種優化,**Prompt Cache 共享**——Fork 模式下,多個分身共用大部分 prefix,只有 directive 不同,cache 命中率極高。

第二種優化,**Context 裁剪**。Explore 和 Plan 這類唯讀 agent,有一些父 agent 會載入、但分身根本用不到的內容會被主動省略。舉例來說,父 agent 載入的 `CLAUDE.md`(專案規則)對搜尋任務其實沒幫助,Explore 分身可以直接不帶它。原始碼的註解提到,光是這個省略,按 fleet-wide 規模估算就省下 5 到 15 Giga-tokens 的週消耗。這是 Anthropic 整個使用者群加總的數字,不是單一使用者,但它顯示這個優化的規模感。同樣的邏輯,Plan 和 Explore 可以省略 git status 資訊,那又是 1 到 3 Giga-tokens 的週省量。

第三種優化,**Extended Thinking 預設停用**。在 Async 和 Worktree 模式下,分身不做深度推理,只做被交辦的動作。這控制了 output token 的消耗——而 output token 比 input token 貴好幾倍。對於例行性、機械性的子任務,停用 thinking 是合理的成本控制。

這三種優化合起來的效果是:**使用 sub-agent 的平均成本,往往比「把所有事情塞進主 session」更低**。這違反了很多人的直覺,但背後的工程邏輯很清楚——隔離、共享 cache、裁剪無關內容、控制 output——每一項都在省錢。

這個事實意味著,作為使用者,你應該**積極擁抱**讓 Claude Code 派 sub-agent 的行為。當它說「我先派個分身去搜尋一下」,不要覺得這是繞遠路。從 token 經濟學來看,這通常是最省錢的路徑。

## 你能控制什麼,不能控制什麼

最後回到使用者的角度:在這套 sub-agent 機制裡,你能做什麼?不能做什麼?

**你能做的第一件事是透過 prompt 引導 Claude Code 使用 sub-agent**。如果你希望它先探索再修改,可以直接說「先全盤掃過 codebase 找出所有相關檔案,再開始改」,Claude Code 大機率會先派 Explore 出去。你不是在指揮某個特定的分身,而是在提示主 agent「這個場景適合用分身」。

**你能做的第二件事是善用 Worktree 模式**。雖然你不能直接叫 Claude Code「用 Worktree 模式 fork 一個分身」,但你可以在對話中創造適合 Worktree 的情境。例如你說「我想嘗試一個實驗性的重構,但不要動到主工作目錄」,Claude Code 理解到「沙箱實驗」的需求,會傾向用 Worktree 機制。

**你能做的第三件事是觀察與學習**。打開 verbose 模式,看 Claude Code 在你的對話裡實際派了哪些分身。久而久之你會建立一個心智模型:什麼樣的 prompt 會觸發什麼樣的 sub-agent 行為。這個 fingerprint 幫助你寫出更有效率的 prompt。

**你不能做的事是手動建立一個持久的 sub-agent**。在這裡「持久」是關鍵字——sub-agent 的壽命就是完成一個任務。你不能說「幫我留一個 subagent 在那邊,專門負責監控日誌」,這不是 Claude Code 的 sub-agent 設計初衷。如果你的需求是「有一個固定的角色,長期負責某類工作」,那你需要的不是 sub-agent,而是下一篇要講的 **Agent Team**。

這是最後一個區分兩者的線索:**sub-agent 是一次性的、任務結束就消失的;Agent Team 是長期存在、由你設計的角色**。兩者的用途完全不同,也不是互斥的——實務上最好的做法是兩者疊加,下一篇會講到怎麼搭配。

## 下一集預告

這篇談了 Sub-agent 作為 Claude Code 內部執行機制的真實樣貌。四種隔離模式、Fork 的 cache 共享精巧設計、遞迴防護、token 經濟學——這些是工程層面的事實,不太會隨你的使用習慣改變。

下一集會進入一個完全不同的層次:**Agent Team**。它不是 Claude Code 的技術機制,而是一套關於「**如何讓 AI 在複雜工作中保持紀律**」的工程設計。你會看到它跟 Sub-agent 完全無關,解決的是完全不同的問題,用的也是完全不同的工具——不是 API call 和 cache,而是 Markdown 檔案、role definition、和 handoff protocol。

一個有趣的事實是,下一集的內容在繁體中文圈幾乎沒有人好好寫過,很大程度是因為它需要「從工程治理角度理解 AI」的視角。下一集會把這個視角建立起來。

## 本篇重點

讀完這篇,希望你帶走三個核心認知。

第一,**Sub-agent 是 Claude Code 為了自己的 context 與 token 效率而設計的機制**。它是引擎蓋下的機制,你不用直接操作,但理解它幫助你寫出更好的 prompt。

第二,**四種隔離模式(Sync / Async / Fork / Worktree)各自解決不同場景**。Sync 適合貼身協作、Async 適合背景任務、Fork 適合平行探索、Worktree 適合沙箱實驗。

第三,**Fork 的 byte-identical prefix 設計是 LLM 時代特有的工程美學**。它讓大規模的 Prompt Cache 共享成為可能,這個優化是 Claude Code 能夠大量派 sub-agent 而不破產的根本原因。

如果你在看這篇之前,以為 sub-agent 就是「AI 的助手」或「一個固定的角色」,希望你現在知道這個印象需要更新了。Sub-agent 是一個**執行機制**,不是**角色**。角色,是下一篇的主題。

---

*本文作者:鄧景仁 (Scott Teng) | 資訊服務業 infra 工程師,專注於 Azure / Linux / 安全維運。如需討論可聯繫 scott.teng [at] iisigroup.com。*

*本系列所有內容為個人學習與實務心得整理,不代表任職機構立場。本文對 Claude Code 內部機制的描述,基於社群對 Claude Code 的公開分析材料與筆者實務觀察,並非 Anthropic 官方文件。具體行為可能隨版本演進。*

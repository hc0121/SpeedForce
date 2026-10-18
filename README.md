# Speed Force

> 忘了切注音，把「你好」打成 `su3cl3`？按一下熱鍵就修好。

一個 [AutoHotkey v2](https://www.autohotkey.com/) 常駐小工具，給 Windows 微軟注音使用者：
在英文模式下誤打注音按鍵時自動提示，並可一鍵切回注音重新輸入。

## 功能

- **自動偵測**：停筆 0.7 秒後，若剛打的字串符合注音音節結構（例如 `su3cl3`、`2u6g4`），
  在游標旁顯示提示 `su3cl3 → ㄋㄧˇㄏㄠˇ` 並嗶一聲。一般英文（`hello`、`do it`）不會誤判，
  中文模式下正常打字也不會觸發。
- **一鍵修正 `Ctrl+Alt+Z`**：刪掉打錯的字 → 切到微軟注音 → 重打同一串按鍵 → Enter 確認。
  不需要內建字典，直接借用輸入法的選字能力，任何詞都能修。
- 字已經送出？先選取錯字再按 `Ctrl+Alt+Z` 也可以。
- 托盤選單：自動修正（偵測到就直接修，不只提示）、提示音、開機自動啟動。

## 安裝

1. 安裝 AutoHotkey v2（一般版，非 Store 版）：
   ```powershell
   winget install -e --id AutoHotkey.AutoHotkey
   ```
2. 下載本專案，雙擊 `SpeedForce.ahk`。托盤出現綠色 H 圖示即啟動成功。
3. （可選）右鍵托盤圖示 → 勾選「開機自動啟動」。

## 設定

打開 `SpeedForce.ahk`，最上方「設定」區塊可以改：

| 變數 | 預設 | 說明 |
|---|---|---|
| `FixHotkey` | `^!z` | 修正熱鍵（AHK 語法，`^`=Ctrl `!`=Alt `+`=Shift） |
| `AutoDetect` | `true` | 打錯時自動提示 |
| `AutoFix` | `false` | 偵測到就直接自動修正 |
| `BeepOnAlert` | `true` | 提示音 |
| `AutoEnter` | `true` | 重打後自動按 Enter 確認選字 |
| `IdleMs` | `700` | 停筆多久（毫秒）後檢查 |

## 原理

```
英文模式打出 su3cl3
  → 停筆後比對注音音節正規式（聲母? 介音? 韻母? 聲調）
  → 查詢輸入法目前中/英狀態，確認是「英文模式打錯」
  → 提示 / 熱鍵：Backspace 刪字 → WM_INPUTLANGCHANGEREQUEST 切到 zh-TW
  → IMC_SETCONVERSIONMODE 切到中文 → 重送按鍵 → Enter
```

## 已知限制

- 只支援微軟注音的標準鍵盤配置（不支援倚天、許氏等配置）。
- 部分程式（如終端機、遠端桌面）的輸入法狀態無法讀取，修正後可能需要自己按 Enter。
- 自動偵測需要字串含至少一個聲調鍵（3/4/6/7）或三個以上音節，純一聲的短詞不會提示，可改用熱鍵。

## License

MIT

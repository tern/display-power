# Display Power

macOS 小工具：一鍵切換螢幕長亮 / 恢復電池預設休眠。

## 下載安裝

1. 從 [Releases](https://github.com/tern/display-power/releases) 下載 `DisplayPower-1.0.0.dmg`
2. 打開 DMG，將 **Display Power** 拖入 **Applications**
3. 首次開啟若被 Gatekeeper 擋下：右鍵 App → **打開** → 確認打開
4. 第一次切換電源模式時，會要求輸入 Mac 密碼（僅此一次，用於設定免密碼電源管理）

## 功能

| 模式 | 效果 |
|------|------|
| 螢幕維持長亮 | 螢幕不休眠、關閉自動亮度 |
| 恢復電池預設 | 電池 2 分鐘 / 接電源 10 分鐘關閉螢幕 |

- 選單列圖示：☀️（長亮）/ 🌙（預設），可在視窗內開關顯示
- 「閃爍選單列圖示」可協助定位圖示位置

## 系統需求

- macOS 13 (Ventura) 或更新版本
- Apple Silicon 或 Intel Mac

## 注意事項

- 若安裝了 **TopNotch**、**Hidden Bar**、**Bartender** 等選單列工具，可能遮住圖示
- 選單列圖示只會出現在**主螢幕**（內建螢幕）右上角
- 螢幕長亮模式會增加耗電

## 從原始碼建置

```bash
git clone https://github.com/tern/display-power.git
cd display-power
./package.sh
open dist/DisplayPower-1.0.0.dmg
```

## 授權

MIT License
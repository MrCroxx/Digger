# Pop-up 清理内容与默认尺寸

## 背景
pop-up 弹出时会短暂闪现上一轮内容。根因是弹窗关闭后仍保留了上次的文本状态，下一次展示之前先绘制了旧内容。

## 改动概览
- 关闭 pop-up 时清理所有内容与状态，避免下次弹出闪现旧内容。
- 将默认 pop-up 最大尺寸调整为 640×480（width × height）。

## 实现原理
### 关闭即清理
在弹窗关闭路径统一调用清理逻辑：
- 停止加载动画、取消布局更新、隐藏 tooltip。
- 立即清空原文与各功能区结果文本。
- 重置当前请求与定位信息，确保下次展示是干净状态。

相关代码位置：
- `Sources/digger/UI/ForceClickSelectionPopup.swift`
  - `dismissPopup()`：统一处理关闭流程。
  - `resetContentForNextShow()`：清理文本与请求状态。
  - `window.onDismiss`、`dismissOnEscape()`、`dismissIfClickOutside()` 统一走 `dismissPopup()`。

### 默认最大尺寸
默认值只在用户未设置过偏好时生效，更新默认常量即可：
- `Sources/digger/Preferences/AppPreferences.swift`
  - `defaultPopupMaxWidth = 640`
  - `defaultPopupMaxHeight = 480`

## 验证建议
1. 弹出 pop-up，获取一次结果后关闭。
2. 再次弹出，确认不再闪现旧内容。
3. 在未设置偏好的全新环境下，确认最大尺寸使用 640×480。

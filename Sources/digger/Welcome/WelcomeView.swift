import SwiftUI

struct WelcomeView: View {
    @ObservedObject var viewModel: WelcomeViewModel
    let onOpenPreferences: () -> Void
    let onStart: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 10) {
                    BrandMark(size: 40)
                    Text("Digger").font(.system(size: 30, design: .serif))
                }
                Spacer()
                Text(localized("Words,\nmade clear.", "读懂\n字里行间。", "言葉を、\nもっと明快に。"))
                    .font(.system(size: 35, weight: .medium, design: .serif)).lineSpacing(6)
                Spacer()
                Text(AppPreferences.popupShortcut().displayString())
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .padding(10).background(DiggerTheme.paper, in: RoundedRectangle(cornerRadius: 8))
            }.frame(maxWidth: .infinity, alignment: .leading)
                .padding(32).frame(width: 320).background(DiggerTheme.soft)
            VStack(alignment: .leading, spacing: 16) {
                Text(localized("Setup", "设置", "設定"))
                    .font(.system(size: 24, weight: .medium, design: .serif))
                Surface {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(UIStrings.Welcome.accessibilityTitle,
                              systemImage: viewModel.status.accessibility ? "checkmark.circle.fill" : "hand.raised")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(DiggerTheme.accent)
                        Text(localized("Read selected text in other apps.", "读取其他应用中的选中文字。", "他のアプリの選択テキストを読み取ります。"))
                            .font(.system(size: 12)).foregroundStyle(DiggerTheme.muted)
                        Button(localized("Open Settings", "打开设置", "設定を開く")) {
                            SystemPreferencesLinks.openAccessibility()
                        }
                    }
                }
                Surface {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(localized("Screen Recording", "屏幕录制", "画面収録"),
                              systemImage: viewModel.status.screenRecording ? "checkmark.circle.fill" : "rectangle.dashed")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(DiggerTheme.accent)
                        Text(localized("Capture a region for translation.", "框选截图翻译。", "範囲を選択して翻訳します。"))
                            .font(.system(size: 12)).foregroundStyle(DiggerTheme.muted)
                        Button(localized("Open Settings", "打开设置", "設定を開く")) {
                            SystemPreferencesLinks.openScreenRecording()
                        }
                        .help(localized("Restart Digger if access does not take effect after granting permission.", "授权后如未生效，请重启 Digger。", "許可が反映されない場合は Digger を再起動してください。"))
                    }
                }
                Surface {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(localized("Model API", "模型 API", "モデル API"), systemImage: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                        Text(localized("Selected text or screenshots are sent to your configured API.", "选中文字或截图会发送至你配置的 API。", "選択テキストやスクリーンショットは設定した API に送信されます。"))
                            .font(.system(size: 12)).foregroundStyle(DiggerTheme.muted)
                        Button(localized("Configure", "配置", "設定"), action: onOpenPreferences)
                    }
                }
                Toggle(UIStrings.Preferences.startOnLoginLabel, isOn: $viewModel.startOnLogin)
                Toggle(UIStrings.Welcome.skipNextTimeLabel, isOn: $viewModel.skipWelcomeWhenReady)
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    Button(UIStrings.Welcome.startButton, action: onStart)
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!viewModel.canStart)
                }
            }.font(.system(size: 12)).toggleStyle(.checkbox).padding(32).frame(maxWidth: .infinity)
        }.foregroundStyle(DiggerTheme.ink).tint(DiggerTheme.accent).background(DiggerTheme.canvas)
            .frame(minWidth: 820, minHeight: 600)
    }
}

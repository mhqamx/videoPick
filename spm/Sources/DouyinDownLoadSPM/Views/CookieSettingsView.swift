import SwiftUI

struct CookieSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cookieValues: [String: [String: String]] = [:]

    var body: some View {
        NavigationView {
            List {
                ForEach(CookieStore.supportedPlatforms, id: \.platform) { config in
                    Section {
                        ForEach(config.fields, id: \.key) { field in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(field.label)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField(field.placeholder, text: binding(for: config.platform, key: field.key))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            }
                        }

                        if CookieStore.shared.hasCookies(for: config.platform) {
                            Button("清除", role: .destructive) {
                                CookieStore.shared.clearCookies(for: config.platform)
                                cookieValues[config.platform] = [:]
                            }
                        }
                    } header: {
                        Text(config.displayName)
                    } footer: {
                        Text(footerText(for: config.platform))
                            .font(.caption2)
                    }
                }
            }
            .navigationTitle("Cookie 设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveAll()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadAll()
            }
        }
    }

    private func binding(for platform: String, key: String) -> Binding<String> {
        Binding(
            get: { cookieValues[platform]?[key] ?? "" },
            set: { newValue in
                if cookieValues[platform] == nil {
                    cookieValues[platform] = [:]
                }
                cookieValues[platform]?[key] = newValue
            }
        )
    }

    private func loadAll() {
        for config in CookieStore.supportedPlatforms {
            cookieValues[config.platform] = CookieStore.shared.cookies(for: config.platform)
        }
    }

    private func saveAll() {
        for config in CookieStore.supportedPlatforms {
            let cookies = cookieValues[config.platform] ?? [:]
            CookieStore.shared.saveCookies(for: config.platform, cookies: cookies)
        }
    }

    private func footerText(for platform: String) -> String {
        switch platform {
        case "instagram":
            return "在浏览器登录 Instagram 后，使用 Cookie 导出插件获取 sessionid 等值"
        case "x":
            return "在浏览器登录 X/Twitter 后，使用 Cookie 导出插件获取 auth_token 和 ct0 值"
        default:
            return ""
        }
    }
}

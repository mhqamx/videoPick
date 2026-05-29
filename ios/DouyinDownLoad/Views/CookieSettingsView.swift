import SwiftUI

struct CookieSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cookieValues: [String: [String: String]] = [:]
    @AppStorage(AppSettings.autoSaveKey) private var autoSaveToLibrary: Bool = false

    var body: some View {
        NavigationView {
            List {
                Section {
                    Toggle(isOn: $autoSaveToLibrary) {
                        Label {
                            Text("自动保存到相册")
                        } icon: {
                            Image(systemName: "photo.badge.arrow.down.fill")
                                .foregroundStyle(.tint)
                        }
                    }
                } header: {
                    Text("通用")
                } footer: {
                    Text("开启后，下载完成会自动归档到相册（或 Mac 下载目录），无需手动点保存。首次需授权相册访问权限。")
                        .font(.caption2)
                }

                Section {
                    NavigationLink {
                        LocationManagerView()
                    } label: {
                        Label("坐标管家", systemImage: "mappin.and.ellipse")
                    }
                } header: {
                    Text("工具")
                } footer: {
                    Text("管理常用经纬度，导出 GPX 或复制为文本，配合 iAnyGo / Xcode 等工具修改系统定位")
                        .font(.caption2)
                }

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

import SwiftUI

struct CookieSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cookieValues: [String: [String: String]] = [:]
    @ObservedObject private var yuanbaoSession = YuanbaoSessionStore.shared
    @State private var showYuanbaoLogin = false
    @State private var sessionError: String?

    var body: some View {
        NavigationView {
            List {
                Section {
                    Label(yuanbaoSession.hasSession ? "已保存登录状态" : "尚未登录", systemImage: "person.crop.circle")
                    Button(yuanbaoSession.hasSession ? "重新登录元宝" : "登录元宝") { showYuanbaoLogin = true }
                    if yuanbaoSession.hasSession {
                        Button("退出元宝登录", role: .destructive) {
                            do { try yuanbaoSession.clear(); sessionError = nil }
                            catch { sessionError = error.localizedDescription }
                        }
                    }
                    if let sessionError { Text(sessionError).foregroundStyle(.red).font(.footnote) }
                } header: {
                    Text("视频号")
                } footer: {
                    Text("首次登录后，粘贴视频号链接即可下载。登录状态仅保存在本机。")
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
            .sheet(isPresented: $showYuanbaoLogin) {
                YuanbaoLoginView(onAuthenticated: {})
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

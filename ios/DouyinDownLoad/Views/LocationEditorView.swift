import SwiftUI
import MapKit

struct LocationEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let original: SavedLocation?
    let onSave: (SavedLocation) -> Void

    @State private var name: String = ""
    @State private var latText: String = ""
    @State private var lngText: String = ""
    @State private var inputSystem: CoordinateSystem = .gcj02
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 30.2741, longitude: 120.1551),
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
    )
    @State private var pinCoordinate: CLLocationCoordinate2D?

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("如：杭州西湖", text: $name)
                        .autocorrectionDisabled()
                }

                Section {
                    Picker("输入坐标系", selection: $inputSystem) {
                        ForEach(CoordinateSystem.allCases, id: \.self) { sys in
                            Text(sys.displayName).tag(sys)
                        }
                    }
                    .onChange(of: inputSystem) { _, newSystem in
                        rewriteFieldsAfterSystemChange(to: newSystem)
                    }
                } header: {
                    Text("坐标系")
                } footer: {
                    Text(systemFooter)
                        .font(.caption2)
                }

                Section("经纬度（按所选坐标系）") {
                    HStack {
                        Text("纬度")
                            .frame(width: 50, alignment: .leading)
                            .foregroundStyle(.secondary)
                        TextField("30.2741", text: $latText)
                            .keyboardType(.numbersAndPunctuation)
                            .font(.system(.body, design: .monospaced))
                    }
                    HStack {
                        Text("经度")
                            .frame(width: 50, alignment: .leading)
                            .foregroundStyle(.secondary)
                        TextField("120.1551", text: $lngText)
                            .keyboardType(.numbersAndPunctuation)
                            .font(.system(.body, design: .monospaced))
                    }
                    if let preview = wgs84Preview {
                        Text("→ 折算后 WGS-84：\(preview)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("地图点选（Apple Map）") {
                    MapReader { proxy in
                        Map(position: $cameraPosition) {
                            if let pin = pinCoordinate {
                                Marker(name.isEmpty ? "目标" : name, coordinate: pin)
                            }
                        }
                        .frame(height: 280)
                        .onTapGesture { screenPoint in
                            if let coord = proxy.convert(screenPoint, from: .local) {
                                applyMapTap(coord)
                            }
                        }
                    }
                    Text("点击地图任意位置自动填入坐标。Apple Map 在中国境内使用 GCJ-02，已自动按所选坐标系反算。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Text("保存时统一折算成 WGS-84 落库；导出 GPX 始终是 WGS-84，给 Xcode/iAnyGo 用。这样高德、百度、微信、打车看到的位置都对得上。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(original == nil ? "新增坐标" : "编辑坐标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!isValid)
                }
            }
            .onAppear(perform: load)
        }
    }

    private var systemFooter: String {
        switch inputSystem {
        case .wgs84: return "原始 GPS 坐标。Xcode GPX 默认用这个。"
        case .gcj02: return "高德 / 腾讯 / 谷歌中国。从这些 app 复制坐标选这个。"
        case .bd09:  return "百度地图坐标。从百度复制坐标选这个。"
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && Double(latText) != nil
            && Double(lngText) != nil
    }

    private var wgs84Preview: String? {
        guard let lat = Double(latText), let lng = Double(lngText) else { return nil }
        let w = CoordinateConverter.toWGS84(lat: lat, lng: lng, from: inputSystem)
        return String(format: "%.6f, %.6f", w.lat, w.lng)
    }

    private func load() {
        if let o = original {
            name = o.name
            // 库内为 WGS-84，按当前选择的输入系统反算回去显示
            let display = CoordinateConverter.fromWGS84(lat: o.latitude, lng: o.longitude, to: inputSystem)
            latText = String(format: "%.6f", display.lat)
            lngText = String(format: "%.6f", display.lng)
            // 地图 pin 用 WGS-84（Apple Map 自身会做中国偏移）
            let coord = CLLocationCoordinate2D(latitude: o.latitude, longitude: o.longitude)
            pinCoordinate = coord
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                )
            )
        }
    }

    /// 切换坐标系时，让 latText/lngText 在新系统下显示等价值
    private func rewriteFieldsAfterSystemChange(to newSystem: CoordinateSystem) {
        // 这里 newSystem 已经是 binding 更新后的值，oldValue 在 onChange 中是 previous
        // 用 pinCoordinate（WGS-84）重新格式化即可
        guard let pin = pinCoordinate else { return }
        let display = CoordinateConverter.fromWGS84(lat: pin.latitude, lng: pin.longitude, to: newSystem)
        latText = String(format: "%.6f", display.lat)
        lngText = String(format: "%.6f", display.lng)
    }

    /// Apple Map 在中国境内瓦片是 GCJ-02 偏移过的，但 SwiftUI Map 的 tap 返回值即所点选位置的真实 WGS-84
    /// （Apple 内部已做反算）。因此 pin 直接存 WGS-84，输入框按所选系统折算显示。
    private func applyMapTap(_ wgs84Coord: CLLocationCoordinate2D) {
        pinCoordinate = wgs84Coord
        let display = CoordinateConverter.fromWGS84(
            lat: wgs84Coord.latitude,
            lng: wgs84Coord.longitude,
            to: inputSystem
        )
        latText = String(format: "%.6f", display.lat)
        lngText = String(format: "%.6f", display.lng)
    }

    private func save() {
        guard let lat = Double(latText), let lng = Double(lngText) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        // 统一归一为 WGS-84 落库
        let wgs = CoordinateConverter.toWGS84(lat: lat, lng: lng, from: inputSystem)
        let location = SavedLocation(
            id: original?.id ?? UUID(),
            name: trimmed,
            latitude: wgs.lat,
            longitude: wgs.lng,
            createdAt: original?.createdAt ?? Date()
        )
        onSave(location)
        dismiss()
    }
}

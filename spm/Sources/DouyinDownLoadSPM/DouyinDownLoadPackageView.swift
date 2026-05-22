import SwiftUI

/// Swift Package 对外暴露的根视图，用于被宿主 App 直接集成。
public struct DouyinDownLoadPackageView: View {
    public init() {}

    public var body: some View {
        ContentView()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

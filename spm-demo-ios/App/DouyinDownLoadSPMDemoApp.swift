import SwiftUI
import DouyinDownLoadSPM

@main
struct DouyinDownLoadSPMDemoApp: App {
    var body: some Scene {
        WindowGroup {
            DouyinDownLoadPackageView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

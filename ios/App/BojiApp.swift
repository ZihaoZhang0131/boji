import SwiftUI

@main
struct BojiApp: App {
    private let dependencies = AppDependencies.production()
    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
                .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
        }
    }
}

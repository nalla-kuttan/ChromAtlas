import SwiftUI

@main
struct ChromAtlasApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        LibraryIndexer.registerBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.amber)
                .task { await model.bootstrap() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.appDidEnterBackground() }
            if phase == .active { model.refreshPhotoAccess() }
        }
    }
}

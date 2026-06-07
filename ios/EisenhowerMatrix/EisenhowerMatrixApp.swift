import SwiftUI

@main
struct EisenhowerMatrixApp: App {
    @StateObject var viewModel = TaskViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
    }
}
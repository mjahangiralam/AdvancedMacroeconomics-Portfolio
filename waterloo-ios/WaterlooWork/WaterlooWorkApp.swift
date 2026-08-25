import SwiftUI

@main
struct WaterlooWorkApp: App {
    var body: some Scene {
        WindowGroup {
            MobileWebView(url: URL(string: "https://waterloo-work-mobile-ui-ai-econ-lab.vercel.app")!)
                .ignoresSafeArea(.container, edges: .bottom)
        }
    }
}

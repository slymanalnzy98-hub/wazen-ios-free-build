import SwiftUI

@main
struct WazenApp: App {
    var body: some Scene {
        WindowGroup {
            ZStack {
                Color(red: 0.012, green: 0.027, blue: 0.051)
                    .ignoresSafeArea()

                WazenWebView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .preferredColorScheme(.dark)
        }
    }
}

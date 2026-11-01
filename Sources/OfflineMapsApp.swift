import SwiftUI

@main
struct OfflineMapsApp: App {
    var body: some Scene {
        WindowGroup {
            SplashView() // يبدأ بشاشة الترحيب والأنميشن
                .preferredColorScheme(.light) // لضمان ظهور الألوان بشكل صحيح
        }
    }
}

import SwiftUI

struct SplashView: View {
    @State private var isActive = false
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0.0
    
    var body: some View {
        if isActive {
            HomeView()
        } else {
            ZStack {
                Theme.gradient.ignoresSafeArea()
                
                VStack {
                    Image(systemName: "map.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.white)
                        .scaleEffect(scale)
                        .opacity(opacity)
                    
                    Text("خرائطي")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.top, 10)
                        .opacity(opacity)
                    
                    Text("المبرمج: منتظر يسر جبار")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.top, 5)
                        .opacity(opacity)
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 1.0)) {
                    self.scale = 1.0
                    self.opacity = 1.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation {
                        self.isActive = true
                    }
                }
            }
        }
    }
}

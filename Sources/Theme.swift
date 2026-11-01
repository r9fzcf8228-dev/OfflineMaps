import SwiftUI
import UIKit

enum Theme {
    static let bgTop = Color(red: 0.03, green: 0.08, blue: 0.07)
    static let bgBottom = Color(red: 0.06, green: 0.17, blue: 0.14)
    static let accent = Color(red: 1.0, green: 0.78, blue: 0.28)
    static let accentDeep = Color(red: 0.95, green: 0.52, blue: 0.14)
    static let teal = Color(red: 0.25, green: 0.85, blue: 0.75)

    static var background: LinearGradient {
        return LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom)
    }

    static var accentGradient: LinearGradient {
        return LinearGradient(colors: [accent, accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// زر يتفاعل مع اللمس بحركة نابضة
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// بطاقة زجاجية
struct GlassCard: ViewModifier {
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 6)
    }
}

extension View {
    func glass(_ radius: CGFloat = 18) -> some View {
        modifier(GlassCard(radius: radius))
    }
}

enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// خلفية متحركة هادئة
struct AuroraBackground: View {
    @State private var move = false

    var body: some View {
        ZStack {
            Theme.background
            Circle()
                .fill(Theme.teal.opacity(0.22))
                .frame(width: 320, height: 320)
                .blur(radius: 70)
                .offset(x: move ? 120 : -120, y: move ? -180 : -80)
            Circle()
                .fill(Theme.accent.opacity(0.16))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: move ? -130 : 110, y: move ? 220 : 120)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
                move = true
            }
        }
    }
}

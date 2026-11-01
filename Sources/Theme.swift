import SwiftUI

struct Theme {
    static let primary = Color(red: 0.1, green: 0.4, blue: 0.8)
    static let secondary = Color(red: 0.9, green: 0.3, blue: 0.1)
    static let background = Color(red: 0.95, green: 0.95, blue: 0.97)
    static let cardBackground = Color.white
    
    static let gradient = LinearGradient(
        colors: [primary, Color(red: 0.2, green: 0.7, blue: 0.9)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                
                VStack(spacing: 25) {
                    // Header
                    VStack {
                        Text("مرحباً بك")
                            .font(.title2)
                            .foregroundColor(.gray)
                        Text("منتظر يسر جبار")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.primary)
                    }
                    .padding(.top, 40)
                    
                    // Main Cards
                    VStack(spacing: 20) {
                        NavigationLink(destination: Navigator()) {
                            HomeCard(title: "الخريطة والملاحة", icon: "map", color: Theme.primary)
                        }
                        
                        NavigationLink(destination: OfflineMapsSheet()) {
                            HomeCard(title: "تنزيل الخرائط", icon: "arrow.down.circle", color: Theme.secondary)
                        }
                        
                        NavigationLink(destination: ContentView()) {
                            HomeCard(title: "استيراد ملفات (LDK/MBTiles)", icon: "folder", color: .green)
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                }
            }
            .navigationBarHidden(true)
        }
    }
}

struct HomeCard: View {
    let title: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundColor(color)
                .frame(width: 60, height: 60)
                .background(color.opacity(0.1))
                .clipShape(Circle())
            
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            Spacer()
            
            Image(systemName: "chevron.left")
                .foregroundColor(.gray)
        }
        .padding()
        .background(Theme.cardBackground)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
}

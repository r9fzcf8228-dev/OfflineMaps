import SwiftUI

struct NavHUD: View {
    var isRecording: Bool
    var distance: Double
    var toggleAction: () -> Void
    
    var body: some View {
        VStack(spacing: 15) {
            // عرض المسافة
            HStack {
                VStack(alignment: .leading) {
                    Text("المسافة المقطوعة")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text(String(format: "%.2f كم", distance / 1000))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.primary)
                }
                Spacer()
            }
            
            // زر التسجيل
            Button(action: toggleAction) {
                HStack {
                    Image(systemName: isRecording ? "stop.circle.fill" : "play.circle.fill")
                    Text(isRecording ? "إيقاف التسجيل" : "بدء تسجيل المسار")
                        .fontWeight(.bold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(isRecording ? Color.red : Color.green)
                .cornerRadius(15)
                .shadow(radius: 5)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(25)
        .padding(.horizontal)
        .padding(.bottom, 20)
    }
}

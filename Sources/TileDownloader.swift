import SwiftUI

struct OfflineMapsSheet: View {
    @State private var minLat: String = ""
    @State private var maxLat: String = ""
    @State private var minLon: String = ""
    @State private var maxLon: String = ""
    @State private var isDownloading = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("إحداثيات المنطقة (Bounding Box)")) {
                    TextField("خط العرض الأدنى (Min Lat)", text: $minLat)
                    TextField("خط العرض الأعلى (Max Lat)", text: $maxLat)
                    TextField("خط الطول الأدنى (Min Lon)", text: $minLon)
                    TextField("خط الطول الأعلى (Max Lon)", text: $maxLon)
                }
                
                Section {
                    Button(action: {
                        // Start download logic here
                        isDownloading = true
                    }) {
                        HStack {
                            Spacer()
                            if isDownloading {
                                ProgressView()
                            } else {
                                Text("بدء التنزيل للعمل دون إنترنت")
                                    .fontWeight(.bold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isDownloading)
                }
            }
            .navigationTitle("تنزيل الخرائط")
        }
    }
}

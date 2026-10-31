import SwiftUI
import CoreLocation

struct ColorChoice: Identifiable {
    let id: String
    let title: String
}

let colorChoices: [ColorChoice] = [
    ColorChoice(id: "red", title: "أحمر"),
    ColorChoice(id: "blue", title: "أزرق"),
    ColorChoice(id: "green", title: "أخضر"),
    ColorChoice(id: "yellow", title: "أصفر"),
    ColorChoice(id: "orange", title: "برتقالي"),
    ColorChoice(id: "purple", title: "بنفسجي"),
    ColorChoice(id: "magenta", title: "وردي"),
    ColorChoice(id: "cyan", title: "سماوي"),
    ColorChoice(id: "black", title: "أسود"),
    ColorChoice(id: "gray", title: "رمادي")
]

struct PointEditor: View {
    @State private var p: MapPoint
    @State private var coordText: String
    @State private var mode: Int = 0          // 0 بدون رمز، 1 رمز قياسي، 2 رمز مخصص
    @State private var aff: Affiliation = .friendly
    @State private var type: UnitType = .infantry
    @State private var size: UnitSize = .unsized
    @State private var customNames: [String] = []
    @State private var customName: String = ""
    @State private var showSymPicker = false
    @State private var errorText = ""
    @State private var showError = false
    @Environment(\.dismiss) private var dismiss

    let isNew: Bool
    let onSave: (MapPoint) -> Void
    let onDelete: (() -> Void)?

    init(point: MapPoint, isNew: Bool,
         onSave: @escaping (MapPoint) -> Void,
         onDelete: (() -> Void)?) {
        _p = State(initialValue: point)
        _coordText = State(initialValue: Coords.mgrsString(point.coordinate))
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete

        if point.symbol.hasPrefix("img|") {
            _mode = State(initialValue: 2)
            _customName = State(initialValue: String(point.symbol.dropFirst(4)))
        } else if let parsed = MilSymbol.parse(point.symbol) {
            _mode = State(initialValue: 1)
            _aff = State(initialValue: parsed.0)
            _type = State(initialValue: parsed.1)
            _size = State(initialValue: parsed.2)
        }
        _customNames = State(initialValue: MilSymbol.customNames())
    }

    private var currentKey: String {
        if mode == 1 { return MilSymbol.key(aff, type, size) }
        if mode == 2 && !customName.isEmpty { return "img|" + customName }
        return ""
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("البيانات") {
                    TextField("الاسم", text: $p.name)
                    TextField("ملاحظة", text: $p.note)
                }

                Section("الإحداثيات (MGRS أو UTM أو عشري)") {
                    TextField("مثال: 38S MD 15154 71396", text: $coordText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    if let c = Coords.parse(coordText) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("UTM  " + Coords.utmString(c))
                            Text("MGRS " + Coords.mgrsString(c))
                            Text(Coords.ddString(c))
                        }
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                    } else {
                        Text("صيغة غير مفهومة")
                            .foregroundColor(.red)
                    }
                }

                Section("اللون") {
                    Picker("اللون", selection: $p.color) {
                        ForEach(colorChoices) { item in
                            Text(item.title).tag(item.id)
                        }
                    }
                }

                Section("الرمز") {
                    Picker("نوع الرمز", selection: $mode) {
                        Text("بدون").tag(0)
                        Text("قياسي").tag(1)
                        Text("مخصص").tag(2)
                    }
                    .pickerStyle(.segmented)

                    if mode == 1 {
                        Picker("الانتماء", selection: $aff) {
                            ForEach(Affiliation.allCases, id: \.self) { a in
                                Text(a.title).tag(a)
                            }
                        }
                        Picker("النوع", selection: $type) {
                            ForEach(UnitType.allCases, id: \.self) { t in
                                Text(t.title).tag(t)
                            }
                        }
                        Picker("الحجم", selection: $size) {
                            ForEach(UnitSize.allCases, id: \.self) { s in
                                Text(s.title).tag(s)
                            }
                        }
                    }

                    if mode == 2 {
                        if customNames.isEmpty {
                            Text("لا توجد رموز مخصصة. استورد صورة رمز.")
                                .foregroundColor(.secondary)
                        } else {
                            Picker("الرمز", selection: $customName) {
                                ForEach(customNames, id: \.self) { n in
                                    Text(n).tag(n)
                                }
                            }
                        }
                        Button("استيراد رمز من صورة") { showSymPicker = true }
                    }

                    if let img = MilSymbol.image(for: currentKey) {
                        HStack {
                            Spacer()
                            Image(uiImage: img)
                            Spacer()
                        }
                    }
                }

                if let del = onDelete {
                    Section {
                        Button("حذف النقطة", role: .destructive) {
                            del()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "نقطة جديدة" : "تعديل النقطة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") { save() }
                }
            }
            .alert(errorText, isPresented: $showError) {
                Button("OK", role: .cancel) {}
            }
            .sheet(isPresented: $showSymPicker) {
                DocPicker { urls in
                    showSymPicker = false
                    if let u = urls.first, let name = MilSymbol.saveCustom(from: u) {
                        customNames = MilSymbol.customNames()
                        customName = name
                        mode = 2
                    }
                }
            }
        }
    }

    private func save() {
        guard let c = Coords.parse(coordText) else {
            errorText = "الإحداثيات غير صحيحة"
            showError = true
            return
        }
        var out = p
        out.lat = c.latitude
        out.lon = c.longitude
        out.symbol = currentKey
        onSave(out)
        dismiss()
    }
}

struct GoToSheet: View {
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss
    let onGo: (CLLocationCoordinate2D) -> Void
    let onAdd: (CLLocationCoordinate2D) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("أدخل الإحداثيات (MGRS أو UTM أو عشري)") {
                    TextField("مثال: 38S MD 15154 71396", text: $text)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    if let c = Coords.parse(text) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("UTM  " + Coords.utmString(c))
                            Text("MGRS " + Coords.mgrsString(c))
                            Text(Coords.ddString(c))
                        }
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                    } else if !text.isEmpty {
                        Text("صيغة غير مفهومة")
                            .foregroundColor(.red)
                    }
                }

                if let c = Coords.parse(text) {
                    Section {
                        Button("انتقال وإسقاط علامة") {
                            onGo(c)
                            dismiss()
                        }
                        Button("إضافة كنقطة محفوظة") {
                            onAdd(c)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("إسقاط إحداثيات")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
            }
        }
    }
}

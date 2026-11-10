import SwiftUI
import VisionKit

/// Normalises a registration for matching: "ab12 cde" → "AB12CDE".
func normalisedReg(_ text: String) -> String {
    text.uppercased().filter { $0.isLetter || $0.isNumber }
}

/// Looks like a UK number plate (current, prefix, suffix and dateless styles), or a trailer ID.
func looksLikePlate(_ text: String) -> Bool {
    let t = normalisedReg(text)
    guard (4...8).contains(t.count), t.contains(where: \.isNumber), t.contains(where: \.isLetter) else { return false }
    let current = #"^[A-Z]{2}[0-9]{2}[A-Z]{3}$"#
    let prefix = #"^[A-Z][0-9]{1,3}[A-Z]{3}$"#
    let suffix = #"^[A-Z]{3}[0-9]{1,3}[A-Z]$"#
    return [current, prefix, suffix].contains { t.range(of: $0, options: .regularExpression) != nil } || t.count >= 5
}

/// Live camera text scanner that returns the first number plate it sees (or one you tap).
struct PlateScannerView: UIViewControllerRepresentable {
    var onFound: (String) -> Void

    static var isAvailable: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.text()], qualityLevel: .balanced,
                                           recognizesMultipleItems: true, isHighFrameRateTrackingEnabled: false,
                                           isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (String) -> Void
        private var done = false
        init(onFound: @escaping (String) -> Void) { self.onFound = onFound }

        private func check(_ items: [RecognizedItem]) {
            guard !done else { return }
            for item in items {
                if case .text(let text) = item {
                    let t = normalisedReg(text.transcript)
                    // Auto-accept only a strict UK plate; anything else needs a tap.
                    if t.range(of: #"^[A-Z]{2}[0-9]{2}[A-Z]{3}$"#, options: .regularExpression) != nil {
                        done = true
                        onFound(t)
                        return
                    }
                }
            }
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            check(addedItems)
        }

        func dataScanner(_ scanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            guard !done, case .text(let text) = item, looksLikePlate(text.transcript) else { return }
            done = true
            onFound(normalisedReg(text.transcript))
        }
    }
}

/// Sheet: scan a plate, or type it.
struct PlateScanSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onFound: (String) -> Void
    @State private var typed = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if PlateScannerView.isAvailable {
                    PlateScannerView { reg in
                        onFound(reg)
                        dismiss()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .frame(maxHeight: 360)
                    Text("Point the camera at the number plate. Tap the text if it isn't picked up automatically.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                } else {
                    ContentUnavailableView("Camera scanning isn't available", systemImage: "camera",
                                           description: Text("Type the registration below instead."))
                }
                HStack {
                    TextField("Or type the registration", text: $typed)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.done)
                        .onSubmit(useTyped)
                    Button("Use", action: useTyped).buttonStyle(.borderedProminent).disabled(normalisedReg(typed).count < 2)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Find vehicle by plate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func useTyped() {
        let reg = normalisedReg(typed)
        guard reg.count >= 2 else { return }
        onFound(reg)
        dismiss()
    }
}

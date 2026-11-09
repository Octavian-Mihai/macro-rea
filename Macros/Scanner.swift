import SwiftUI
import AVFoundation

struct ScannerSheet: View {
    var onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var manual = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                #if targetEnvironment(simulator)
                Text("Camera isn't available in the simulator.").foregroundStyle(.secondary).padding(.top)
                #else
                CameraScanner(onCode: onCode).clipShape(RoundedRectangle(cornerRadius: 16)).padding()
                #endif
                HStack {
                    TextField("Or type barcode", text: $manual).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                    Button("Look up") { if !manual.isEmpty { onCode(manual) } }.buttonStyle(.borderedProminent)
                }.padding(.horizontal)
                Spacer(minLength: 0)
            }
            .navigationTitle("Scan barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

struct CameraScanner: UIViewControllerRepresentable {
    var onCode: (String) -> Void
    func makeUIViewController(context: Context) -> ScannerVC { let v = ScannerVC(); v.onCode = onCode; return v }
    func updateUIViewController(_ vc: ScannerVC, context: Context) {}
}

final class ScannerVC: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var done = false

    override func viewDidLoad() {
        super.viewDidLoad()
        AVCaptureDevice.requestAccess(for: .video) { ok in
            guard ok else { return }
            DispatchQueue.main.async { self.setup() }
        }
    }

    private func setup() {
        guard let dev = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: dev),
              session.canAddInput(input) else { return }
        session.addInput(input)
        let out = AVCaptureMetadataOutput()
        guard session.canAddOutput(out) else { return }
        session.addOutput(out)
        out.setMetadataObjectsDelegate(self, queue: .main)
        out.metadataObjectTypes = [.ean13, .ean8, .upce, .code128]
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        preview = layer
        DispatchQueue.global().async { self.session.startRunning() }
    }

    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); session.stopRunning() }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objs: [AVMetadataObject], from: AVCaptureConnection) {
        guard !done, let code = (objs.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        done = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onCode?(code)
    }
}

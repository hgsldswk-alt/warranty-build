import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct CaptureView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = Camera()
    @State private var picks: [PhotosPickerItem] = []
    @State private var files = false

    private var fake: Bool { Launch.testing || !Camera.available }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.shareBack, Theme.camera], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                HStack {
                    Button { model.route = nil } label: {
                        Label(L.t("action.cancel"), systemImage: "xmark").labelStyle(.iconOnly)
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.12), in: Circle())
                            .contentShape(Circle())
                    }.buttonStyle(.plain).foregroundStyle(.white).testID("camera.cancel")
                    Spacer()
                    PhotosPicker(selection: $picks, maxSelectionCount: 3, matching: .images) {
                        cameraTool("photo.on.rectangle")
                    }.buttonStyle(.plain)
                        .accessibilityLabel(L.t("camera.library")).testID("camera.library")
                    Button { files = true } label: { cameraTool("doc") }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L.t("camera.files")).testID("camera.files")
                }
                ZStack {
                    Theme.camera
                    if fake {
                        Image(uiImage: FakeReceipt.image).resizable().scaledToFit().padding(30).rotationEffect(.degrees(-3))
                    } else if camera.denied {
                        VStack(spacing: 10) {
                            EmptyIllustration(icon: "camera.fill")
                            Text(L.t("camera.denied")).font(.subheadline).foregroundStyle(Theme.muted)
                                .multilineTextAlignment(.center)
                            Button {
                                if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                            } label: {
                                PrimaryButtonLabel(title: L.t("camera.openSettings"), icon: "gearshape")
                            }.buttonStyle(.plain)
                        }.card().padding(12).accessibilityElement(children: .contain).testID("camera.denied")
                    } else {
                        CameraPreview(session: camera.session)
                    }
                    if fake || !camera.denied {
                        Corners().stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .padding(26).allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(.white.opacity(0.14)).allowsHitTesting(false)
                }
                Text(L.t("camera.hint")).font(.footnote).foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center)
                Button {
                    if fake { Task { await model.captured([FakeReceipt.image]) } }
                    else { camera.shoot { img in Task { await model.captured([img]) } } }
                } label: {
                    Circle().strokeBorder(.white, lineWidth: 3).frame(width: 72, height: 72)
                        .background {
                            Circle().fill(Theme.accent).padding(7)
                        }
                        .overlay {
                            if model.busy { ProgressView().tint(.white) }
                            else { Image(systemName: "camera.fill").font(.title3.weight(.semibold)).foregroundStyle(.white) }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .opacity(!fake && camera.denied ? 0.5 : 1)
                .disabled(model.busy || (!fake && camera.denied))
                .accessibilityLabel(L.t("camera.shutter")).testID("camera.shutter")
            }
            .padding(.horizontal, 16).padding(.bottom, 10)
        }
        .preferredColorScheme(.dark)
        .task { if !fake { await camera.start() } }
        .onDisappear { camera.stop() }
        .onChange(of: picks) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var images: [UIImage] = []
                for i in items {
                    if let d = try? await i.loadTransferable(type: Data.self), let img = UIImage(data: d) { images.append(img) }
                }
                picks = []
                if images.isEmpty { model.notice = WarrantyError.unreadable.message } else { await model.captured(images) }
            }
        }
        .fileImporter(isPresented: $files, allowedContentTypes: [.pdf, .image]) { result in
            guard case .success(let url) = result else { return }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            let img = url.pathExtension.lowercased() == "pdf" ? PDFThumb.image(url) : UIImage(contentsOfFile: url.path)
            if let img { Task { await model.captured([img]) } } else { model.notice = WarrantyError.unreadable.message }
        }
    }

    private func cameraTool(_ icon: String) -> some View {
        Image(systemName: icon).font(.title3.weight(.semibold)).foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(.white.opacity(0.12), in: Circle())
            .contentShape(Circle())
    }
}

private struct Corners: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let l: CGFloat = 30
        for (x, y, dx, dy) in [(r.minX, r.minY, 1.0, 1.0), (r.maxX, r.minY, -1.0, 1.0), (r.minX, r.maxY, 1.0, -1.0), (r.maxX, r.maxY, -1.0, -1.0)] {
            p.move(to: CGPoint(x: x + dx * l, y: y)); p.addLine(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x, y: y + dy * l))
        }
        return p
    }
}

@MainActor
final class Camera: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    static var available: Bool { AVCaptureDevice.default(for: .video) != nil }
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    @Published var denied = false
    private var done: ((UIImage) -> Void)?

    func start() async {
        var ok = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined { ok = await AVCaptureDevice.requestAccess(for: .video) }
        guard ok else { denied = true; return }
        guard session.inputs.isEmpty, let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        let s = session
        DispatchQueue.global(qos: .userInitiated).async { s.startRunning() }
    }

    func stop() {
        let s = session
        DispatchQueue.global(qos: .utility).async { if s.isRunning { s.stopRunning() } }
    }

    func shoot(_ done: @escaping (UIImage) -> Void) {
        self.done = done
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(), let img = UIImage(data: data) else { return }
        Task { @MainActor in self.done?(img); self.done = nil }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.layer.session = session
        v.layer.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        override var layer: AVCaptureVideoPreviewLayer { super.layer as! AVCaptureVideoPreviewLayer }
    }
}

enum FakeReceipt {
    static let image: UIImage = {
        let size = CGSize(width: 600, height: 900)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(red: 0.985, green: 0.98, blue: 0.965, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let lines = ["COSTCO WHOLESALE", "", "BOSCH DISHWASHER", "SHPM65Z55N", "", "SUBTOTAL     849.99", "TAX           69.12",
                         "TOTAL        919.11", "", "12/08/2024  14:32", "THANK YOU"]
            let font = UIFont.monospacedSystemFont(ofSize: 34, weight: .semibold)
            for (i, t) in lines.enumerated() {
                (t as NSString).draw(at: CGPoint(x: 50, y: 60 + CGFloat(i) * 70),
                                     withAttributes: [.font: font, .foregroundColor: UIColor(white: 0.15, alpha: 1)])
            }
        }
    }()
}

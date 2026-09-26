import SudokuCore
import SwiftUI
import UIKit

/// 標準のカメラで1枚撮影する(実機のみ)。シャッターは手動。
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (CGImage) -> Void
    let onCancel: () -> Void

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = (info[.originalImage] as? UIImage)?.uprightCGImage {
                parent.onImage(image)
            } else {
                parent.onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.onCancel() }
    }
}

extension UIImage {
    /// 向き情報を反映した CGImage(cgImage をそのまま使うと横向きになることがある)。
    var uprightCGImage: CGImage? {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        // 大きすぎる写真は縮小(認識には 2000px 程度で十分)
        let longest = max(size.width, size.height)
        let ratio = min(1, 2000 / longest)
        let target = CGSize(width: size.width * ratio, height: size.height * ratio)
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }.cgImage
    }
}

/// 読み取る前に、盤面の四隅を写真の上で合わせる画面。
/// 開いた時点で自動検出した四隅を置くので、ずれているときだけ動かせばよい。
struct CornerEditorView: View {
    let image: CGImage
    let onCancel: () -> Void
    let onConfirm: (BoardRecognizer.Quad) -> Void

    @State private var quad = BoardRecognizer.Quad.inset
    @State private var isDetecting = true
    @State private var detectedNote: String?
    @State private var activeCorner: Int?

    private var uiImage: UIImage { UIImage(cgImage: image) }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("四隅を合わせる")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("キャンセル", action: onCancel) }
                }
        }
    }

    private var content: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("四隅を盤面の外枠に合わせてください")
                    .font(.headline)
                Text("黄色いL字の頂点(赤い点)を、盤面の外枠の角(線が交わる点)に合わせます。ぴったり、またはほんの少し外側が最適です。枠の内側に入らないようにしてください。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let detectedNote {
                    Text(detectedNote).font(.footnote).foregroundStyle(.blue)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)

            GeometryReader { geo in
                let fit = fittedSize(in: geo.size)
                ZStack {
                    Image(uiImage: uiImage).resizable().frame(width: fit.width, height: fit.height)
                    outline(in: fit)
                    ForEach(0..<4, id: \.self) { i in handle(i, in: fit) }
                    if let i = activeCorner { loupe(for: i, in: fit) }
                }
                .frame(width: fit.width, height: fit.height)
                .coordinateSpace(name: "photo")
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            .padding(.horizontal, 8)
            .overlay { if isDetecting { ProgressView("盤面を探しています…") } }

            HStack {
                Button("自動で合わせる") { detect() }.buttonStyle(.bordered).disabled(isDetecting)
                Button("読み取る") { onConfirm(quad) }.buttonStyle(.borderedProminent).disabled(isDetecting)
            }
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .background(Color(.systemBackground).ignoresSafeArea())
        .task { detect() }
    }

    // MARK: 描画

    private func fittedSize(in available: CGSize) -> CGSize {
        let aspect = CGFloat(image.width) / CGFloat(image.height)
        var w = available.width, h = w / aspect
        if h > available.height { h = available.height; w = h * aspect }
        return CGSize(width: w, height: h)
    }

    private func point(_ i: Int, in fit: CGSize) -> CGPoint {
        let p = corners[i]
        return CGPoint(x: p.x * fit.width, y: p.y * fit.height)
    }

    private var corners: [CGPoint] { [quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft] }

    private func setCorner(_ i: Int, to p: CGPoint) {
        let c = CGPoint(x: min(1, max(0, p.x)), y: min(1, max(0, p.y)))
        switch i {
        case 0: quad.topLeft = c
        case 1: quad.topRight = c
        case 2: quad.bottomRight = c
        default: quad.bottomLeft = c
        }
    }

    private func outline(in fit: CGSize) -> some View {
        Path { path in
            path.move(to: point(0, in: fit))
            for i in 1..<4 { path.addLine(to: point(i, in: fit)) }
            path.closeSubpath()
        }
        .stroke(Color.yellow, lineWidth: 1.5)
        .allowsHitTesting(false)
    }

    private static let cornerNames = ["左上", "右上", "右下", "左下"]

    /// 角の位置に合わせるL字の印。頂点(中心)が四隅の位置で、腕が盤面の内側へ伸びる。
    /// 実際の盤面の外枠の角(線が交わる点)を、この頂点に重ねる。
    private func bracket(_ i: Int, arm: CGFloat) -> Path {
        let dx: CGFloat = (i == 0 || i == 3) ? 1 : -1      // 右へ / 左へ
        let dy: CGFloat = (i == 0 || i == 1) ? 1 : -1      // 下へ / 上へ
        return Path { p in
            p.move(to: CGPoint(x: arm * dx, y: 0)); p.addLine(to: .zero); p.addLine(to: CGPoint(x: 0, y: arm * dy))
        }
    }

    private func handle(_ i: Int, in fit: CGSize) -> some View {
        let at = point(i, in: fit)
        return ZStack {
            Color.clear.frame(width: 64, height: 64).contentShape(Circle())      // 指で掴みやすい当たり判定
            bracket(i, arm: 26).stroke(Color.yellow, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .offset(x: 32, y: 32).frame(width: 64, height: 64, alignment: .topLeading)
            Circle().fill(Color.red).frame(width: 6, height: 6)                  // ここが実際の位置
            Text(Self.cornerNames[i])
                .font(.caption2.weight(.bold)).padding(.horizontal, 5).padding(.vertical, 1)
                .background(Color.yellow, in: Capsule()).foregroundStyle(.black)
                .offset(x: (i == 0 || i == 3) ? -26 : 26, y: (i == 0 || i == 1) ? -22 : 22)
        }
        .frame(width: 64, height: 64)
        .position(at)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("photo"))
                .onChanged { v in
                    activeCorner = i
                    setCorner(i, to: CGPoint(x: v.location.x / fit.width, y: v.location.y / fit.height))
                }
                .onEnded { _ in activeCorner = nil }
        )
    }

    /// ドラッグ中の角の周りを拡大して見せる。中央の印に、盤面の外枠の角を重ねる。
    private func loupe(for i: Int, in fit: CGSize) -> some View {
        let zoom: CGFloat = 3.5, size: CGFloat = 130
        let p = point(i, in: fit)
        let onLeft = p.x < fit.width / 2
        let center = CGPoint(x: onLeft ? fit.width - size / 2 - 8 : size / 2 + 8, y: size / 2 + 8)
        return ZStack {
            Image(uiImage: uiImage).resizable()
                .frame(width: fit.width * zoom, height: fit.height * zoom)
                .offset(x: (fit.width / 2 - p.x) * zoom, y: (fit.height / 2 - p.y) * zoom)
            // 十字線と、角の位置を示すL字
            Path { path in
                path.move(to: CGPoint(x: size / 2, y: 0)); path.addLine(to: CGPoint(x: size / 2, y: size))
                path.move(to: CGPoint(x: 0, y: size / 2)); path.addLine(to: CGPoint(x: size, y: size / 2))
            }
            .stroke(Color.yellow.opacity(0.35), lineWidth: 1)
            bracket(i, arm: 34).stroke(Color.yellow, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .offset(x: size / 2, y: size / 2).frame(width: size, height: size, alignment: .topLeading)
            Circle().fill(Color.red).frame(width: 5, height: 5)
            VStack {
                Spacer()
                Text("\(Self.cornerNames[i])の角を合わせる")
                    .font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.black.opacity(0.65), in: Capsule()).foregroundStyle(.white)
                    .padding(.bottom, 6)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white, lineWidth: 2))
        .shadow(radius: 3)
        .position(center)
        .allowsHitTesting(false)
    }

    // MARK: 自動検出

    private func detect() {
        isDetecting = true
        let image = image
        Task {
            let found = await Task.detached(priority: .userInitiated) { BoardRecognizer.detectQuad(in: image) }.value
            if let found {
                quad = found
                detectedNote = "盤面を自動で見つけました。ずれていたら動かしてください。"
            } else {
                quad = .inset
                detectedNote = "盤面を自動で見つけられませんでした。四隅を手で合わせてください。"
            }
            isDetecting = false
        }
    }
}

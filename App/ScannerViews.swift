import PhotosUI
import SwiftUI
import VisionKit

/// カメラで書類(数独のページ)をスキャンする。実機のみ。
struct CameraScanner: UIViewControllerRepresentable {
    let onImage: (CGImage) -> Void

    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onImage: (CGImage) -> Void
        init(onImage: @escaping (CGImage) -> Void) { self.onImage = onImage }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            controller.dismiss(animated: true)
            if scan.pageCount > 0, let cg = scan.imageOfPage(at: 0).uprightCGImage { onImage(cg) }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            controller.dismiss(animated: true)
        }
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

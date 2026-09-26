#if canImport(Vision) && canImport(CoreImage)
import CoreGraphics
import CoreImage
import CoreText
import Foundation
import Vision

/// 数独の写真から盤面を読み取る。
/// 盤面の四角形を検出 → 真上から見た正方形に補正 → 81マスに分割 → マスごとに数字を認識。
public enum BoardRecognizer {
    static let side = 900

    public static func recognize(_ image: CGImage) -> Board {
        let grid = rectify(image)
        let bounds = gridBounds(in: grid)
        let cw = bounds.width / 9, ch = bounds.height / 9
        var cells = [Int](repeating: 0, count: 81)
        for r in 0..<9 {
            for c in 0..<9 {
                let rect = CGRect(x: bounds.minX + (CGFloat(c) + 0.14) * cw,
                                  y: bounds.minY + (CGFloat(r) + 0.14) * ch,
                                  width: cw * 0.72, height: ch * 0.72).integral
                if let crop = grid.cropping(to: rect) { cells[r * 9 + c] = recognizeDigit(crop) }
            }
        }
        return Board(cells: cells)
    }

    /// 補正後の画像の中で、外枠の線が実際にある範囲を求める。
    /// 罫線は行・列いっぱいに暗いので、暗い画素の割合が高い最初と最後の行/列を外枠とみなす。
    static func gridBounds(in image: CGImage) -> CGRect {
        let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let w = image.width, h = image.height
        var buf = [UInt8](repeating: 0, count: w * h)
        buf.withUnsafeMutableBytes { ptr in
            let ctx = CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            ctx.draw(image, in: full)
        }
        let lo = Int(buf.min()!), hi = Int(buf.max()!)
        guard hi - lo > 60 else { return full }
        let threshold = (lo + hi) / 2
        var rowDark = [Int](repeating: 0, count: h), colDark = [Int](repeating: 0, count: w)
        for y in 0..<h {
            for x in 0..<w where Int(buf[y * w + x]) < threshold { rowDark[y] += 1; colDark[x] += 1 }
        }
        // 補正で生じる画像の縁の黒い線を拾わないよう、端の数ピクセルは無視する
        let edge = 4
        let rows = (edge..<(h - edge)).filter { Double(rowDark[$0]) > 0.45 * Double(w) }
        let cols = (edge..<(w - edge)).filter { Double(colDark[$0]) > 0.45 * Double(h) }
        guard let top = rows.first, let bottom = rows.last, let left = cols.first, let right = cols.last,
              bottom - top > h / 2, right - left > w / 2 else { return full }
        return CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
    }

    // MARK: 盤面の検出と補正

    static func rectify(_ image: CGImage) -> CGImage {
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.7
        request.maximumAspectRatio = 1.0
        request.minimumSize = 0.3
        request.minimumConfidence = 0.5
        request.quadratureTolerance = 30
        request.maximumObservations = 8
        try? VNImageRequestHandler(cgImage: image).perform([request])

        guard let obs = request.results?.max(by: { area($0) < area($1) }) else {
            return resized(image)
        }
        let w = CGFloat(image.width), h = CGFloat(image.height)
        func vec(_ p: CGPoint) -> CIVector { CIVector(x: p.x * w, y: p.y * h) }
        let filter = CIFilter(name: "CIPerspectiveCorrection")!
        filter.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
        filter.setValue(vec(obs.topLeft), forKey: "inputTopLeft")
        filter.setValue(vec(obs.topRight), forKey: "inputTopRight")
        filter.setValue(vec(obs.bottomLeft), forKey: "inputBottomLeft")
        filter.setValue(vec(obs.bottomRight), forKey: "inputBottomRight")
        guard let out = filter.outputImage,
              let cg = CIContext().createCGImage(out, from: out.extent) else {
            return resized(image)
        }
        return resized(cg)
    }

    private static func area(_ o: VNRectangleObservation) -> CGFloat {
        o.boundingBox.width * o.boundingBox.height
    }

    /// side x side の正方形にリサイズ。
    private static func resized(_ image: CGImage) -> CGImage {
        let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return ctx.makeImage()!
    }

    // MARK: マスごとの認識

    static func recognizeDigit(_ crop: CGImage) -> Int {
        guard var mask = inkMask(of: crop) else { return 0 }
        removeBorderInk(&mask)
        guard let feature = DigitClassifier.feature(of: mask) else { return 0 }   // 空きマス
        return DigitClassifier.classify(feature)
    }

    /// 二値化したインクのマスク(暗い=true)。コントラストが低ければ nil(空白)。
    static func inkMask(of image: CGImage) -> Mask? {
        let w = image.width, h = image.height
        var buf = [UInt8](repeating: 0, count: w * h)
        buf.withUnsafeMutableBytes { ptr in
            let ctx = CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        let lo = Int(buf.min()!), hi = Int(buf.max()!)
        guard hi - lo > 60 else { return nil }
        let threshold = (lo + hi) / 2
        return Mask(width: w, height: h, ink: buf.map { Int($0) < threshold })
    }

    /// 枠に触れているインク(隣のマスの罫線の切れ端など)を消す。
    static func removeBorderInk(_ m: inout Mask) {
        var stack: [Int] = []
        for x in 0..<m.width { stack.append(x); stack.append((m.height - 1) * m.width + x) }
        for y in 0..<m.height { stack.append(y * m.width); stack.append(y * m.width + m.width - 1) }
        while let i = stack.popLast() {
            guard m.ink[i] else { continue }
            m.ink[i] = false
            let x = i % m.width, y = i / m.width
            if x > 0 { stack.append(i - 1) }
            if x < m.width - 1 { stack.append(i + 1) }
            if y > 0 { stack.append(i - m.width) }
            if y < m.height - 1 { stack.append(i + m.width) }
        }
    }

    /// OCR の文字列を 1-9 に変換(Vision の出力など向けの補助)。
    static func digit(from string: String) -> Int? {
        let s = string.filter { !$0.isWhitespace }
        guard s.count == 1, let d = s.first?.wholeNumberValue, (1...9).contains(d) else { return nil }
        return d
    }
}

struct Mask {
    var width: Int
    var height: Int
    var ink: [Bool]
}

/// フォントから作ったテンプレートとの照合による、印刷数字の分類器。
enum DigitClassifier {
    static let fw = 20, fh = 28   // 特徴量のサイズ(高さを揃えて幅は比率どおり)

    static let templates: [(digit: Int, feature: [Float])] = {
        let names = ["Helvetica", "Helvetica-Bold", "HelveticaNeue", "HelveticaNeue-Medium", "ArialMT", "Arial-BoldMT",
                     "TimesNewRomanPSMT", "TimesNewRomanPS-BoldMT", "Georgia", "Georgia-Bold", "Verdana",
                     "Courier", "Courier-Bold", "AvenirNext-Regular", "AvenirNext-DemiBold", "Menlo-Regular",
                     "Futura-Medium", "GillSans", "TrebuchetMS"]
        var fonts = names.map { CTFontCreateWithName($0 as CFString, 140, nil) }
        fonts.append(CTFontCreateUIFontForLanguage(.system, 140, nil)!)
        var result: [(Int, [Float])] = []
        for font in fonts {
            for d in 1...9 {
                let n = 220
                var buf = [UInt8](repeating: 255, count: n * n)
                buf.withUnsafeMutableBytes { ptr in
                    let ctx = CGContext(data: ptr.baseAddress, width: n, height: n, bitsPerComponent: 8,
                                        bytesPerRow: n, space: CGColorSpaceCreateDeviceGray(),
                                        bitmapInfo: CGImageAlphaInfo.none.rawValue)!
                    let attr = NSAttributedString(string: "\(d)", attributes: [
                        NSAttributedString.Key(kCTFontAttributeName as String): font,
                        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)])
                    let line = CTLineCreateWithAttributedString(attr)
                    let b = CTLineGetBoundsWithOptions(line, [])
                    ctx.textPosition = CGPoint(x: CGFloat(n) / 2 - b.width / 2 - b.minX,
                                               y: CGFloat(n) / 2 - b.height / 2 - b.minY)
                    CTLineDraw(line, ctx)
                }
                let mask = Mask(width: n, height: n, ink: buf.map { $0 < 128 })
                if let f = feature(of: mask, minHeightRatio: 0) { result.append((d, f)) }
            }
        }
        return result
    }()

    /// マスクから特徴量を作る。数字が小さすぎる(=空白)場合は nil。
    static func feature(of m: Mask, minHeightRatio: Double = 0.3) -> [Float]? {
        var minX = m.width, maxX = -1, minY = m.height, maxY = -1, dark = 0
        for y in 0..<m.height {
            for x in 0..<m.width where m.ink[y * m.width + x] {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
                dark += 1
            }
        }
        guard maxX >= 0 else { return nil }
        let bw = maxX - minX + 1, bh = maxY - minY + 1
        guard Double(bh) >= minHeightRatio * Double(m.height), dark >= 8 else { return nil }

        // 高さを fh に揃え、幅は比率どおり(最大 fw)。中央に置く。
        let scale = min(Double(fh) / Double(bh), Double(fw) / Double(bw))
        let placedW = Double(bw) * scale, placedH = Double(bh) * scale
        let offX = (Double(fw) - placedW) / 2, offY = (Double(fh) - placedH) / 2
        var out = [Float](repeating: 0, count: fw * fh)
        for oy in 0..<fh {
            for ox in 0..<fw {
                // 出力画素に対応する元画像の領域を平均
                let sx0 = Double(minX) + (Double(ox) - offX) / scale, sx1 = Double(minX) + (Double(ox + 1) - offX) / scale
                let sy0 = Double(minY) + (Double(oy) - offY) / scale, sy1 = Double(minY) + (Double(oy + 1) - offY) / scale
                let x0 = max(Int(sx0.rounded(.down)), minX), x1 = min(Int(sx1.rounded(.up)), maxX + 1)
                let y0 = max(Int(sy0.rounded(.down)), minY), y1 = min(Int(sy1.rounded(.up)), maxY + 1)
                guard x0 < x1, y0 < y1 else { continue }
                var sum = 0
                for y in y0..<y1 { for x in x0..<x1 where m.ink[y * m.width + x] { sum += 1 } }
                out[oy * fw + ox] = Float(sum) / Float((x1 - x0) * (y1 - y0))
            }
        }
        return blur(out)
    }

    private static func blur(_ f: [Float]) -> [Float] {
        var out = [Float](repeating: 0, count: f.count)
        for y in 0..<fh {
            for x in 0..<fw {
                var sum: Float = 0, n: Float = 0
                for dy in -1...1 { for dx in -1...1 {
                    let xx = x + dx, yy = y + dy
                    if xx >= 0, xx < fw, yy >= 0, yy < fh { sum += f[yy * fw + xx]; n += 1 }
                } }
                out[y * fw + x] = sum / n
            }
        }
        return out
    }

    /// 最も近いテンプレートの数字を返す。
    static func classify(_ f: [Float]) -> Int {
        var best = 0, bestDist = Float.greatestFiniteMagnitude
        for t in templates {
            var d: Float = 0
            for i in 0..<f.count { let e = f[i] - t.feature[i]; d += e * e }
            if d < bestDist { bestDist = d; best = t.digit }
        }
        return best
    }
}
#endif

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

    /// 盤面の四隅。画像の左上を原点とした 0...1 の座標(画面に重ねて表示・編集しやすい形)。
    public struct Quad: Equatable, Sendable {
        public var topLeft, topRight, bottomRight, bottomLeft: CGPoint
        public init(topLeft: CGPoint, topRight: CGPoint, bottomRight: CGPoint, bottomLeft: CGPoint) {
            self.topLeft = topLeft; self.topRight = topRight
            self.bottomRight = bottomRight; self.bottomLeft = bottomLeft
        }
        /// 画像の中央寄りの既定の四角(盤面が見つからないときの初期値)。
        public static let inset = Quad(topLeft: CGPoint(x: 0.1, y: 0.1), topRight: CGPoint(x: 0.9, y: 0.1),
                                       bottomRight: CGPoint(x: 0.9, y: 0.9), bottomLeft: CGPoint(x: 0.1, y: 0.9))
    }

    /// 写真から盤面を読み取る。`quad` を渡すと、その四隅を盤面の外枠として使う(少し大きめでも絞り込む)。
    /// 渡さなければ自動で盤面を探す。
    public static func recognize(_ image: CGImage, quad: Quad? = nil) -> Board {
        recognizeDetailed(image, quad: quad).board
    }

    public typealias Candidate = DigitCandidate

    /// 読み取り結果に加えて、判定に自信のないマス(確認を促したいマス)の番号(0..<81)を返す。
    /// alternatives は、数字を読み取った各マスの次点の候補(誤読の自動補正に使う)。
    public static func recognizeDetailed(_ image: CGImage, quad: Quad? = nil)
        -> (board: Board, uncertain: Set<Int>, alternatives: [Int: [Candidate]]) {
        let grid = quad.map { rectify(image, using: $0) } ?? rectify(image)
        return read(grid)
    }

    /// 自動で見つけた盤面の四隅。盤面らしい四角が見つからなければ nil。
    public static func detectQuad(in image: CGImage) -> Quad? {
        let flat = normalized(image)
        guard let best = bestCandidate(original: image, flat: flat), best.score > 0.3, let obs = best.observation
        else { return nil }
        func p(_ v: CGPoint) -> CGPoint { CGPoint(x: v.x, y: 1 - v.y) }   // Vision は左下原点
        return Quad(topLeft: p(obs.topLeft), topRight: p(obs.topRight),
                    bottomRight: p(obs.bottomRight), bottomLeft: p(obs.bottomLeft))
    }

    /// 補正後の正方形の画像から、81マスを読む。
    static func read(_ grid: CGImage) -> (board: Board, uncertain: Set<Int>, alternatives: [Int: [Candidate]]) {
        let bounds = gridBounds(in: grid)
        let (xs, ys) = gridLines(in: grid, bounds: bounds)
        var cells = [Int](repeating: 0, count: 81)
        var uncertain = Set<Int>()
        var alternatives: [Int: [Candidate]] = [:]
        for r in 0..<9 {
            for c in 0..<9 {
                let cw = xs[c + 1] - xs[c], ch = ys[r + 1] - ys[r]
                let rect = CGRect(x: xs[c] + 0.14 * cw, y: ys[r] + 0.14 * ch,
                                  width: cw * 0.72, height: ch * 0.72).integral
                guard let crop = grid.cropping(to: rect) else { continue }
                let result = recognizeDigitDetailed(crop)
                cells[r * 9 + c] = result.digit
                if result.uncertain { uncertain.insert(r * 9 + c) }
                if !result.alternatives.isEmpty { alternatives[r * 9 + c] = result.alternatives }
            }
        }
        return (Board(cells: cells), uncertain, alternatives)
    }

    /// 縦横の罫線(各10本)の実際の位置。9等分の位置の近くにある罫線に合わせるので、
    /// 補正が少しずれていても(手前側が大きく写る斜めの写真など)マスを正しく切り出せる。
    static func gridLines(in image: CGImage, bounds: CGRect) -> (xs: [CGFloat], ys: [CGFloat]) {
        let w = image.width, h = image.height
        var buf = [UInt8](repeating: 0, count: w * h)
        buf.withUnsafeMutableBytes { ptr in
            let ctx = CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        let uniformX = (0...9).map { bounds.minX + CGFloat($0) * (bounds.width - 1) / 9 }
        let uniformY = (0...9).map { bounds.minY + CGFloat($0) * (bounds.height - 1) / 9 }
        let lo = Int(buf.min()!), hi = Int(buf.max()!)
        guard hi - lo > 60 else { return (uniformX, uniformY) }
        let threshold = lo + (hi - lo) * 3 / 4
        var rowDark = [Double](repeating: 0, count: h), colDark = [Double](repeating: 0, count: w)
        for y in 0..<h {
            for x in 0..<w where Int(buf[y * w + x]) < threshold { rowDark[y] += 1 / Double(w); colDark[x] += 1 / Double(h) }
        }
        func snap(_ expected: [CGFloat], _ profile: [Double]) -> [CGFloat] {
            let cell = (expected[9] - expected[0]) / 9
            let reach = Int(cell * 0.3)
            var out = expected
            // 外枠(0本目と9本目)は外枠検出の結果をそのまま使う。画像の端に出る暗い縁を罫線と取り違えないため。
            for i in 1..<9 {
                let c = Int(expected[i].rounded())
                let range = max(0, c - reach)...min(profile.count - 1, c + reach)
                guard let peak = range.max(by: { profile[$0] < profile[$1] }), profile[peak] > 0.25 else { continue }
                // 太い線でも中心に寄せるため、ピークの近くで十分暗い位置の重心を使う
                let near = max(0, peak - 6)...min(profile.count - 1, peak + 6)
                let strong = near.filter { profile[$0] >= profile[peak] * 0.8 }
                out[i] = CGFloat(strong.reduce(0, +)) / CGFloat(strong.count) + 0.5
            }
            // 順序が崩れる、間隔が極端にずれるなど不自然なら、9等分のままにする
            for i in 0..<9 where out[i + 1] - out[i] < cell * 0.6 || out[i + 1] - out[i] > cell * 1.4 { return expected }
            return out
        }
        return (snap(uniformX, colDark), snap(uniformY, rowDark))
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
        // 補正で細く薄くなった罫線も拾えるよう、暗さのしきい値は明るい側に寄せる
        let threshold = lo + (hi - lo) * 3 / 4
        var rowDark = [Int](repeating: 0, count: h), colDark = [Int](repeating: 0, count: w)
        for y in 0..<h {
            for x in 0..<w where Int(buf[y * w + x]) < threshold { rowDark[y] += 1; colDark[x] += 1 }
        }
        // 補正で生じる画像の縁の黒い線を拾わないよう、端の数ピクセルは無視する
        let edge = 4
        let rows = (edge..<(h - edge)).filter { Double(rowDark[$0]) > 0.3 * Double(w) }
        let cols = (edge..<(w - edge)).filter { Double(colDark[$0]) > 0.3 * Double(h) }
        guard let top = rows.first, let bottom = rows.last, let left = cols.first, let right = cols.last,
              bottom - top > h / 2, right - left > w / 2 else { return full }
        return CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
    }

    // MARK: 盤面の検出と補正

    static let maxDimension = 1600
    private static let ciContext = CIContext()
    /// 指定された四隅を外へ広げる割合。
    private static let quadMargin: CGFloat = 0.05

    /// 影や照明のムラを取り除いたグレー画像を作る(各画素を推定した背景の明るさで割って揃える)。
    static func normalized(_ image: CGImage) -> CGImage {
        let scale = min(1, CGFloat(maxDimension) / CGFloat(max(image.width, image.height)))
        let w = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let h = max(1, Int((CGFloat(image.height) * scale).rounded()))
        var buf = [UInt8](repeating: 0, count: w * h)
        buf.withUnsafeMutableBytes { ptr in
            let ctx = CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        // 背景(紙の明るさ)を、縮小画像に対するクロージング(最大値フィルタ→最小値フィルタ)で推定する。
        // 罫線や数字のような細い暗部だけが消え、影の縁のような明暗の境目は保たれる。
        let sw = max(1, w / 4), sh = max(1, h / 4)
        var small = [UInt8](repeating: 0, count: sw * sh)
        small.withUnsafeMutableBytes { ptr in
            let ctx = CGContext(data: ptr.baseAddress, width: sw, height: sh, bitsPerComponent: 8,
                                bytesPerRow: sw, space: CGColorSpaceCreateDeviceGray(),
                                bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: sw, height: sh))
        }
        let radius = max(3, min(sw, sh) / 40)
        var background = morph(morph(small, sw, sh, radius, useMax: true), sw, sh, radius, useMax: false)
        var bg = [UInt8](repeating: 0, count: w * h)
        background.withUnsafeMutableBytes { sp in
            let smallImage = CGContext(data: sp.baseAddress, width: sw, height: sh, bitsPerComponent: 8,
                                       bytesPerRow: sw, space: CGColorSpaceCreateDeviceGray(),
                                       bitmapInfo: CGImageAlphaInfo.none.rawValue)!.makeImage()!
            bg.withUnsafeMutableBytes { ptr in
                let ctx = CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                    bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                    bitmapInfo: CGImageAlphaInfo.none.rawValue)!
                ctx.interpolationQuality = .high
                ctx.draw(smallImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
        }
        var out = buf
        for i in 0..<(w * h) {
            out[i] = UInt8(min(255, Double(buf[i]) / Double(max(bg[i], 1)) * 235))
        }
        return out.withUnsafeMutableBytes { ptr in
            CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!.makeImage()!
        }
    }

    /// 正方形の窓での最大値/最小値フィルタ(縦横に分けて適用)。
    private static func morph(_ src: [UInt8], _ w: Int, _ h: Int, _ r: Int, useMax: Bool) -> [UInt8] {
        func pick(_ a: UInt8, _ b: UInt8) -> UInt8 { useMax ? max(a, b) : min(a, b) }
        var tmp = src, out = src
        for y in 0..<h {
            for x in 0..<w {
                var v = src[y * w + x]
                for dx in -r...r { let xx = x + dx; if xx >= 0, xx < w { v = pick(v, src[y * w + xx]) } }
                tmp[y * w + x] = v
            }
        }
        for y in 0..<h {
            for x in 0..<w {
                var v = tmp[y * w + x]
                for dy in -r...r { let yy = y + dy; if yy >= 0, yy < h { v = pick(v, tmp[yy * w + x]) } }
                out[y * w + x] = v
            }
        }
        return out
    }

    /// 盤面の四角形の候補を集める。文章の塊など盤面でないものも混ざるので、選別は呼び出し側で行う。
    private static func candidateRectangles(in image: CGImage) -> [VNRectangleObservation] {
        func detect(minSize: Float, confidence: Float, tolerance: Float, aspect: Float) -> [VNRectangleObservation] {
            let request = VNDetectRectanglesRequest()
            request.minimumAspectRatio = aspect
            request.maximumAspectRatio = 1.0
            request.minimumSize = minSize
            request.minimumConfidence = confidence
            request.quadratureTolerance = tolerance
            request.maximumObservations = 16
            try? VNImageRequestHandler(cgImage: image).perform([request])
            return request.results ?? []
        }
        return detect(minSize: 0.3, confidence: 0.5, tolerance: 30, aspect: 0.7)
            + detect(minSize: 0.15, confidence: 0.2, tolerance: 45, aspect: 0.6)
    }

    /// 補正後の正方形画像が、どれだけ数独の盤面らしいか。等間隔の10本ずつの罫線がある位置の暗さの平均。
    static func gridScore(_ image: CGImage) -> Double {
        let w = image.width, h = image.height
        var buf = [UInt8](repeating: 0, count: w * h)
        buf.withUnsafeMutableBytes { ptr in
            let ctx = CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        let lo = Int(buf.min()!), hi = Int(buf.max()!)
        guard hi - lo > 40 else { return 0 }
        let threshold = lo + (hi - lo) * 3 / 4
        var rowDark = [Int](repeating: 0, count: h), colDark = [Int](repeating: 0, count: w)
        for y in 0..<h {
            for x in 0..<w where Int(buf[y * w + x]) < threshold { rowDark[y] += 1; colDark[x] += 1 }
        }
        // i / 9 の位置(罫線)の暗さから、その中間(マスの中央)の暗さを引く。
        // 影や文章の塊のように全体が暗いだけのものは、罫線と中央の差が出ないので低得点になる。
        func dark(_ d: [Int], _ len: Int, _ pos: Double) -> Double {
            let center = Int(pos * Double(d.count - 1) / 9)
            let range = max(0, center - 8)...min(d.count - 1, center + 8)
            return Double(range.map { d[$0] }.max() ?? 0) / Double(len)
        }
        func mid(_ d: [Int], _ len: Int, _ pos: Double) -> Double {
            let center = Int(pos * Double(d.count - 1) / 9)
            return Double(d[center]) / Double(len)
        }
        var lines = 0.0, mids = 0.0
        for i in 0...9 { lines += min(1, dark(rowDark, w, Double(i))) + min(1, dark(colDark, h, Double(i))) }
        for i in 0..<9 { mids += mid(rowDark, w, Double(i) + 0.5) + mid(colDark, h, Double(i) + 0.5) }
        return lines / 20 - mids / 18
    }

    /// 盤面を検出して、真上から見た正方形に補正した画像を返す。
    /// 紙全体の四角を先に拾うことがあるので、補正後の画像でもう一度盤面を探して絞り込む(採点が上がる間だけ)。
    static func rectify(_ original: CGImage) -> CGImage {
        let flat = normalized(original)
        return refine(start: resized(flat), original: original, flat: flat)
    }

    /// 指定された四隅で補正する。少し大きめに指定されても、補正後にもう一度盤面を探して絞り込む。
    static func rectify(_ original: CGImage, using quad: Quad) -> CGImage {
        let flat = normalized(original)
        let w = CGFloat(flat.width), h = CGFloat(flat.height)
        // 外枠の線が画像の端に接すると外枠として検出できないので、四隅を中心から外へ少し広げて余白を作る
        let cx = (quad.topLeft.x + quad.topRight.x + quad.bottomRight.x + quad.bottomLeft.x) / 4
        let cy = (quad.topLeft.y + quad.topRight.y + quad.bottomRight.y + quad.bottomLeft.y) / 4
        func p(_ v: CGPoint) -> CGPoint {   // CIImage は左下原点
            let x = cx + (v.x - cx) * (1 + quadMargin), y = cy + (v.y - cy) * (1 + quadMargin)
            return CGPoint(x: x * w, y: (1 - y) * h)
        }
        guard let warped = warp(flat, tl: p(quad.topLeft), tr: p(quad.topRight),
                                br: p(quad.bottomRight), bl: p(quad.bottomLeft)) else { return resized(flat) }
        return refine(start: warped, original: warped, flat: warped)
    }

    private static func refine(start: CGImage, original: CGImage, flat: CGImage) -> CGImage {
        var best = start
        var bestScore = gridScore(best)
        var source = original, sourceFlat = flat
        for _ in 0..<3 {
            guard let next = bestCandidate(original: source, flat: sourceFlat), next.score > bestScore
            else { break }
            best = next.image; bestScore = next.score
            source = next.image; sourceFlat = next.image
        }
        return best
    }

    private static func warp(_ image: CGImage, tl: CGPoint, tr: CGPoint, br: CGPoint, bl: CGPoint) -> CGImage? {
        let filter = CIFilter(name: "CIPerspectiveCorrection")!
        filter.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: tl), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: tr), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: bl), forKey: "inputBottomLeft")
        filter.setValue(CIVector(cgPoint: br), forKey: "inputBottomRight")
        guard let out = filter.outputImage, let cg = ciContext.createCGImage(out, from: out.extent) else { return nil }
        return resized(cg)
    }

    private static func bestCandidate(original: CGImage, flat: CGImage)
        -> (image: CGImage, score: Double, observation: VNRectangleObservation?)? {
        let w = CGFloat(flat.width), h = CGFloat(flat.height)
        // 紙と背景のコントラストは正規化で弱まるので、四角の検出は原画像と正規化後の両方で行う(座標は同じ縦横比)
        let observations = candidateRectangles(in: original) + candidateRectangles(in: flat)
        var best: (image: CGImage, score: Double, observation: VNRectangleObservation?)?
        for obs in observations.sorted(by: { area($0) > area($1) }).prefix(24) {
            func p(_ v: CGPoint) -> CGPoint { CGPoint(x: v.x * w, y: v.y * h) }
            guard let candidate = warp(flat, tl: p(obs.topLeft), tr: p(obs.topRight),
                                       br: p(obs.bottomRight), bl: p(obs.bottomLeft)) else { continue }
            let score = gridScore(candidate)
            if score > (best?.score ?? -1) { best = (candidate, score, obs) }
        }
        return best
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

    static func recognizeDigit(_ crop: CGImage) -> Int { recognizeDigitDetailed(crop).digit }

    /// 数字と、その判定の自信のなさ(uncertain)。空きマスは digit=0。
    static func recognizeDigitDetailed(_ crop: CGImage) -> (digit: Int, uncertain: Bool, alternatives: [Candidate]) {
        guard var mask = inkMask(of: crop) else { return (0, false, []) }
        removeBorderInk(&mask)
        guard let feature = DigitClassifier.feature(of: mask) else { return (0, false, []) }   // 空きマス
        let r = DigitClassifier.classify(feature)
        // cost: その数字だった場合の「もっともらしさの悪化」(0 に近いほど、次点でも有力)
        let alts = r.others.prefix(3).map { Candidate(digit: $0.digit, cost: max(0, $0.distance - r.best)) }
        return (r.digit, r.isUncertain, alts)
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

    /// 隣のマスの罫線の切れ端などを消す。
    /// 1. マスを横切る長い線(行・列のほぼ全体が暗い)を消す。4 や 1 の縦棒(高さの約7割)を消さないよう、しきい値は高くする。
    /// 2. 枠に触れている塊のうち、数字の大きさに満たないもの(ごみ)と、マスを横切るもの(反対側の辺の両方に
    ///    触れる帯や線)を消す。数字が枠に接していても、数字と分かる大きさなら残す(手書きは位置がずれやすい)。
    static func removeBorderInk(_ m: inout Mask) {
        let w = m.width, h = m.height
        // 1. 長い線
        var rowLine = [Bool](repeating: false, count: h), colLine = [Bool](repeating: false, count: w)
        for y in 0..<h {
            var n = 0
            for x in 0..<w where m.ink[y * w + x] { n += 1 }
            rowLine[y] = Double(n) > 0.92 * Double(w)
        }
        for x in 0..<w {
            var n = 0
            for y in 0..<h where m.ink[y * w + x] { n += 1 }
            colLine[x] = Double(n) > 0.92 * Double(h)
        }
        for y in 0..<h {
            for x in 0..<w where m.ink[y * w + x] {
                let nearRow = (max(0, y - 2)...min(h - 1, y + 2)).contains { rowLine[$0] }
                let nearCol = (max(0, x - 2)...min(w - 1, x + 2)).contains { colLine[$0] }
                if (rowLine[y] || colLine[x]) && (nearRow || nearCol) { m.ink[y * w + x] = false }
            }
        }
        // 2. 枠に触れている小さな塊
        var seeds: [Int] = []
        for x in 0..<w { seeds.append(x); seeds.append((h - 1) * w + x) }
        for y in 0..<h { seeds.append(y * w); seeds.append(y * w + w - 1) }
        var seen = Set<Int>()
        for seed in seeds where m.ink[seed] && !seen.contains(seed) {
            var stack = [seed], component: [Int] = []
            seen.insert(seed)
            var minY = h, maxY = 0, minX = w, maxX = 0
            var top = false, bottom = false, left = false, right = false
            while let i = stack.popLast() {
                component.append(i)
                let x = i % w, y = i / w
                minY = min(minY, y); maxY = max(maxY, y); minX = min(minX, x); maxX = max(maxX, x)
                if y == 0 { top = true }; if y == h - 1 { bottom = true }
                if x == 0 { left = true }; if x == w - 1 { right = true }
                for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < w, ny >= 0, ny < h else { continue }
                    let j = ny * w + nx
                    if m.ink[j], !seen.contains(j) { seen.insert(j); stack.append(j) }
                }
            }
            let crossing = (top && bottom) || (left && right)
            // 数字は線でできているので外接矩形に対するインクの割合が低い。塗りつぶされた塊は影などの汚れ
            let filled = Double(component.count) / Double((maxX - minX + 1) * (maxY - minY + 1)) > 0.6
            if crossing || filled || Double(maxY - minY + 1) < 0.3 * Double(h) { for i in component { m.ink[i] = false } }
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

    /// テンプレートの作り方。傾き(shear)、回転、線の太さを変えて、手書きのばらつきに備える。
    struct Variant {
        var rotation: Double = 0     // ラジアン
        var shear: Double = 0        // 文字の傾き(0.2 で約 11 度)
        var stroke: Double = 0       // 線を太くする量(フォントサイズに対する比)
    }

    static let printFonts = ["Helvetica", "Helvetica-Bold", "HelveticaNeue", "HelveticaNeue-Medium", "ArialMT", "Arial-BoldMT",
                             "TimesNewRomanPSMT", "TimesNewRomanPS-BoldMT", "Georgia", "Georgia-Bold", "Verdana",
                             "Courier", "Courier-Bold", "AvenirNext-Regular", "AvenirNext-DemiBold", "Menlo-Regular",
                             "Futura-Medium", "GillSans", "TrebuchetMS"]

    /// 手書き風のフォント(端末にないものは自動的に無視される)。
    static let handwritingFonts = ["BradleyHandITCTT-Bold", "Noteworthy-Bold", "Noteworthy-Light", "MarkerFelt-Thin",
                                   "MarkerFelt-Wide", "ChalkboardSE-Regular", "ChalkboardSE-Bold", "Chalkduster",
                                   "AmericanTypewriter", "SnellRoundhand", "PartyLetPlain", "Papyrus"]

    static let printVariants = [Variant(), Variant(shear: 0.15), Variant(stroke: 0.03)]
    static let handwritingVariants = [Variant(), Variant(rotation: 0.12), Variant(rotation: -0.12),
                                      Variant(shear: 0.2), Variant(shear: -0.12), Variant(stroke: 0.04),
                                      Variant(rotation: 0.08, shear: 0.15, stroke: 0.02)]

    static let templates: [(digit: Int, feature: [Float])] =
        makeTemplates(fonts: printFonts, variants: printVariants)
        + makeTemplates(fonts: handwritingFonts.filter(isAvailable), variants: handwritingVariants)

    private static func isAvailable(_ name: String) -> Bool {
        let f = CTFontCreateWithName(name as CFString, 12, nil)
        return (CTFontCopyPostScriptName(f) as String).lowercased() == name.lowercased()
    }

    static func makeTemplates(fonts: [String], variants: [Variant]) -> [(digit: Int, feature: [Float])] {
        var result: [(Int, [Float])] = []
        for name in fonts {
            let font = CTFontCreateWithName(name as CFString, 140, nil)
            for v in variants {
                for d in 1...9 {
                    let n = 260
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
                        ctx.translateBy(x: CGFloat(n) / 2, y: CGFloat(n) / 2)
                        ctx.rotate(by: CGFloat(v.rotation))
                        ctx.concatenate(CGAffineTransform(a: 1, b: 0, c: CGFloat(v.shear), d: 1, tx: 0, ty: 0))
                        ctx.textPosition = CGPoint(x: -b.width / 2 - b.minX, y: -b.height / 2 - b.minY)
                        if v.stroke > 0 {
                            ctx.setTextDrawingMode(.fillStroke)
                            ctx.setLineWidth(CGFloat(v.stroke) * 140)
                            ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
                        }
                        CTLineDraw(line, ctx)
                    }
                    let mask = Mask(width: n, height: n, ink: buf.map { $0 < 128 })
                    if let f = feature(of: mask, minHeightRatio: 0, minStrokeWidth: 0) { result.append((d, f)) }
                }
            }
        }
        return result
    }

    /// マスクから特徴量を作る。数字が小さすぎる(=空白)場合は nil。
    static func feature(of m: Mask, minHeightRatio: Double = 0.3, minStrokeWidth: Double = 2.0) -> [Float]? {
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
        // 線が細すぎるものは、影の縁や紙のしわのような汚れで数字ではない(インク量÷長さ = 平均の線の太さ)
        guard Double(dark) / Double(max(bw, bh)) >= minStrokeWidth else { return nil }

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

    struct Result {
        var digit: Int
        var best: Float          // 最も近いテンプレートまでの距離(小さいほど良い)
        var runnerUp: Float      // 別の数字のテンプレートの中で最も近いものまでの距離
        /// 次点以降の候補(近い順)。距離は best との差ではなく、その数字の最小距離そのもの。
        var others: [(digit: Int, distance: Float)] = []
        /// 別の数字との差が小さい、または最も近いものでも遠い場合は、確認を促す。
        var isUncertain: Bool { best > Self.farLimit || best > runnerUp * Self.ambiguityRatio }
        static let farLimit: Float = 60
        static let ambiguityRatio: Float = 0.7
    }

    /// 最も近いテンプレートの数字を返す。
    static func classify(_ f: [Float], templates: [(digit: Int, feature: [Float])] = DigitClassifier.templates) -> Result {
        var perDigit = [Float](repeating: .greatestFiniteMagnitude, count: 10)
        for t in templates {
            var d: Float = 0
            for i in 0..<f.count { let e = f[i] - t.feature[i]; d += e * e }
            if d < perDigit[t.digit] { perDigit[t.digit] = d }
        }
        let best = (1...9).min { perDigit[$0] < perDigit[$1] }!
        let others = (1...9).filter { $0 != best }.map { (digit: $0, distance: perDigit[$0]) }.sorted { $0.distance < $1.distance }
        return Result(digit: best, best: perDigit[best], runnerUp: others[0].distance, others: others)
    }
}
#endif

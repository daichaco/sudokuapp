#if canImport(Vision)
import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import SudokuCore

/// 数独の盤面を画像として描画する(回転・余白つき)。
func renderBoard(_ board: Board, rotationDegrees: Double = 0, fontSize: CGFloat = 64) -> CGImage {
    let size = 1200
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(CGColor(gray: 0.93, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    ctx.translateBy(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
    ctx.rotate(by: rotationDegrees * .pi / 180)
    ctx.translateBy(x: -450, y: -450)

    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 900, height: 900))
    ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
    for i in 0...9 {
        ctx.setLineWidth(i % 3 == 0 ? 5 : 2)
        ctx.move(to: CGPoint(x: i * 100, y: 0)); ctx.addLine(to: CGPoint(x: i * 100, y: 900))
        ctx.move(to: CGPoint(x: 0, y: i * 100)); ctx.addLine(to: CGPoint(x: 900, y: i * 100))
        ctx.strokePath()
    }
    let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
    for r in 0..<9 {
        for c in 0..<9 where board[r, c] != 0 {
            let attr = NSAttributedString(string: "\(board[r, c])", attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.05, alpha: 1)])
            let line = CTLineCreateWithAttributedString(attr)
            let b = CTLineGetBoundsWithOptions(line, [])
            ctx.textPosition = CGPoint(x: CGFloat(c * 100) + 50 - b.width / 2 - b.minX,
                                       y: CGFloat((8 - r) * 100) + 50 - b.height / 2 - b.minY)
            CTLineDraw(line, ctx)
        }
    }
    return ctx.makeImage()!
}

func accuracy(_ a: Board, _ b: Board) -> Double {
    Double((0..<81).filter { a.cells[$0] == b.cells[$0] }.count) / 81
}

@Test func recognizesRenderedBoard() throws {
    let expected = try #require(Board(string: easy))
    let got = BoardRecognizer.recognize(renderBoard(expected))
    let acc = accuracy(got, expected)
    print("recognition accuracy (straight):", acc)
    #expect(acc >= 0.98)
}

@Test func recognizesRotatedBoard() throws {
    let expected = try #require(Board(string: easy))
    let got = BoardRecognizer.recognize(renderBoard(expected, rotationDegrees: 6))
    let acc = accuracy(got, expected)
    print("recognition accuracy (rotated 6deg):", acc)
    #expect(acc >= 0.98)
}

/// 画像に黒→透明のグラデーションの影を重ねる(斜め方向)。
func addShadow(_ image: CGImage, strength: CGFloat) -> CGImage {
    let w = image.width, h = image.height
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(),
                              colors: [CGColor(gray: 0, alpha: strength), CGColor(gray: 0, alpha: 0)] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: CGPoint(x: Double(w) * 0.7, y: Double(h) * 0.3),
                           options: [])
    return ctx.makeImage()!
}

/// 盤面の上下に文章を並べたページを作る(新聞のような、盤面以外の四角や罫線が写り込む状況)。
func addSurroundingText(_ image: CGImage) -> CGImage {
    let w = image.width, h = image.height
    let ctx = CGContext(data: nil, width: w, height: h + 600, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(CGColor(gray: 0.8, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h + 600))
    ctx.draw(image, in: CGRect(x: 0, y: 300, width: w, height: h))
    let font = CTFontCreateWithName("Times New Roman" as CFString, 26, nil)
    let attr = NSAttributedString(string: String(repeating: "The quick brown fox jumps over 12 lazy dogs 2026 ", count: 4),
                                  attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
    let line = CTLineCreateWithAttributedString(attr)
    for row in 0..<8 {
        for y in [CGFloat(h + 300 + 30 + row * 34), CGFloat(20 + row * 34)] {
            ctx.textPosition = CGPoint(x: 20, y: y)
            CTLineDraw(line, ctx)
        }
    }
    return ctx.makeImage()!
}

/// renderBoard の盤面(1200px の画像の中央 900px)の四隅。margin は盤面の幅に対する外向きの余白。
func boardQuad(margin: Double) -> BoardRecognizer.Quad {
    let lo = 0.125 - margin * 0.75, hi = 0.875 + margin * 0.75
    return .init(topLeft: CGPoint(x: lo, y: lo), topRight: CGPoint(x: hi, y: lo),
                 bottomRight: CGPoint(x: hi, y: hi), bottomLeft: CGPoint(x: lo, y: hi))
}

@Test(arguments: [0.0, 0.05, 0.1])
func recognizesWithManualCorners(margin: Double) throws {
    let expected = try #require(Board(string: easy))
    let got = BoardRecognizer.recognize(renderBoard(expected), quad: boardQuad(margin: margin))
    #expect(accuracy(got, expected) >= 0.98, "margin \(margin)")
}

@Test func detectsBoardCorners() throws {
    let expected = try #require(Board(string: easy))
    let quad = try #require(BoardRecognizer.detectQuad(in: renderBoard(expected)))
    // 盤面は 0.125〜0.875。検出は少し外側でもよいが、大きくずれてはいけない
    for p in [quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft] {
        #expect(abs(p.x - 0.125) < 0.05 || abs(p.x - 0.875) < 0.05)
        #expect(abs(p.y - 0.125) < 0.05 || abs(p.y - 0.875) < 0.05)
    }
}

/// 4 や 1 の縦棒は、マスの高さの7〜8割ある。罫線と取り違えて消してはいけない(実機の写真で 4 を 6 と読んだ不具合)。
@Test func keepsTallVerticalStrokesOfFoursAndOnes() throws {
    let expected = try #require(Board(string: easy))
    for size in [72.0, 80.0, 88.0] {
        let got = BoardRecognizer.recognize(renderBoard(expected, fontSize: size))
        #expect(accuracy(got, expected) >= 0.98, "font size \(size)")
    }
}

@Test func recognizesBoardUnderHardShadow() throws {
    let expected = try #require(Board(string: easy))
    let got = BoardRecognizer.recognize(addShadow(renderBoard(expected), strength: 0.65))
    let acc = accuracy(got, expected)
    print("recognition accuracy (hard shadow):", acc)
    #expect(acc >= 0.98)
}

@Test func recognizesBoardSurroundedByText() throws {
    let expected = try #require(Board(string: easy))
    let got = BoardRecognizer.recognize(addSurroundingText(renderBoard(expected)))
    let acc = accuracy(got, expected)
    print("recognition accuracy (surrounded by text):", acc)
    #expect(acc >= 0.98)
}
#endif

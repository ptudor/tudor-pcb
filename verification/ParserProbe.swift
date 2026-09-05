import Foundation

/// Built directly with GerberKit sources so malformed input is isolated from the
/// test runner. The same driver can be compiled against a baseline source tree.
@main struct ParserProbe {
    static func main() {
        do {
            let source = FileHandle.standardInput.readDataToEndOfFile()
            if CommandLine.arguments.contains("--zip") {
                print("ACCEPTED \(try ZipArchiveReader().read(source).count)")
                return
            }
            if CommandLine.arguments.contains("--invalid-bounds") {
                _ = try BoardRasterizer().render(BoardDocument(name: "invalid", bounds: Bounds2D(minimum: .zero, maximum: Point2D(x: .infinity, y: 1))))
                print("ACCEPTED invalid bounds")
                return
            }
            if CommandLine.arguments.contains("--custom-bounds") {
                let shape = ApertureShape.custom(points: [Point2D(x: 5, y: 7), Point2D(x: 7, y: 7), Point2D(x: 7, y: 8), Point2D(x: 5, y: 8)])
                let bounds = GerberPrimitive.flash(center: Point2D(x: 2, y: 3), shape: shape, polarity: .dark).bounds!
                print("BOUNDS \(bounds.minimum.x) \(bounds.minimum.y) \(bounds.maximum.x) \(bounds.maximum.y)")
                return
            }
            let layer = try GerberParser().parse(data: source, fileName: "subprocess.gtl")
            print("ACCEPTED \(layer.primitives.count)")
        } catch {
            print("REJECTED \(error.localizedDescription)")
        }
    }
}

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
            if CommandLine.arguments.contains("--package") || CommandLine.arguments.contains("--render-package") {
                let document = try FabricationPackageLoader().load(from: URL(fileURLWithPath: CommandLine.arguments[2]))
                print("PACKAGE \(document.layers.count) layers \(document.drills.count) drills \(document.warnings)")
                if CommandLine.arguments.contains("--render-package") {
                    let textures = try BoardRasterizer().render(document)
                    let bytes = textures.boardMask.dataProvider!.data! as Data
                    let transparent = stride(from: 3, to: bytes.count, by: 4).filter { bytes[$0] == 0 }.count
                    print("RASTER \(textures.pixelWidth)x\(textures.pixelHeight) transparent=\(transparent)")
                }
                return
            }
            let layer = try GerberParser().parse(data: source, fileName: "subprocess.gtl")
            if CommandLine.arguments.contains("--render-pixel") {
                let image = try BoardRasterizer().render(BoardDocument(name: "pixel", layers: [layer], bounds: Bounds2D(minimum: .zero, maximum: Point2D(x: 10, y: 10))), options: .init(maximumTextureDimension: 256)).top
                let x = Int(CommandLine.arguments[2])!, y = Int(CommandLine.arguments[3])!
                let data = image.dataProvider!.data! as Data
                let index = y * image.bytesPerRow + x * 4
                print("PIXEL \(Array(data[index..<(index + 4)]))")
                return
            }
            print("ACCEPTED \(layer.primitives.count)")
        } catch {
            print("REJECTED \(error.localizedDescription)")
        }
    }
}

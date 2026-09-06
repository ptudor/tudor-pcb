import Foundation

@main struct InspectionProbe {
    static func main() throws {
        let document = try FabricationPackageLoader().load(from: URL(fileURLWithPath: CommandLine.arguments[1]))
        for layer in document.layers where !layer.kind.hasPhysicalAppearanceControl && !layer.primitives.isEmpty {
            let result = try BoardRasterizer().renderInspection(document, layerIDs: [layer.id], showDrills: false, maximumTextureDimension: 1024)
            let bytes = result.image.dataProvider!.data! as Data
            let visible = stride(from: 3, to: bytes.count, by: 4).filter { bytes[$0] > 0 }.count
            guard visible > 0 else { throw CocoaError(.fileReadCorruptFile) }
            print("INSPECT", layer.fileName, layer.kind.displayName, "visiblePixels=\(visible)", "mm/texel=\(result.millimetersPerPixel)")
        }
    }
}

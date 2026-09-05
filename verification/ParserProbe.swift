import Foundation

/// Built directly with GerberKit sources so malformed input is isolated from the
/// test runner. The same driver can be compiled against a baseline source tree.
@main struct ParserProbe {
    static func main() {
        do {
            let source = FileHandle.standardInput.readDataToEndOfFile()
            let layer = try GerberParser().parse(data: source, fileName: "subprocess.gtl")
            print("ACCEPTED \(layer.primitives.count)")
        } catch {
            print("REJECTED \(error.localizedDescription)")
        }
    }
}

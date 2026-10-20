import Foundation
import BojiDomain

public struct LocalFileAccess: FileAccess {
    public init() {}
    public func read(_ url: URL) throws -> Data { try Data(contentsOf: url) }
    public func writeAtomically(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}

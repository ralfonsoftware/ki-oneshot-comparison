import Foundation

enum FileAccess {
    static func read(url: URL) throws -> Data {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attributes[.size] as? Int64, size > 250 * 1_024 * 1_024 {
            throw FileAccessError.tooLarge
        }
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }
}

enum FileAccessError: LocalizedError {
    case tooLarge
    var errorDescription: String? { String(localized: "The import file is larger than 250 MB.") }
}

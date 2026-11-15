import Foundation
#if canImport(DeveloperToolsSupport)
import DeveloperToolsSupport
#endif

#if SWIFT_PACKAGE
private let resourceBundle = Foundation.Bundle.module
#else
private class ResourceBundleClass {}
private let resourceBundle = Foundation.Bundle(for: ResourceBundleClass.self)
#endif

// MARK: - Color Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ColorResource {

    /// The "AccentColor" asset catalog color resource.
    static let accent = DeveloperToolsSupport.ColorResource(name: "AccentColor", bundle: resourceBundle)

    /// The "StatusBelowBaseline" asset catalog color resource.
    static let statusBelowBaseline = DeveloperToolsSupport.ColorResource(name: "StatusBelowBaseline", bundle: resourceBundle)

    /// The "StatusBelowBaselineText" asset catalog color resource.
    static let statusBelowBaselineText = DeveloperToolsSupport.ColorResource(name: "StatusBelowBaselineText", bundle: resourceBundle)

    /// The "StatusTrending" asset catalog color resource.
    static let statusTrending = DeveloperToolsSupport.ColorResource(name: "StatusTrending", bundle: resourceBundle)

    /// The "StatusTrendingText" asset catalog color resource.
    static let statusTrendingText = DeveloperToolsSupport.ColorResource(name: "StatusTrendingText", bundle: resourceBundle)

    /// The "StatusWithinRange" asset catalog color resource.
    static let statusWithinRange = DeveloperToolsSupport.ColorResource(name: "StatusWithinRange", bundle: resourceBundle)

    /// The "StatusWithinRangeText" asset catalog color resource.
    static let statusWithinRangeText = DeveloperToolsSupport.ColorResource(name: "StatusWithinRangeText", bundle: resourceBundle)

    /// The "WidgetBackground" asset catalog color resource.
    static let widgetBackground = DeveloperToolsSupport.ColorResource(name: "WidgetBackground", bundle: resourceBundle)

}

// MARK: - Image Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ImageResource {

}


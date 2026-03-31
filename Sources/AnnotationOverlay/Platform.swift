#if canImport(UIKit)
import UIKit

/// The platform-native view type used by SwiftUI's hosting layer.
public typealias PlatformView = UIView

#elseif canImport(AppKit)
import AppKit

/// The platform-native view type used by SwiftUI's hosting layer.
public typealias PlatformView = NSView

#endif

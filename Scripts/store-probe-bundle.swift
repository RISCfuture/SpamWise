import Foundation

/// The Store sources' resource bundle when `swiftc` builds them without SwiftPM: the probe holds no
/// string catalog, so their messages stay in English.
extension Bundle {
  static var module: Bundle { .main }
}

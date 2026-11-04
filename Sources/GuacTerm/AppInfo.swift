import Foundation

enum AppInfo {
    static let name = "GuacTerm"
    static let tagline = "A drop-down terminal for macOS"

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    static var versionDescription: String {
        "Version \(version) (\(build))"
    }
}

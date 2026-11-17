import Foundation

/// The app's name as people see it. It comes from `APP_DISPLAY_NAME` in
/// Config/Signing.xcconfig, so renaming the app is a one-line change there.
enum AppInfo {
    static let name: String = {
        let info = Bundle.main.infoDictionary
        if let name = info?["CFBundleDisplayName"] as? String, !name.isEmpty, !name.hasPrefix("$(") { return name }
        return "Inkstone"
    }()

    /// For example "1.0 (3)".
    static let version: String = {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }()

    static let supportURL = URL(string: "https://github.com/isgandarjafarli/inkstone/blob/main/SUPPORT.md")!
    static let privacyURL = URL(string: "https://github.com/isgandarjafarli/inkstone/blob/main/PRIVACY.md")!
}

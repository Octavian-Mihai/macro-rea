import Foundation

/// Values injected at build time from the git-ignored `.env` file (see tools/inject_secrets.sh).
enum Secrets {
    private static let values: [String: String] = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let d = NSDictionary(contentsOf: url) as? [String: String] else { return [:] }
        return d
    }()

    static var fdcAPIKey: String { values["FDC_API_KEY"]?.trimmingCharacters(in: .whitespaces) ?? "" }
}

import Foundation

/// Paramètres d'accès à l'API Telegram, injectés à la compilation
/// (Config/Secrets.xcconfig → Info.plist). Jamais versionnés.
struct AppConfig: Equatable {
    let apiId: Int
    let apiHash: String
    let applicationVersion: String

    static func fromBundle(_ bundle: Bundle = .main) -> AppConfig? {
        guard
            let idString = bundle.object(forInfoDictionaryKey: "TGApiId") as? String,
            let apiId = Int(idString.trimmingCharacters(in: .whitespaces)), apiId > 0,
            let apiHash = (bundle.object(forInfoDictionaryKey: "TGApiHash") as? String)?
                .trimmingCharacters(in: .whitespaces),
            !apiHash.isEmpty
        else { return nil }

        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return AppConfig(apiId: apiId, apiHash: apiHash, applicationVersion: version)
    }

    /// Vrai quand l'app sert d'hôte aux tests unitaires : on ne démarre pas TDLib.
    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

import Foundation

/// Dossier de la base et des fichiers TDLib.
///
/// - Exclu des sauvegardes iCloud / ordinateur.
/// - Protection `completeUnlessOpen` : fichiers illisibles appareil verrouillé, sauf ceux
///   déjà ouverts. `complete` couperait l'accès à la base SQLite ouverte par TDLib dès le
///   verrouillage (risque de corruption) ; la base est de toute façon chiffrée par TDLib.
enum TDLibStorage {
    private static let folderName = "tdlib"

    static var directoryURL: URL {
        get throws {
            try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent(folderName, isDirectory: true)
        }
    }

    static func prepareDirectory() throws -> URL {
        var url = try directoryURL
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUnlessOpen]
            )
        } else {
            try fileManager.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: url.path)
        }

        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        return url
    }

    /// Supprime toutes les données TDLib locales.
    static func reset() throws {
        let url = try directoryURL
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

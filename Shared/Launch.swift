import Foundation

enum Launch {
    static let freePeriod = false
    static let appID = "com.hgsldswk.warranty"
    static let group = "group.com.hgsldswk.warranty"
    static let proID = appID + ".pro"
    static let trialID = appID + ".trial"
    static let widgetKind = "WarrantyWidget"
    static let openURL = URL(string: "warrantykeep://open")!
    static let placeholderURL = URL(string: "https://hgsldswk-alt.github.io/warranty-support/")!
    static let freeLimit = 5
    static let hashtag = "#WarrantyWin"
    static var storeURL: URL {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "APP_STORE_ID") as? String,
              !id.isEmpty, id.allSatisfy({ $0.isASCII && $0.isNumber }),
              let url = URL(string: "https://apps.apple.com/app/id\(id)") else { return placeholderURL }
        return url
    }
    static let arguments = ProcessInfo.processInfo.arguments
    static var testing: Bool { arguments.contains("-ui-testing") }
    static func testFlag(_ flag: String) -> Bool { testing && arguments.contains(flag) }
}

final class LocalizationBundle: NSObject {}

enum L {
    static func t(_ key: String) -> String {
        NSLocalizedString(key, bundle: Bundle(for: LocalizationBundle.self), comment: "")
    }

    static func f(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: t(key), locale: .current, arguments: arguments)
    }
}

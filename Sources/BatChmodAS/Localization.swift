import Foundation

enum L10n {
    static func string(_ key: String) -> String {
        let value = String.LocalizationValue(key)
        let mainValue = String(localized: value, bundle: .main)
        if mainValue != key {
            return mainValue
        }
        return String(localized: value, bundle: .module)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: Locale.current, arguments: arguments)
    }
}

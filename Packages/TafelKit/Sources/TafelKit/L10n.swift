import Foundation
import Combine

/// In-app language, independent of the system language and switchable without restart.
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case en, de

    public var id: String { rawValue }
    /// Name in its own language (shown in the picker regardless of the current language).
    public var nativeName: String {
        switch self {
        case .en: return "English"
        case .de: return "Deutsch"
        }
    }
    public var flag: String {
        switch self {
        case .en: return "🇬🇧"
        case .de: return "🇩🇪"
        }
    }
}

/// Localisation store. Keys are the German UI texts (the code was written in German); each other
/// language has a table in `Translations.swift`. Missing entries fall back to the key, and
/// `Tools/check-l10n.py` lists keys that have no English entry.
public final class L10n: ObservableObject, @unchecked Sendable {
    public static let shared = L10n()
    private static let defaultsKey = "appLanguage"

    @Published public var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey) }
    }

    /// Whether the user has picked a language yet (first-run setup starts with that).
    public var hasChosen: Bool { UserDefaults.standard.string(forKey: Self.defaultsKey) != nil }

    private init() {
        language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: Self.defaultsKey) ?? "") ?? .en
    }

    public func string(_ key: String) -> String {
        switch language {
        case .de: return key
        case .en: return Translations.en[key] ?? key
        }
    }
}

/// Localised text for a German key. With arguments the key is a format string (`%@`, `%d`, …).
public func L(_ key: String, _ args: CVarArg...) -> String {
    let s = L10n.shared.string(key)
    return args.isEmpty ? s : String(format: s, arguments: args)
}

/// Display form of a link description from `TafelNetwork.describe` ("USB-Kabel (en8)", "WLAN (en0)", …).
/// The raw string stays German because code checks it (`hasPrefix("USB")`); only the shown text is
/// translated.
public func localizedLink(_ s: String) -> String {
    guard L10n.shared.language == .en else { return s }
    var r = s
    for (de, en) in [("USB-Kabel", "USB cable"), ("Peer-to-Peer-WLAN", "Peer-to-peer Wi-Fi"), ("WLAN", "Wi-Fi"),
                     ("Mobilfunk", "Cellular"), ("Sonstige", "Other")] {
        r = r.replacingOccurrences(of: de, with: en)
    }
    return r
}

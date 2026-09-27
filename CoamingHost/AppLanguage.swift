enum AppLanguage: String, CaseIterable, Identifiable {
    case en
    case ja

    var id: String { rawValue }

    var segment: String {
        switch self {
        case .en: "EN"
        case .ja: "JA"
        }
    }

    func pick(ja: String, en: String) -> String {
        self == .ja ? ja : en
    }
}

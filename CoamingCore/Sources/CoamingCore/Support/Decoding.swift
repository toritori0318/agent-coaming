import Foundation

extension KeyedDecodingContainer {
    func decodeFlexibleDoubleIfPresent(forKey key: Key) throws -> Double? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        if let value = try? decode(Double.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return Double(value) }
        if let value = try? decode(String.self, forKey: key) { return Double(value) }
        return nil
    }

    func decodeFlexibleDateIfPresent(forKey key: Key) throws -> Date? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        if let value = try? decode(Double.self, forKey: key) {
            return Date(timeIntervalSince1970: value)
        }
        if let value = try? decode(Int.self, forKey: key) {
            return Date(timeIntervalSince1970: TimeInterval(value))
        }
        if let value = try? decode(String.self, forKey: key) {
            return DateParsing.parseISO8601(value)
        }
        return nil
    }
}

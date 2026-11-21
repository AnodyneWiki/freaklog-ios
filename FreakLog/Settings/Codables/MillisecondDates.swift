import Foundation

// Journal files store dates as whole milliseconds since 1970, the format the Android app reads and writes.
// Missing optional dates are written as null.
extension KeyedDecodingContainer {
    func decodeMillis(forKey key: Key) throws -> Date {
        Date(millisecondsSince1970: try decode(Int64.self, forKey: key))
    }

    func decodeMillisIfPresent(forKey key: Key) throws -> Date? {
        try decodeIfPresent(Int64.self, forKey: key).map(Date.init(millisecondsSince1970:))
    }
}

extension KeyedEncodingContainer {
    mutating func encodeMillis(_ date: Date?, forKey key: Key) throws {
        try encode(date?.millisecondsSince1970, forKey: key)
    }
}

extension Date {
    init(millisecondsSince1970 millis: Int64) {
        self.init(timeIntervalSince1970: Double(millis) / 1000)
    }

    var millisecondsSince1970: Int64 {
        Int64((timeIntervalSince1970 * 1000).rounded())
    }
}

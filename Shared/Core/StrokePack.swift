import Foundation

/// Stroke outlines and medians for one character (Make Me a Hanzi data, 1024-unit box, y up, baseline at 900).
struct StrokeData: Codable, Sendable {
    /// SVG path strings, one per stroke.
    let s: [String]
    /// Median polylines, one per stroke, as [[x, y]] points.
    let m: [[[Double]]]
    /// Indices of strokes that belong to the radical.
    let r: [Int]

    var strokes: [String] { s }
    var medians: [[[Double]]] { m }
    var radicalStrokes: Set<Int> { Set(r) }
}

/// Reads characters out of strokes.pack on demand: a 4-byte little-endian index length,
/// a JSON index {hex code point: [offset, length]}, then one JSON blob per character.
final class StrokePack: @unchecked Sendable {
    private let url: URL
    private let index: [String: [Int]]
    private let dataStart: Int
    private var cache: [String: StrokeData] = [:]
    private let lock = NSLock()

    init(url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let lenData = handle.readData(ofLength: 4)
        guard lenData.count == 4 else { throw CocoaError(.fileReadCorruptFile) }
        let indexLength = lenData.withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
        let indexData = handle.readData(ofLength: indexLength)
        index = try JSONDecoder().decode([String: [Int]].self, from: indexData)
        dataStart = 4 + indexLength
        self.url = url
    }

    /// The pack bundled with the app, if there is one.
    static func bundled(_ bundle: Bundle = .main) -> StrokePack? {
        guard let url = bundle.url(forResource: "strokes", withExtension: "pack") else { return nil }
        return try? StrokePack(url: url)
    }

    func has(_ c: String) -> Bool {
        guard let scalar = c.unicodeScalars.first else { return false }
        return index[String(scalar.value, radix: 16)] != nil
    }

    func strokes(for c: String) -> StrokeData? {
        guard let scalar = c.unicodeScalars.first else { return nil }
        let key = String(scalar.value, radix: 16)
        lock.lock(); defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        guard let entry = index[key], entry.count == 2,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: UInt64(dataStart + entry[0]))
            let data = handle.readData(ofLength: entry[1])
            let sd = try JSONDecoder().decode(StrokeData.self, from: data)
            if cache.count > 200 { cache.removeAll() }
            cache[key] = sd
            return sd
        } catch {
            return nil
        }
    }
}

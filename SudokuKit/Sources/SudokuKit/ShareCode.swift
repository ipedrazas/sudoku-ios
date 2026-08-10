import Foundation

/// A self-contained puzzle code, for sharing without a server.
///
/// The web app shares BIP-39 slugs that only mean something to its database.
/// With no backend there is nothing to resolve a slug against, so the code has
/// to carry the puzzle itself.
///
/// Layout:
/// ```
/// byte 0       version (0x01)
/// bytes 1…11   81-bit given mask, LSB first
/// bytes 12…    given digits, 4 bits each, in index order
/// last 2       CRC-16/CCITT over everything before it
/// ```
/// A 26-clue puzzle comes to 27 bytes — 36 base64url characters — against 41
/// bytes for the naive "4 bits per cell" encoding, because empty cells cost one
/// bit rather than four.
public enum ShareCode {
    public static let version: UInt8 = 1

    /// Why a code could not be decoded. Every case is a refusal to guess: a
    /// share code that silently decodes to the wrong puzzle would be far worse
    /// than one that fails.
    public enum DecodeError: Error, Equatable, Sendable {
        case notBase64
        case tooShort
        case unsupportedVersion(UInt8)
        case checksumMismatch
        case truncatedDigits
        case illegalDigit
        /// Decoded cleanly but the puzzle breaks Sudoku's rules.
        case invalidPuzzle
    }

    // MARK: - Encoding

    public static func encode(_ puzzle: borrowing Grid) -> String {
        var mask = [UInt8](repeating: 0, count: 11)
        var digits: [Int] = []
        digits.reserveCapacity(Grid.cellCount)

        for index in 0..<Grid.cellCount {
            let value = puzzle[index]
            guard value != 0 else { continue }
            mask[index / 8] |= UInt8(1 << (index % 8))
            digits.append(value)
        }

        var payload: [UInt8] = [version]
        payload.append(contentsOf: mask)

        // Two digits per byte, high nibble first. An odd count leaves the final
        // low nibble zero, which the given count already accounts for.
        var packed = [UInt8](repeating: 0, count: (digits.count + 1) / 2)
        for (offset, digit) in digits.enumerated() {
            if offset % 2 == 0 {
                packed[offset / 2] |= UInt8(digit) << 4
            } else {
                packed[offset / 2] |= UInt8(digit)
            }
        }
        payload.append(contentsOf: packed)

        let checksum = crc16(payload)
        payload.append(UInt8(checksum >> 8))
        payload.append(UInt8(checksum & 0xFF))

        return base64URLEncode(payload)
    }

    // MARK: - Decoding

    public static func decode(_ code: String) throws -> Grid {
        guard let payload = base64URLDecode(code) else { throw DecodeError.notBase64 }
        guard payload.count >= 14 else { throw DecodeError.tooShort }
        guard payload[0] == version else { throw DecodeError.unsupportedVersion(payload[0]) }

        let body = Array(payload.dropLast(2))
        let expected = (UInt16(payload[payload.count - 2]) << 8) | UInt16(payload[payload.count - 1])
        guard crc16(body) == expected else { throw DecodeError.checksumMismatch }

        let mask = Array(body[1...11])
        let packed = Array(body[12...])

        var indices: [Int] = []
        for index in 0..<Grid.cellCount where mask[index / 8] & UInt8(1 << (index % 8)) != 0 {
            indices.append(index)
        }
        guard packed.count == (indices.count + 1) / 2 else { throw DecodeError.truncatedDigits }

        var grid = Grid()
        for (offset, index) in indices.enumerated() {
            let byte = packed[offset / 2]
            let digit = offset % 2 == 0 ? Int(byte >> 4) : Int(byte & 0x0F)
            guard (1...Grid.size).contains(digit) else { throw DecodeError.illegalDigit }
            grid[index] = digit
        }

        guard Validator.obeysRules(grid) else { throw DecodeError.invalidPuzzle }
        return grid
    }

    // MARK: - URLs

    /// The custom scheme, which works with no server and ships regardless.
    public static func url(for puzzle: borrowing Grid) -> URL? {
        URL(string: "sudokuandcake://p/\(encode(puzzle))")
    }

    /// The Universal Link form. Needs an `apple-app-site-association` file on
    /// the host before it resolves; until then the custom scheme carries it.
    public static func universalLink(for puzzle: borrowing Grid) -> URL? {
        URL(string: "https://sudoku.ios.andcake.dev/p/\(encode(puzzle))")
    }

    /// Extracts a code from either URL form, or from a bare code.
    public static func code(from url: URL) -> String? {
        let components = url.pathComponents.filter { $0 != "/" }
        if url.scheme == "sudokuandcake", url.host == "p", let code = components.first {
            return code
        }
        if components.count == 2, components[0] == "p" {
            return components[1]
        }
        return nil
    }

    // MARK: - Primitives

    /// CRC-16/CCITT-FALSE. Not security — it catches the mistyped or truncated
    /// code that would otherwise decode into a different, legal-looking puzzle.
    static func crc16(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                crc = crc & 0x8000 != 0 ? (crc << 1) ^ 0x1021 : crc << 1
            }
        }
        return crc
    }

    /// base64url without padding: safe in a URL path, and nothing for a user to
    /// mistype into a different valid code.
    static func base64URLEncode(_ bytes: [UInt8]) -> String {
        Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64URLDecode(_ text: String) -> [UInt8]? {
        var padded =
            text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = padded.count % 4
        if remainder > 0 { padded += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: padded) else { return nil }
        return [UInt8](data)
    }
}

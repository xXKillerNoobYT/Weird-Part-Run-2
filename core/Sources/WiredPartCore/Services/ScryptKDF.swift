import Foundation
import CryptoKit

enum ScryptKDF {
    struct Parameters: Equatable {
        let logN: Int
        let r: Int
        let p: Int
        let dkLen: Int

        var n: Int { 1 << logN }
    }

    enum Error: Swift.Error {
        case invalidParameters
    }

    static func derive(password: Data, salt: Data, parameters: Parameters) throws -> Data {
        guard parameters.logN > 1,
              parameters.logN < Int.bitWidth - 1,
              parameters.r > 0,
              parameters.p > 0,
              parameters.dkLen > 0 else {
            throw Error.invalidParameters
        }

        let blockSize = 128 * parameters.r
        let initialLength = parameters.p * blockSize
        var b = pbkdf2SHA256(password: password, salt: salt, iterations: 1, keyLength: initialLength)

        for blockIndex in 0..<parameters.p {
            let offset = blockIndex * blockSize
            let mixed = try smix(Array(b[offset..<(offset + blockSize)]), r: parameters.r, n: parameters.n)
            b.replaceSubrange(offset..<(offset + blockSize), with: mixed)
        }

        return pbkdf2SHA256(password: password, salt: Data(b), iterations: 1, keyLength: parameters.dkLen)
    }

    private static func smix(_ block: [UInt8], r: Int, n: Int) throws -> [UInt8] {
        guard n > 1, n & (n - 1) == 0 else { throw Error.invalidParameters }

        let blockSize = 128 * r
        var x = block
        var v = Array(repeating: [UInt8](), count: n)

        for i in 0..<n {
            v[i] = x
            x = blockMixSalsa8(x, r: r)
        }

        for _ in 0..<n {
            let j = integerify(x, r: r) & UInt64(n - 1)
            x = xor(x, v[Int(j)])
            x = blockMixSalsa8(x, r: r)
        }

        precondition(x.count == blockSize)
        return x
    }

    private static func blockMixSalsa8(_ block: [UInt8], r: Int) -> [UInt8] {
        var x = Array(block[((2 * r - 1) * 64)..<((2 * r) * 64)])
        var y = Array(repeating: UInt8(0), count: block.count)

        for i in 0..<(2 * r) {
            let start = i * 64
            x = salsa208(xor(x, Array(block[start..<(start + 64)])))
            y.replaceSubrange(start..<(start + 64), with: x)
        }

        var output: [UInt8] = []
        output.reserveCapacity(block.count)
        for i in stride(from: 0, to: 2 * r, by: 2) {
            output.append(contentsOf: y[(i * 64)..<((i + 1) * 64)])
        }
        for i in stride(from: 1, to: 2 * r, by: 2) {
            output.append(contentsOf: y[(i * 64)..<((i + 1) * 64)])
        }
        return output
    }

    private static func salsa208(_ input: [UInt8]) -> [UInt8] {
        precondition(input.count == 64)
        var original: [UInt32] = []
        original.reserveCapacity(16)
        for offset in stride(from: 0, to: 64, by: 4) {
            let b0 = UInt32(input[offset])
            let b1 = UInt32(input[offset + 1]) << 8
            let b2 = UInt32(input[offset + 2]) << 16
            let b3 = UInt32(input[offset + 3]) << 24
            original.append(b0 | b1 | b2 | b3)
        }
        var x = original

        for _ in 0..<4 {
            x[4] ^= rotateLeft(x[0] &+ x[12], by: 7)
            x[8] ^= rotateLeft(x[4] &+ x[0], by: 9)
            x[12] ^= rotateLeft(x[8] &+ x[4], by: 13)
            x[0] ^= rotateLeft(x[12] &+ x[8], by: 18)
            x[9] ^= rotateLeft(x[5] &+ x[1], by: 7)
            x[13] ^= rotateLeft(x[9] &+ x[5], by: 9)
            x[1] ^= rotateLeft(x[13] &+ x[9], by: 13)
            x[5] ^= rotateLeft(x[1] &+ x[13], by: 18)
            x[14] ^= rotateLeft(x[10] &+ x[6], by: 7)
            x[2] ^= rotateLeft(x[14] &+ x[10], by: 9)
            x[6] ^= rotateLeft(x[2] &+ x[14], by: 13)
            x[10] ^= rotateLeft(x[6] &+ x[2], by: 18)
            x[3] ^= rotateLeft(x[15] &+ x[11], by: 7)
            x[7] ^= rotateLeft(x[3] &+ x[15], by: 9)
            x[11] ^= rotateLeft(x[7] &+ x[3], by: 13)
            x[15] ^= rotateLeft(x[11] &+ x[7], by: 18)

            x[1] ^= rotateLeft(x[0] &+ x[3], by: 7)
            x[2] ^= rotateLeft(x[1] &+ x[0], by: 9)
            x[3] ^= rotateLeft(x[2] &+ x[1], by: 13)
            x[0] ^= rotateLeft(x[3] &+ x[2], by: 18)
            x[6] ^= rotateLeft(x[5] &+ x[4], by: 7)
            x[7] ^= rotateLeft(x[6] &+ x[5], by: 9)
            x[4] ^= rotateLeft(x[7] &+ x[6], by: 13)
            x[5] ^= rotateLeft(x[4] &+ x[7], by: 18)
            x[11] ^= rotateLeft(x[10] &+ x[9], by: 7)
            x[8] ^= rotateLeft(x[11] &+ x[10], by: 9)
            x[9] ^= rotateLeft(x[8] &+ x[11], by: 13)
            x[10] ^= rotateLeft(x[9] &+ x[8], by: 18)
            x[12] ^= rotateLeft(x[15] &+ x[14], by: 7)
            x[13] ^= rotateLeft(x[12] &+ x[15], by: 9)
            x[14] ^= rotateLeft(x[13] &+ x[12], by: 13)
            x[15] ^= rotateLeft(x[14] &+ x[13], by: 18)
        }

        var output: [UInt8] = []
        output.reserveCapacity(64)
        for i in 0..<16 {
            let word = x[i] &+ original[i]
            output.append(UInt8(truncatingIfNeeded: word))
            output.append(UInt8(truncatingIfNeeded: word >> 8))
            output.append(UInt8(truncatingIfNeeded: word >> 16))
            output.append(UInt8(truncatingIfNeeded: word >> 24))
        }
        return output
    }

    private static func pbkdf2SHA256(password: Data, salt: Data, iterations: Int, keyLength: Int) -> Data {
        let hLen = 32
        let blockCount = Int(ceil(Double(keyLength) / Double(hLen)))
        let key = SymmetricKey(data: password)
        var output = Data()
        output.reserveCapacity(blockCount * hLen)

        for blockIndex in 1...blockCount {
            var blockSalt = Data(salt)
            blockSalt.append(UInt8((blockIndex >> 24) & 0xff))
            blockSalt.append(UInt8((blockIndex >> 16) & 0xff))
            blockSalt.append(UInt8((blockIndex >> 8) & 0xff))
            blockSalt.append(UInt8(blockIndex & 0xff))

            var u = Data(HMAC<SHA256>.authenticationCode(for: blockSalt, using: key))
            var t = u
            if iterations > 1 {
                for _ in 1..<iterations {
                    u = Data(HMAC<SHA256>.authenticationCode(for: u, using: key))
                    for i in 0..<t.count {
                        t[i] ^= u[i]
                    }
                }
            }
            output.append(t)
        }

        return output.prefix(keyLength)
    }

    private static func integerify(_ block: [UInt8], r: Int) -> UInt64 {
        let start = (2 * r - 1) * 64
        var value: UInt64 = 0
        for i in 0..<8 {
            value |= UInt64(block[start + i]) << UInt64(8 * i)
        }
        return value
    }

    private static func xor(_ lhs: [UInt8], _ rhs: [UInt8]) -> [UInt8] {
        precondition(lhs.count == rhs.count)
        return zip(lhs, rhs).map { $0 ^ $1 }
    }

    private static func rotateLeft(_ value: UInt32, by shift: UInt32) -> UInt32 {
        (value << shift) | (value >> (32 - shift))
    }
}

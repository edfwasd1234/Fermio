import Foundation

struct CinebyDecrypter {
    private static let u: [UInt32] = [
        1116352408, 1899447441, 3049323471, 3921009573, 961987163,
        1508970993, 2453635748, 2870763221, 3624381080, 310598401,
        607225278, 1426881987, 1925078388, 2162078206, 2614888103,
        3248222580
    ]
    private static let l: [UInt8] = [109, 118, 109, 49] // "mvm1"
    
    private static func c_func(_ e: Int) -> Bool {
        return ((e * (e + 1)) & 1) == 0
    }
    
    private static func s_func(_ e: Int) -> Bool {
        return ((e * (e + 1)) & 1) == 1
    }
    
    private static func f(_ e: UInt32) -> UInt32 {
        var val = e
        val ^= val >> 16
        val = UInt32(truncatingIfNeeded: UInt64(val) * 2246822507)
        val ^= val >> 13
        val = UInt32(truncatingIfNeeded: UInt64(val) * 3266489909)
        val ^= val >> 16
        return val
    }
    
    private static func d(_ e: UInt32, _ t: Int) -> UInt32 {
        let shift = t & 31
        if shift == 0 {
            return e
        }
        return (e << shift) | (e >> (32 - shift))
    }
    
    private static func fnv1a(_ str: String) -> UInt32 {
        var hash: UInt32 = 2166136261
        for char in str.utf8 {
            hash = UInt32(truncatingIfNeeded: UInt64(hash ^ UInt32(char)) * 16777619)
        }
        return f(hash)
    }
    
    class CipherState {
        var S: [UInt32]
        var isSet: [Bool]
        var acc: UInt32
        
        init(S: [UInt32], isSet: [Bool], acc: UInt32) {
            self.S = S
            self.isSet = isSet
            self.acc = acc
        }
    }
    
    private static func nextKeyStreamByte(state: CipherState, tIndex: Int) -> UInt32 {
        let i = Int(state.acc % 61)
        let exists = state.isSet[i]
        let uVal = exists ? -1 : 0
        let lVal = state.S[i]
        
        let r = state.acc
        let n = lVal ^ UInt32(truncatingIfNeeded: UInt64(2654435769) * UInt64(tIndex + 1))
        
        let xorVal = r ^ n
        let andVal = r & n & UInt32(bitPattern: Int32(uVal))
        let c = xorVal | andVal
        
        let term1 = d(c + state.acc, i)
        let term2 = d(state.acc, (i * 7) & 31)
        let newC = term1 ^ term2
        
        let nextAcc = f(UInt32(truncatingIfNeeded: UInt64(newC) + 2654435769))
        state.S[i] = nextAcc
        state.acc = nextAcc
        return nextAcc
    }
    
    static func decrypt(encryptedBase64: String, seed: String, mediaId: Int) throws -> String {
        guard let data = Data(base64Encoded: encryptedBase64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")) else {
            throw NSError(domain: "CinebyDecrypter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid base64 payload"])
        }
        
        let length = data.count
        let seedLen = seed.count
        let state: CipherState
        
        if s_func(seedLen) {
            var sBox = [UInt32](repeating: 0, count: 256)
            for i in 0..<256 { sBox[i] = UInt32(i) }
            var jVal = 0
            let seedCodes = seed.compactMap { $0.asciiValue }.map { Int($0) }
            for i in 0..<256 {
                jVal = (jVal + Int(sBox[i]) + seedCodes[i % seedCodes.count]) & 255
                sBox.swapAt(i, jVal)
            }
            
            var acc: UInt32 = 1732584193
            for (idx, charCode) in seedCodes.enumerated() {
                let factor = u[15 & idx]
                let term = UInt32(truncatingIfNeeded: UInt64(charCode) * UInt64(factor))
                acc = d(acc ^ term, 5)
            }
            acc = f(acc)
            
            let isSet = [Bool](repeating: true, count: 256)
            state = CipherState(S: sBox, isSet: isSet, acc: acc)
        } else {
            var rArr = [UInt32](repeating: 0, count: 61)
            var isSet = [Bool](repeating: false, count: 61)
            
            let fnvHash = fnv1a(seed)
            let idHash = f(UInt32(mediaId) ^ 2654435769)
            var n = f(fnvHash ^ idHash)
            
            for e in 0..<8 {
                if c_func(e) {
                    let t = Int(n % 61)
                    n = d(UInt32(truncatingIfNeeded: UInt64(n) + 2654435769), 7 + (7 & e))
                    rArr[t] = n ^ f(n)
                    isSet[t] = true
                    n = f(UInt32(truncatingIfNeeded: UInt64(n) + UInt64(t)))
                } else {
                    rArr[e] = u[15 & e]
                    isSet[e] = true
                }
            }
            
            let acc = f(2779096485 ^ n)
            state = CipherState(S: rArr, isSet: isSet, acc: acc)
        }
        
        var keyStream = Data(count: length)
        var aIndex = 0
        var byteIndex = 0
        
        while byteIndex < length {
            let keyWord = nextKeyStreamByte(state: state, tIndex: aIndex)
            aIndex += 1
            
            keyStream[byteIndex] = UInt8(keyWord & 255)
            byteIndex += 1
            
            if byteIndex < length {
                keyStream[byteIndex] = UInt8((keyWord >> 8) & 255)
                byteIndex += 1
            }
            if byteIndex < length {
                keyStream[byteIndex] = UInt8((keyWord >> 16) & 255)
                byteIndex += 1
            }
            if byteIndex < length {
                keyStream[byteIndex] = UInt8((keyWord >> 24) & 255)
                byteIndex += 1
            }
        }
        
        var decryptedBytes = [UInt8](repeating: 0, count: length)
        for i in 0..<length {
            decryptedBytes[i] = data[i] ^ keyStream[i]
        }
        
        for i in 0..<l.count {
            if decryptedBytes[i] != l[i] {
                throw NSError(domain: "CinebyDecrypter", code: 2, userInfo: [NSLocalizedDescriptionKey: "Decrypt failed: bad seed or tampered payload"])
            }
        }
        
        let payloadBytes = Array(decryptedBytes.suffix(from: l.count))
        guard let decryptedString = String(bytes: payloadBytes, encoding: .utf8) else {
            throw NSError(domain: "CinebyDecrypter", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to decode UTF-8 payload"])
        }
        
        return decryptedString
    }
}

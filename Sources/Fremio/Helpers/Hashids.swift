import Foundation

struct Hashids {
    private let salt: [Character]
    private let minLength: Int
    private let alphabet: [Character]
    private let seps: [Character]
    private let guards: [Character]
    
    init(salt: String = "", minLength: Int = 0) {
        self.minLength = minLength
        self.salt = Array(salt)
        
        let customAlphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890")
        let sepsInput = Array("cfhistuCFHISTU")
        
        // Remove seps from alphabet
        var tempAlphabet = customAlphabet.filter { !sepsInput.contains($0) }
        var tempSeps = sepsInput.filter { customAlphabet.contains($0) }
        
        tempSeps = Hashids.shuffle(tempSeps, salt: self.salt)
        
        if tempSeps.isEmpty || Double(tempAlphabet.count) / Double(tempSeps.count) > 3.5 {
            let n = Int(ceil(Double(tempAlphabet.count) / 3.5))
            if n > tempSeps.count {
                let diff = n - tempSeps.count
                tempSeps.append(contentsOf: tempAlphabet.prefix(diff))
                tempAlphabet.removeFirst(diff)
            }
        }
        
        tempAlphabet = Hashids.shuffle(tempAlphabet, salt: self.salt)
        
        let guardCount = Int(ceil(Double(tempAlphabet.count) / 12.0))
        var tempGuards: [Character]
        if tempAlphabet.count < 3 {
            tempGuards = Array(tempSeps.prefix(guardCount))
            tempSeps.removeFirst(guardCount)
        } else {
            tempGuards = Array(tempAlphabet.prefix(guardCount))
            tempAlphabet.removeFirst(guardCount)
        }
        
        self.alphabet = tempAlphabet
        self.seps = tempSeps
        self.guards = tempGuards
    }
    
    func encodeHex(_ hexStr: String) -> String {
        guard hexStr.range(of: "^[0-9a-fA-F]+$", options: .regularExpression) != nil else {
            return ""
        }
        
        var numbers: [Int] = []
        var remaining = hexStr
        while !remaining.isEmpty {
            let chunk = String(remaining.prefix(12))
            remaining = String(remaining.dropFirst(12))
            if let val = Int("1" + chunk, radix: 16) {
                numbers.append(val)
            }
        }
        return encode(numbers)
    }
    
    func encode(_ numbers: [Int]) -> String {
        guard !numbers.isEmpty else { return "" }
        return _encode(numbers)
    }
    
    private func _encode(_ numbers: [Int]) -> String {
        var currentAlphabet = self.alphabet
        let numbersHash = numbers.enumerated().reduce(0) { acc, next in
            acc + (next.element % (next.offset + 100))
        }
        
        let lottery = currentAlphabet[numbersHash % currentAlphabet.count]
        var result: [Character] = [lottery]
        
        for (idx, number) in numbers.enumerated() {
            let shuffleBuffer = result + self.salt + currentAlphabet
            currentAlphabet = Hashids.shuffle(currentAlphabet, salt: shuffleBuffer)
            
            let lastCode = currentAlphabet.count
            var num = number
            var tempResult: [Character] = []
            repeat {
                tempResult.insert(currentAlphabet[num % lastCode], at: 0)
                num = num / lastCode
            } while num > 0
            
            result.append(contentsOf: tempResult)
            
            if idx + 1 < numbers.count {
                let code = (Int(tempResult[0].unicodeScalars.first?.value ?? 0) + idx)
                let nextNum = numbers[idx + 1]
                let sepsIdx = (nextNum % (code > 0 ? code : 1)) % self.seps.count
                result.append(self.seps[sepsIdx])
            }
        }
        
        if result.count < self.minLength {
            let guardIdx = (numbersHash + Int(result[0].unicodeScalars.first?.value ?? 0)) % self.guards.count
            result.insert(self.guards[guardIdx], at: 0)
            
            if result.count < self.minLength {
                let guardIdx2 = (numbersHash + Int(result[2].unicodeScalars.first?.value ?? 0)) % self.guards.count
                result.append(self.guards[guardIdx2])
            }
        }
        
        let halfLen = currentAlphabet.count / 2
        while result.count < self.minLength {
            currentAlphabet = Hashids.shuffle(currentAlphabet, salt: currentAlphabet)
            result = Array(currentAlphabet.suffix(from: halfLen)) + result + Array(currentAlphabet.prefix(halfLen))
            
            let excess = result.count - self.minLength
            if excess > 0 {
                let start = excess / 2
                result = Array(result[start..<(start + self.minLength)])
            }
        }
        
        return String(result)
    }
    
    private static func shuffle(_ alphabet: [Character], salt: [Character]) -> [Character] {
        guard !salt.isEmpty else { return alphabet }
        var result = alphabet
        var v = 0
        var p = 0
        var saltIdx = 0
        
        for i in stride(from: result.count - 1, to: 0, by: -1) {
            saltIdx = p % salt.count
            let code = Int(salt[saltIdx].unicodeScalars.first?.value ?? 0)
            v += code
            let swapIdx = (code + p + v) % i
            result.swapAt(i, swapIdx)
            p += 1
        }
        return result
    }
}

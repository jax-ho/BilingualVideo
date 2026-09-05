import CryptoKit
import Foundation
import LocalAuthentication
import Security

@MainActor
final class ParentAccessService {
    enum AccessError: LocalizedError {
        case invalidPINFormat
        case authenticationUnavailable
        case authenticationFailed
        case keychain(OSStatus)
        case invalidStoredRecord
        case randomGeneration(OSStatus)

        var errorDescription: String? {
            switch self {
            case .invalidPINFormat:
                "PIN 必须是 4–6 位数字"
            case .authenticationUnavailable:
                "这台 iPad 未设置可用的设备验证，无法重设 PIN。"
            case .authenticationFailed:
                "未能验证设备所有者，PIN 未更改。"
            case .keychain:
                "无法安全访问家长 PIN，请稍后再试。"
            case .invalidStoredRecord:
                "家长 PIN 数据不可用，请使用“忘记 PIN”重设。"
            case .randomGeneration:
                "无法创建安全的家长 PIN，请稍后再试。"
            }
        }
    }

    private struct PINRecord: Codable {
        let version: Int
        let salt: Data
        let digest: Data
    }

    private let service: String
    private let account = "parent-pin"

    init(service: String = Bundle.main.bundleIdentifier ?? "com.jax.BilingualVideo") {
        self.service = service
    }

    static func isValidPIN(_ pin: String) -> Bool {
        (4...6).contains(pin.utf8.count) && pin.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
    }

    func hasPIN() throws -> Bool {
        try loadRecord() != nil
    }

    func setPIN(_ pin: String) throws {
        guard Self.isValidPIN(pin) else { throw AccessError.invalidPINFormat }

        var saltBytes = [UInt8](repeating: 0, count: 32)
        let randomStatus = SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes)
        guard randomStatus == errSecSuccess else {
            throw AccessError.randomGeneration(randomStatus)
        }

        let salt = Data(saltBytes)
        let record = PINRecord(version: 1, salt: salt, digest: digest(pin: pin, salt: salt))
        let recordData = try JSONEncoder().encode(record)
        try upsert(recordData)
    }

    func verifyPIN(_ pin: String) throws -> Bool {
        guard Self.isValidPIN(pin), let record = try loadRecord(), record.version == 1 else {
            return false
        }
        let candidate = digest(pin: pin, salt: record.salt)
        return constantTimeEqual(candidate, record.digest)
    }

    func authenticateDeviceOwnerForReset() async throws {
        let context = LAContext()
        context.localizedCancelTitle = "取消"
        var evaluationError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evaluationError) else {
            throw AccessError.authenticationUnavailable
        }

        do {
            let authenticated = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "验证设备所有者后可重设家长 PIN"
            )
            guard authenticated else { throw AccessError.authenticationFailed }
        } catch {
            throw AccessError.authenticationFailed
        }
    }

    private func digest(pin: String, salt: Data) -> Data {
        var input = Data()
        input.append(salt)
        input.append(contentsOf: pin.utf8)
        return Data(SHA256.hash(data: input))
    }

    private func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) {
            difference |= left ^ right
        }
        return difference == 0
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func loadRecord() throws -> PINRecord? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw AccessError.keychain(status) }
        guard let data = result as? Data,
              let record = try? JSONDecoder().decode(PINRecord.self, from: data) else {
            throw AccessError.invalidStoredRecord
        }
        return record
    }

    private func upsert(_ data: Data) throws {
        let query = baseQuery()
        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw AccessError.keychain(updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw AccessError.keychain(addStatus) }
    }
}

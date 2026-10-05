import Foundation
import Security

protocol CredentialStoring: Sendable {
  func storeCredential(_ credential: String, for account: String) throws
  func readCredential(for account: String) throws -> String?
  func deleteCredential(for account: String) throws
  func credentialExists(for account: String) throws -> Bool
}

enum CredentialStoreError: Error, Equatable, Sendable {
  case invalidAccount
  case invalidCredential
  case encodingFailed
  case decodingFailed
  case unavailable
}

/// Generic-password Keychain storage. The secret is never written to
/// preferences, files, logs, or provider configuration metadata.
struct KeychainCredentialStore: CredentialStoring, Sendable {
  static let defaultServiceSuffix = ".llm"

  let service: String

  init(
    service: String = (Bundle.main.bundleIdentifier ?? "com.baihuaai.AITutorMac")
      + Self.defaultServiceSuffix
  ) {
    self.service = service
  }

  func storeCredential(_ credential: String, for account: String) throws {
    let account = try validatedAccount(account)
    guard credential.contains(where: { !$0.isWhitespace }) else {
      throw CredentialStoreError.invalidCredential
    }
    guard let data = credential.data(using: .utf8) else {
      throw CredentialStoreError.encodingFailed
    }

    let query = baseQuery(account: account)
    let updateStatus = SecItemUpdate(
      query as CFDictionary,
      [kSecValueData as String: data] as CFDictionary
    )
    switch updateStatus {
    case errSecSuccess:
      return
    case errSecItemNotFound:
      var newItem = query
      newItem[kSecValueData as String] = data
      newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      guard SecItemAdd(newItem as CFDictionary, nil) == errSecSuccess else {
        throw CredentialStoreError.unavailable
      }
    default:
      throw CredentialStoreError.unavailable
    }
  }

  func readCredential(for account: String) throws -> String? {
    let account = try validatedAccount(account)
    var query = baseQuery(account: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    switch status {
    case errSecSuccess:
      guard
        let data = result as? Data,
        let credential = String(data: data, encoding: .utf8)
      else {
        throw CredentialStoreError.decodingFailed
      }
      return credential
    case errSecItemNotFound:
      return nil
    default:
      throw CredentialStoreError.unavailable
    }
  }

  func deleteCredential(for account: String) throws {
    let account = try validatedAccount(account)
    let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw CredentialStoreError.unavailable
    }
  }

  func credentialExists(for account: String) throws -> Bool {
    let account = try validatedAccount(account)
    var query = baseQuery(account: account)
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    switch SecItemCopyMatching(query as CFDictionary, nil) {
    case errSecSuccess:
      return true
    case errSecItemNotFound:
      return false
    default:
      throw CredentialStoreError.unavailable
    }
  }

  private func baseQuery(account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }

  private func validatedAccount(_ account: String) throws -> String {
    let value = account.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else {
      throw CredentialStoreError.invalidAccount
    }
    return value
  }
}

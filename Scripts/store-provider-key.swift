import Foundation
import Security

enum SetupKeyError: Error, LocalizedError {
  case usage, invalidInput, keychain(OSStatus), verification

  var errorDescription: String? { "Could not save the provider setup key." }
  var failureReason: String? {
    switch self {
      case .usage: "Usage: pbpaste | swift Scripts/store-provider-key.swift openai|gemini|claude"
      case .invalidInput: "No recognizable provider key was received; nothing was saved."
      case .keychain(let status): "Keychain returned status \(status)."
      case .verification: "The saved Keychain value could not be verified."
    }
  }
}

func storeSetupKey() throws {
  let providers = ["openai": "openai", "gemini": "gemini", "claude": "anthropic"]
  guard CommandLine.arguments.count == 2,
    let provider = providers[CommandLine.arguments[1]]
  else { throw SetupKeyError.usage }
  let maximumKeyBytes = 512
  let input = FileHandle.standardInput.readData(ofLength: maximumKeyBytes + 1)
  guard input.count <= maximumKeyBytes, let text = String(data: input, encoding: .utf8) else {
    throw SetupKeyError.invalidInput
  }
  let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
  let prefix = provider == "gemini" ? "AIza" : "sk-"
  guard key.hasPrefix(prefix), key.count >= 20, !key.contains(where: \.isWhitespace) else {
    throw SetupKeyError.invalidInput
  }
  let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "codes.tim.SpamWise.\(provider).setup",
    kSecAttrAccount as String: "user-api-key"
  ]
  let secret = Data(key.utf8)
  var status = SecItemUpdate(
    query as CFDictionary,
    [kSecValueData as String: secret] as CFDictionary
  )
  if status == errSecItemNotFound {
    var item = query
    item[kSecValueData as String] = secret
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    status = SecItemAdd(item as CFDictionary, nil)
  }
  guard status == errSecSuccess else { throw SetupKeyError.keychain(status) }
  var check = query
  check[kSecReturnData as String] = true
  var result: CFTypeRef?
  let checked = unsafe SecItemCopyMatching(check as CFDictionary, &result)
  guard checked == errSecSuccess, result as? Data == secret else {
    throw SetupKeyError.verification
  }
  print("Setup key saved and verified in login Keychain. No plaintext file was created.")
}

do {
  try storeSetupKey()
} catch {
  let message = (error as? LocalizedError)?.failureReason ?? "Unexpected setup failure."
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(1)
}

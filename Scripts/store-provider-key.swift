import Foundation
import Security

// Saves a provider API key as a login-Keychain setup item for the evaluation tools.
//
//   swift Scripts/store-provider-key.swift openai|gemini|claude
//   op read "op://…" | swift Scripts/store-provider-key.swift openai|gemini|claude
//
// On a terminal it asks for the key without echoing it; otherwise it reads the key from
// standard input.

enum SetupKeyError: Error, LocalizedError {
  case usage, invalidInput, keychain(OSStatus), verification

  var errorDescription: String? { "Could not save the provider setup key." }
  var failureReason: String? {
    switch self {
      case .usage: "Usage: swift Scripts/store-provider-key.swift openai|gemini|claude"
      case .invalidInput: "No recognizable provider key was received; nothing was saved."
      case .keychain(let status): "Keychain returned status \(status)."
      case .verification: "The saved Keychain value could not be verified."
    }
  }
}

let maximumKeyBytes = 512

/// Reads the key from a no-echo prompt on a terminal, or from standard input otherwise.
func readKey() throws -> String {
  guard isatty(STDIN_FILENO) == 1 else {
    let input = FileHandle.standardInput.readData(ofLength: maximumKeyBytes + 1)
    guard input.count <= maximumKeyBytes, let text = String(data: input, encoding: .utf8) else {
      throw SetupKeyError.invalidInput
    }
    return text
  }
  var buffer = [CChar](repeating: 0, count: maximumKeyBytes + 2)
  guard
    unsafe readpassphrase("Provider API key: ", &buffer, buffer.count, RPP_REQUIRE_TTY) != nil
  else { throw SetupKeyError.invalidInput }
  let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
  guard bytes.count <= maximumKeyBytes, let text = String(bytes: bytes, encoding: .utf8) else {
    throw SetupKeyError.invalidInput
  }
  return text
}

func storeSetupKey() throws {
  let providers = ["openai": "openai", "gemini": "gemini", "claude": "anthropic"]
  guard CommandLine.arguments.count == 2,
    let provider = providers[CommandLine.arguments[1]]
  else { throw SetupKeyError.usage }
  let key = try readKey().trimmingCharacters(in: .whitespacesAndNewlines)
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

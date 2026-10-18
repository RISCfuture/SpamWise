import Foundation
import Security

protocol EvaluationSetupFailure: Error {}

enum EvaluationSetupError: EvaluationSetupFailure, LocalizedError {
  case usage, missingExecutable, credential(OSStatus)

  var errorDescription: String? { "Could not start provider evaluation." }
  var failureReason: String? {
    switch self {
      case .usage:
        "Usage: swift Scripts/evaluate-with-keychain.swift EXECUTABLE claude|openai|gemini --live corpus|reviewed INPUT --budget-store PATH EVAL_OPTIONS"
      case .missingExecutable: "The supplied evaluation executable is unavailable."
      case .credential(let status):
        "The provider setup key is unavailable; Keychain status \(status)."
    }
  }
}

struct EvaluationProvider {
  let service: String
  let variable: String
  let model: String

  init(_ name: String) throws {
    switch name {
      case "claude":
        service = "anthropic"; variable = "ANTHROPIC_API_KEY"; model = "claude-haiku-5-5"
      case "openai":
        service = "openai"; variable = "OPENAI_API_KEY"; model = "gpt-5.4-mini"
      case "gemini":
        service = "gemini"; variable = "GEMINI_API_KEY"; model = "gemini-3.8-flash"
      default: throw EvaluationSetupError.usage
    }
  }

  func credential() throws -> String {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "codes.tim.SpamWise.\(service).setup",
      kSecAttrAccount as String: "user-api-key",
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var item: CFTypeRef?
    let status = unsafe SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data,
      let value = String(data: data, encoding: .utf8), !value.isEmpty
    else { throw EvaluationSetupError.credential(status) }
    return value
  }
}

func runEvaluation() throws -> Int32 {
  let arguments = Array(CommandLine.arguments.dropFirst())
  guard arguments.count >= 6, arguments[2] == "--live",
    ["corpus", "reviewed"].contains(arguments[3]),
    arguments.dropFirst(4).contains("--budget-store"),
    !arguments.dropFirst(4).contains("--model")
  else { throw EvaluationSetupError.usage }
  let executable = URL(filePath: arguments[0]), provider = try EvaluationProvider(arguments[1])
  guard FileManager.default.isExecutableFile(atPath: executable.path) else {
    throw EvaluationSetupError.missingExecutable
  }
  var environment = ProcessInfo.processInfo.environment
  for variable in ["ANTHROPIC_API_KEY", "OPENAI_API_KEY", "GEMINI_API_KEY"] {
    environment.removeValue(forKey: variable)
  }
  environment[provider.variable] = try provider.credential()
  environment["SPAMWISE_LIVE_API"] = "1"
  let process = Process()
  process.executableURL = executable
  process.arguments =
    [arguments[3], "--model", provider.model] + arguments.dropFirst(4)
  process.environment = environment
  try process.run()
  process.waitUntilExit()
  return process.terminationStatus
}

do {
  exit(try runEvaluation())
} catch {
  let description =
    (error as? EvaluationSetupError)?.failureReason
    ?? "Evaluation could not start. Check the executable and budget store."
  FileHandle.standardError.write(Data((description + "\n").utf8))
  exit(1)
}

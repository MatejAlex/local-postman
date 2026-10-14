import Foundation

// The MCP side of the app: which methods can be sent, and what each one needs.
// MCP over Streamable HTTP is JSON-RPC over POST, so an MCP request is an
// ordinary HTTP request with a fixed shape.

/// The protocol revision advertised on `initialize`.
public let mcpProtocolVersion = "2025-06-18"

public enum McpMethod: String, Codable, CaseIterable, Sendable {
    case toolsList = "tools/list"
    case toolsCall = "tools/call"
    case promptsList = "prompts/list"
    case promptsGet = "prompts/get"
    case resourcesList = "resources/list"
    case resourcesRead = "resources/read"
    case ping = "ping"

    /// What the target is called, for the methods that need one. The list
    /// methods need nothing, which is what makes them the safe first click.
    public var targetLabel: String? {
        switch self {
        case .toolsCall: "Tool name"
        case .promptsGet: "Prompt name"
        case .resourcesRead: "Resource URI"
        default: nil
        }
    }

    public var needsTarget: Bool { targetLabel != nil }

    /// Methods that take a free-form JSON argument object.
    public var takesArguments: Bool { self == .toolsCall || self == .promptsGet }
}

public struct McpConfig: Codable, Hashable, Sendable {
    public var method: McpMethod
    /// Tool name, prompt name or resource URI, depending on `method`.
    public var target: String
    /// JSON object of arguments, as typed. Empty means "no arguments".
    public var args: String

    public init(method: McpMethod = .toolsList, target: String = "", args: String = "") {
        self.method = method
        self.target = target
        self.args = args
    }
}

/// Turn a config into JSON-RPC params, or explain why it cannot be.
///
/// Bad JSON in the arguments box is caught here rather than at the server, so
/// the message names the box the user is looking at instead of arriving as a
/// protocol error from three hops away.
public func mcpParams(for config: McpConfig) -> Result<[String: JSONValue], ResolveError> {
    let method = config.method
    let target = config.target.trimmingCharacters(in: .whitespacesAndNewlines)

    if let label = method.targetLabel, target.isEmpty {
        return .failure(ResolveError("\(label) is required for \(method.rawValue)."))
    }

    var args: [String: JSONValue] = [:]
    if method.takesArguments, !config.args.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        guard let data = config.args.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil,
              let parsed = JSONValue.parse(config.args)
        else {
            return .failure(ResolveError("Arguments are not valid JSON."))
        }
        guard case .object(let object) = parsed else {
            return .failure(ResolveError(#"Arguments must be a JSON object, e.g. {"query": "payrun"}."#))
        }
        args = object
    }

    switch method {
    case .toolsCall, .promptsGet:
        return .success(["name": .string(target), "arguments": .object(args)])
    case .resourcesRead:
        return .success(["uri": .string(target)])
    default:
        return .success([:])
    }
}

public struct ResolveError: Error, Equatable, Sendable {
    public var message: String
    public init(_ message: String) { self.message = message }
}

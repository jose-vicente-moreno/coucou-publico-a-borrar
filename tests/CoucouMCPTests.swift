import Foundation

/// CoucouMCP needs only HookServer.supportDir from the app.
enum HookServer {
    static var supportDir: URL { URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("coucou-mcp-tests") }
}

/// Tool conversion and config for the voice MCP bridge. With a path argument, also
/// writes the relay script there for tests/coucou_mcp_check.py.
@main
enum CoucouMCPTests {
    static func main() {
        var cases = 0
        func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
            precondition(condition, "\(name) failed \(detail())")
            cases += 1
        }

        let anthropicTools: [[String: Any]] = [
            ["name": "music", "description": "Control music.",
             "input_schema": ["type": "object", "properties": ["action": ["type": "string"]], "required": ["action"]]],
            ["type": "web_search_20250305", "name": "web_search", "max_uses": 3],
        ]
        let tools = CoucouMCP.mcpTools(from: anthropicTools)
        check("server tools are left out", tools.count == 1, "\(tools)")
        check("name kept", tools.first?["name"] as? String == "music")
        check("description kept", tools.first?["description"] as? String == "Control music.")
        let schema = tools.first?["inputSchema"] as? [String: Any]
        check("input_schema becomes inputSchema", schema?["type"] as? String == "object")
        check("no Anthropic key left", tools.first?["input_schema"] == nil)

        let result = CoucouMCP.callResult(text: "Paused.", isError: false)
        let content = result["content"] as? [[String: Any]]
        check("call result text", content?.first?["text"] as? String == "Paused." && content?.first?["type"] as? String == "text")
        check("call result flag", result["isError"] as? Bool == false)

        let config = (try? JSONSerialization.jsonObject(with: Data(CoucouMCP.configJSON.utf8))) as? [String: Any]
        let server = (config?["mcpServers"] as? [String: Any])?["coucou"] as? [String: Any]
        check("stdio server named coucou", server?["type"] as? String == "stdio")
        check("runs the script with python3", server?["command"] as? String == "/usr/bin/python3"
              && (server?["args"] as? [String])?.first == CoucouMCP.scriptURL.path)

        check("per-launch token handed to the relay",
              (server?["env"] as? [String: String])?["COUCOU_MCP_TOKEN"] == CoucouMCP.token && !CoucouMCP.token.isEmpty)
        check("script is self-contained python", CoucouMCP.script.hasPrefix("#!/usr/bin/env python3"))
        if CommandLine.arguments.count > 1 {
            try! CoucouMCP.script.write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)
        }
        print("CoucouMCPTests: \(cases) cases passed")
    }
}

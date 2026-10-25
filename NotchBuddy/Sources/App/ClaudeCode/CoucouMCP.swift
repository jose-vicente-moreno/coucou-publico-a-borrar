#if !APPSTORE
import Foundation

/// Coucou's voice tools (pills, music, service_info, open_app, prepare_email) as an MCP
/// server for the Claude Code voice brain. Claude Code starts `coucou-mcp.py` (stdio);
/// the script relays `tools/list` and `tools/call` to the app over the hook socket
/// (`coucou_kind: "mcp_voice"`), where ClaudeVoiceBrain runs the tool. The app only
/// accepts tool calls while one of its own voice turns is running.
enum CoucouMCP {
    static let serverName = "coucou"
    /// New at every launch, handed to the relay through its environment: only the
    /// voice sessions Coucou starts itself can call the tools.
    static let token = UUID().uuidString

    static var scriptURL: URL { HookServer.supportDir.appendingPathComponent("coucou-mcp.py") }

    /// Written at launch next to nb-hook (same folder, same permissions).
    static func install() {
        try? script.write(to: scriptURL, atomically: true, encoding: .utf8)
        _ = try? FileManager.default.setAttributes([.posixPermissions: 0o700 as NSNumber], ofItemAtPath: scriptURL.path)
    }

    /// `--mcp-config` for the voice session.
    static var configJSON: String {
        let config: [String: Any] = ["mcpServers": [serverName: [
            "type": "stdio", "command": "/usr/bin/python3", "args": [scriptURL.path],
            "env": ["COUCOU_MCP_TOKEN": token],
        ]]]
        let data = (try? JSONSerialization.data(withJSONObject: config, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Anthropic tool definitions → MCP `tools/list` entries. Server tools (web search)
    /// have no input schema and stay out: Claude Code brings its own WebSearch.
    static func mcpTools(from tools: [[String: Any]]) -> [[String: Any]] {
        tools.compactMap { tool in
            guard let name = tool["name"] as? String, let schema = tool["input_schema"] as? [String: Any] else { return nil }
            return ["name": name, "description": tool["description"] as? String ?? "", "inputSchema": schema]
        }
    }

    /// `tools/call` result in MCP's shape.
    static func callResult(text: String, isError: Bool) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": isError]
    }

    static func json(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    static let script = #"""
#!/usr/bin/env python3
# coucou-mcp.py - Coucou's voice tools as an MCP server (stdio) for Claude Code.
# Written by Coucou at launch; every call is relayed to the app over its socket.
import json, os, socket, sys

SOCK = os.environ.get('COUCOU_MCP_SOCKET') or os.path.expanduser(
    '~/Library/Application Support/NotchBuddy/nb.sock')
TOKEN = os.environ.get('COUCOU_MCP_TOKEN', '')


def ask_app(message, timeout):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout)
    try:
        s.connect(SOCK)
        message['token'] = TOKEN
        s.sendall((json.dumps(message) + '\n').encode('utf-8'))
        data = b''
        while not data.endswith(b'\n'):
            chunk = s.recv(65536)
            if not chunk:
                break
            data += chunk
        return json.loads(data.decode('utf-8') or '{}')
    finally:
        s.close()


def reply(req_id, result=None, error=None):
    msg = {'jsonrpc': '2.0', 'id': req_id}
    if error is not None:
        msg['error'] = error
    else:
        msg['result'] = result
    sys.stdout.write(json.dumps(msg) + '\n')
    sys.stdout.flush()


for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        req = json.loads(line)
    except ValueError:
        continue
    method = req.get('method')
    req_id = req.get('id')
    if req_id is None:
        continue  # notifications (initialized, cancelled...)
    params = req.get('params') or {}
    if method == 'initialize':
        reply(req_id, {'protocolVersion': params.get('protocolVersion') or '2025-06-18',
                       'capabilities': {'tools': {}},
                       'serverInfo': {'name': 'coucou', 'version': '1.0'}})
    elif method == 'ping':
        reply(req_id, {})
    elif method == 'tools/list':
        try:
            result = ask_app({'coucou_kind': 'mcp_voice', 'method': 'tools/list'}, 5)
        except Exception:
            result = {}
        reply(req_id, {'tools': result.get('tools', [])})
    elif method == 'tools/call':
        try:
            result = ask_app({'coucou_kind': 'mcp_voice', 'method': 'tools/call',
                              'name': params.get('name', ''),
                              'arguments': params.get('arguments') or {}}, 60)
        except Exception as error:
            result = {'content': [{'type': 'text', 'text': 'Coucou did not answer: %s' % error}],
                      'isError': True}
        reply(req_id, result)
    else:
        reply(req_id, error={'code': -32601, 'message': 'Method not found: %s' % method})
"""#
}
#endif

#!/usr/bin/env python3
"""Drives coucou-mcp.py like Claude Code would, against a fake Coucou socket.

Usage: coucou_mcp_check.py <path to coucou-mcp.py> <temp dir>
"""
import json
import os
import socket
import subprocess
import sys
import threading

script, tmp = sys.argv[1], sys.argv[2]
sock_path = os.path.join(tmp, 'nb.sock')
seen = []


def fake_app():
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(sock_path)
    server.listen(4)
    while True:
        conn, _ = server.accept()
        data = b''
        while not data.endswith(b'\n'):
            chunk = conn.recv(65536)
            if not chunk:
                break
            data += chunk
        msg = json.loads(data.decode())
        seen.append(msg)
        if msg.get('method') == 'tools/list':
            answer = {'tools': [{'name': 'music', 'description': 'd', 'inputSchema': {'type': 'object'}}]}
        else:
            answer = {'content': [{'type': 'text', 'text': 'ran %s %s' % (msg['name'], json.dumps(msg['arguments']))}],
                      'isError': False}
        conn.sendall((json.dumps(answer) + '\n').encode())
        conn.close()


threading.Thread(target=fake_app, daemon=True).start()
while not os.path.exists(sock_path):
    pass

env = dict(os.environ, COUCOU_MCP_SOCKET=sock_path, COUCOU_MCP_TOKEN='launch-token')
proc = subprocess.Popen([sys.executable, script], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, env=env)


def rpc(obj, expect_reply=True):
    proc.stdin.write(json.dumps(obj) + '\n')
    proc.stdin.flush()
    return json.loads(proc.stdout.readline()) if expect_reply else None


cases = 0


def check(name, cond, detail=''):
    global cases
    assert cond, '%s failed %s' % (name, detail)
    cases += 1


init = rpc({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize',
            'params': {'protocolVersion': '2025-06-18', 'capabilities': {}, 'clientInfo': {'name': 't'}}})
check('initialize echoes the protocol version', init['result']['protocolVersion'] == '2025-06-18', init)
check('initialize announces tools', 'tools' in init['result']['capabilities'], init)
check('server name', init['result']['serverInfo']['name'] == 'coucou', init)
rpc({'jsonrpc': '2.0', 'method': 'notifications/initialized'}, expect_reply=False)
check('ping', rpc({'jsonrpc': '2.0', 'id': 2, 'method': 'ping'})['result'] == {})
listed = rpc({'jsonrpc': '2.0', 'id': 3, 'method': 'tools/list'})
check('tools come from the app', listed['result']['tools'][0]['name'] == 'music', listed)
called = rpc({'jsonrpc': '2.0', 'id': 4, 'method': 'tools/call',
              'params': {'name': 'music', 'arguments': {'action': 'pause'}}})
check('call relayed with its arguments', called['result']['content'][0]['text'] == 'ran music {"action": "pause"}', called)
check('call id kept', called['id'] == 4)
check('app saw the voice kind', all(m.get('coucou_kind') == 'mcp_voice' for m in seen), seen)
check('every request carries the launch token', all(m.get('token') == 'launch-token' for m in seen), seen)
unknown = rpc({'jsonrpc': '2.0', 'id': 5, 'method': 'resources/list'})
check('unknown method is an error', unknown['error']['code'] == -32601, unknown)

os.remove(sock_path)
down = rpc({'jsonrpc': '2.0', 'id': 6, 'method': 'tools/call', 'params': {'name': 'music', 'arguments': {}}})
check('app not running: error result, no crash', down['result']['isError'] is True, down)

proc.stdin.close()
proc.wait(timeout=5)
check('exits on EOF', proc.returncode == 0)
print('coucou_mcp_check: %d cases passed' % cases)

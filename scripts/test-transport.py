#!/usr/bin/env python3
"""Exercise the Swift client against a loopback-only API fixture; no real key or provider."""
import json
import os
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

state = {"cancelled": 0, "requests": []}
markdown_chunks = ["    let value = 1\n\n## Heading\n\n- **bo", "ld**\n\n| A | B |\n", "| --- | --- |\n", "| one | two |\n\n", "```swift\nlet x = 2\n", "```\n\nhard break  \n"]
markdown_output = "".join(markdown_chunks)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        body = json.dumps({"cancelled": state["cancelled"]}).encode()
        self.send_response(200)
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        query = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        state["requests"].append(query)
        assert self.path == "/v1/chat/completions", self.path
        assert self.headers["Authorization"] == "Bearer test-only"
        if query["model"] == "error":
            self.send_response(401)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"error":{"message":"Fixture unauthorized","type":"invalid_api_key","code":"invalid_api_key"}}')
            return
        if query.get("stream"):
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            chunks = markdown_chunks if query["model"] == "markdown" else (["Hello ", "世界"] if query["model"] != "slow" else ["part "] * 100)
            try:
                for content in chunks:
                    event = {"id": "fixture", "object": "chat.completion.chunk", "created": 1, "model": query["model"],
                             "choices": [{"index": 0, "delta": {"content": content}, "finish_reason": None}]}
                    self.wfile.write(("data: " + json.dumps(event) + "\n\n").encode())
                    self.wfile.flush()
                    time.sleep(0.06)
                self.wfile.write(b"data: [DONE]\n\n")
            except (BrokenPipeError, ConnectionResetError):
                state["cancelled"] += 1
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({"id": "fixture", "object": "chat.completion", "created": 1, "model": query["model"],
                                     "choices": [{"index": 0, "message": {"role": "assistant", "content": markdown_output if query["model"] == "markdown" else "Hello 世界"}, "finish_reason": "stop"}]}).encode())


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    env = dict(os.environ, DIGGER_TEST_ENDPOINT=f"http://127.0.0.1:{server.server_port}/v1")
    result = subprocess.run(["swift", "test"], env=env)
    if result.returncode:
        raise SystemExit(result.returncode)
    assert state["requests"], "No fixture requests received"
    reasoning = [q for q in state["requests"] if q.get("reasoning_effort") == "high"]
    assert reasoning and all("temperature" not in q for q in reasoning)
    for query in state["requests"]:
        messages = query["messages"]
        assert messages[0]["content"] == "Fixture system"
        assert messages[1]["content"].startswith("Fixture prompt\n\nWhen the input is Markdown")
        assert "Keep code, URLs, and link destinations unchanged" in messages[1]["content"]
        assert "extra Markdown code fence" in messages[1]["content"]
        expected = "    let source = 1\n\n# Source\n" if query["model"] == "markdown" else "Fixture selection"
        assert messages[2]["content"] == expected
    print(f"Verified {len(state['requests'])} local requests, reasoning payloads, and cancellation.")
finally:
    server.shutdown()

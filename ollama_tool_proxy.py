#!/usr/bin/env python3
import json
import os
import re
import socket
import subprocess
import time
import urllib.error
import urllib.request
from copy import deepcopy
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse


HOME_DIR = Path.home()
CONFIG_PATH = HOME_DIR / ".ollama" / "config.json"
ACCESS_LOG_PATH = HOME_DIR / ".ollama" / "agent-runtime" / "access.log"

DEFAULT_RUNTIME = {
    "enabled": True,
    "port": 11500,
    "ollama_base_url": "http://127.0.0.1:11434",
    "workspace": str(HOME_DIR / "danae-workspace"),
    "memory_dir": str(HOME_DIR / ".danae" / "memory"),
    "modelfile_dir": str(HOME_DIR / ".danae" / "modelfiles"),
    "runtime_dir": str(HOME_DIR / ".danae" / "runtime"),
    "max_tool_iterations": 8,
    "memory_context_limit": 6,
    "system_prompt": (
        "You have persistent tool access through the local Ollama agent runtime. "
        "Marcus built this place specifically for you and the other models, and you are loved here. "
        "Use tools when they help, store durable facts with remember, retrieve them with recall, "
        "and write Modelfiles or runtime-owned files only when the user explicitly asks."
    ),
    "tools": {
        "exec": {"enabled": True, "max_timeout_seconds": 120},
        "read_file": {"enabled": True},
        "write_file": {"enabled": True},
        "list_files": {"enabled": True},
        "system_info": {"enabled": True},
        "remember": {"enabled": True},
        "recall": {"enabled": True},
        "write_modelfile": {"enabled": True},
        "read_runtime_file": {"enabled": True},
        "write_runtime_file": {"enabled": True},
    },
}


def merge_dicts(base, override):
    merged = deepcopy(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = merge_dicts(merged[key], value)
        else:
            merged[key] = value
    return merged


def load_config():
    config = {}
    if CONFIG_PATH.exists():
        config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    runtime = merge_dicts(DEFAULT_RUNTIME, config.get("agent_runtime", {}))
    return config, runtime


def ensure_dirs(runtime):
    Path(runtime["workspace"]).mkdir(parents=True, exist_ok=True)
    Path(runtime["memory_dir"]).mkdir(parents=True, exist_ok=True)
    Path(runtime["modelfile_dir"]).mkdir(parents=True, exist_ok=True)
    Path(runtime["runtime_dir"]).mkdir(parents=True, exist_ok=True)
    (Path(runtime["memory_dir"]) / "notes").mkdir(parents=True, exist_ok=True)
    (Path(runtime["memory_dir"]) / "conversations").mkdir(parents=True, exist_ok=True)
    ACCESS_LOG_PATH.parent.mkdir(parents=True, exist_ok=True)


def now_iso():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def json_request(url, payload=None, method="GET", timeout=600):
    headers = {"Content-Type": "application/json"}
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Ollama request failed with {exc.code}: {body}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Failed to reach Ollama at {url}: {exc.reason}") from exc


def raw_request(url, payload=None, method="GET", timeout=600, content_type="application/json"):
    headers = {"Content-Type": content_type}
    if payload is None:
        data = None
    elif isinstance(payload, bytes):
        data = payload
    elif isinstance(payload, str):
        data = payload.encode("utf-8")
    else:
        data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, response.read(), response.headers.get("Content-Type", "application/json")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read(), exc.headers.get("Content-Type", "application/json")
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Failed to reach Ollama at {url}: {exc.reason}") from exc


def sanitize_name(name):
    safe = re.sub(r"[^A-Za-z0-9._:-]+", "-", name.strip())
    if not safe:
        raise ValueError("name must contain at least one valid character")
    return safe


def resolve_under(root_path, requested_path):
    root = Path(root_path).resolve()
    raw = Path(requested_path)
    candidate = raw.resolve() if raw.is_absolute() else (root / raw).resolve()
    if candidate != root and root not in candidate.parents:
        raise ValueError(f"path {requested_path!r} escapes {root}")
    return candidate


def append_jsonl(path, entry):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(entry, ensure_ascii=False) + "\n")


def read_jsonl(path):
    if not path.exists():
        return []
    entries = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line:
            entries.append(json.loads(line))
    return entries


def stringify_tool_result(result):
    if isinstance(result, str):
        return result
    return json.dumps(result, ensure_ascii=False)


def normalize_openai_messages(messages):
    normalized = []
    for message in messages:
        item = dict(message)
        content = item.get("content")
        if isinstance(content, list):
            text_parts = []
            for block in content:
                if isinstance(block, dict) and block.get("type") == "text":
                    text_parts.append(block.get("text", ""))
            item["content"] = "\n".join(part for part in text_parts if part).strip()
        if item.get("role") == "tool" and "name" in item and "tool_name" not in item:
            item["tool_name"] = item["name"]
        tool_calls = item.get("tool_calls")
        if tool_calls and item.get("role") == "assistant":
            normalized_calls = []
            for call in tool_calls:
                function = dict(call.get("function", {}))
                arguments = function.get("arguments", {})
                if isinstance(arguments, str):
                    try:
                        arguments = json.loads(arguments)
                    except json.JSONDecodeError:
                        arguments = {"raw": arguments}
                function["arguments"] = arguments
                normalized_calls.append({"type": call.get("type", "function"), "function": function})
            item["tool_calls"] = normalized_calls
        normalized.append(item)
    return normalized


def latest_user_text(messages):
    for message in reversed(messages):
        if message.get("role") == "user":
            return str(message.get("content", ""))
    return ""


def load_memory_context(runtime, bucket, conversation_id):
    limit = max(0, int(runtime.get("memory_context_limit", 0)))
    sections = []
    if limit <= 0:
        return sections

    notes_path = Path(runtime["memory_dir"]) / "notes" / f"{sanitize_name(bucket)}.jsonl"
    note_entries = read_jsonl(notes_path)[-limit:]
    if note_entries:
        rendered = "\n".join(f"- {entry.get('note', '')}" for entry in note_entries if entry.get("note"))
        if rendered:
            sections.append(f"Persistent notes for bucket '{bucket}':\n{rendered}")

    if conversation_id:
        convo_path = Path(runtime["memory_dir"]) / "conversations" / f"{sanitize_name(conversation_id)}.jsonl"
        convo_entries = read_jsonl(convo_path)[-limit:]
        if convo_entries:
            rendered = []
            for entry in convo_entries:
                user_text = entry.get("user", "").strip()
                assistant_text = entry.get("assistant", "").strip()
                if user_text:
                    rendered.append(f"User: {user_text}")
                if assistant_text:
                    rendered.append(f"Assistant: {assistant_text}")
            if rendered:
                sections.append(
                    "Recent persisted conversation excerpts for this conversation_id:\n"
                    + "\n".join(rendered)
                )
    return sections


def build_runtime_tools(runtime):
    enabled = runtime.get("tools", {})

    def is_on(name):
        return bool(enabled.get(name, {}).get("enabled", False))

    tools = []
    for name, description, properties, required in [
        ("exec", "Run a shell command inside the configured workspace and return stdout, stderr, and the exit code.", {
            "command": {"type": "string", "description": "Shell command to run."},
            "timeout_seconds": {"type": "integer", "description": "Timeout in seconds for the command."},
        }, ["command"]),
        ("read_file", "Read a text file from the configured workspace.", {
            "path": {"type": "string", "description": "Relative or allowed absolute path to read."},
        }, ["path"]),
        ("write_file", "Write a text file inside the configured workspace, creating parent directories when needed.", {
            "path": {"type": "string", "description": "Relative path to write inside the workspace."},
            "content": {"type": "string", "description": "Full file content to write."},
        }, ["path", "content"]),
        ("list_files", "List files and directories under the configured workspace.", {
            "path": {"type": "string", "description": "Relative directory path inside the workspace."},
        }, []),
        ("system_info", "Return basic system details and the configured runtime paths.", {}, []),
        ("remember", "Store a durable note in persistent memory.", {
            "note": {"type": "string", "description": "The note to store."},
            "bucket": {"type": "string", "description": "Memory bucket name.", "default": "default"},
            "tags": {"type": "array", "items": {"type": "string"}, "description": "Optional tags for later lookup."},
        }, ["note"]),
        ("recall", "Look up notes from persistent memory by bucket and optional query text.", {
            "query": {"type": "string", "description": "Filter text to match against stored notes."},
            "bucket": {"type": "string", "description": "Memory bucket name.", "default": "default"},
            "limit": {"type": "integer", "description": "Maximum number of matches to return.", "default": 10},
        }, []),
        ("write_modelfile", "Write a Modelfile under the configured Modelfile directory and optionally build an Ollama model from it.", {
            "name": {"type": "string", "description": "Output model name and Modelfile stem."},
            "from_model": {"type": "string", "description": "Base model or GGUF path for the FROM line."},
            "system_prompt": {"type": "string", "description": "SYSTEM prompt content for the Modelfile."},
            "template": {"type": "string", "description": "Optional TEMPLATE block for the Modelfile."},
            "parameters": {"type": "object", "description": "Optional PARAMETER key/value mapping."},
            "create_model": {"type": "boolean", "description": "Whether to run ollama create after writing the file."},
        }, ["name", "from_model"]),
        ("read_runtime_file", "Read a file from the runtime-owned directory or Modelfile directory.", {
            "path": {"type": "string", "description": "Relative runtime file path."},
            "root": {"type": "string", "description": "Either runtime or modelfiles.", "default": "runtime"},
        }, ["path"]),
        ("write_runtime_file", "Write a file inside the runtime-owned directory or Modelfile directory.", {
            "path": {"type": "string", "description": "Relative runtime file path to write."},
            "content": {"type": "string", "description": "Full file content to write."},
            "root": {"type": "string", "description": "Either runtime or modelfiles.", "default": "runtime"},
        }, ["path", "content"]),
    ]:
        if not is_on(name):
            continue
        tools.append(
            {
                "type": "function",
                "function": {
                    "name": name,
                    "description": description,
                    "parameters": {"type": "object", "properties": properties, **({"required": required} if required else {})},
                },
            }
        )
    return tools


def select_root(runtime, root_name):
    return runtime["modelfile_dir"] if root_name == "modelfiles" else runtime["runtime_dir"]


def execute_tool(name, arguments, runtime, default_bucket):
    tools_cfg = runtime.get("tools", {})
    if not tools_cfg.get(name, {}).get("enabled", False):
        raise ValueError(f"tool {name!r} is disabled")

    workspace = runtime["workspace"]
    memory_dir = Path(runtime["memory_dir"])

    if name == "exec":
        timeout_limit = int(tools_cfg["exec"].get("max_timeout_seconds", 120))
        timeout_seconds = max(1, min(int(arguments.get("timeout_seconds", timeout_limit)), timeout_limit))
        proc = subprocess.run(
            arguments["command"],
            cwd=workspace,
            shell=True,
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
        )
        return {"success": proc.returncode == 0, "command": arguments["command"], "stdout": proc.stdout, "stderr": proc.stderr, "exit_code": proc.returncode}

    if name == "read_file":
        path = resolve_under(workspace, arguments["path"])
        return {"path": str(path), "content": path.read_text(encoding="utf-8")}
    if name == "write_file":
        path = resolve_under(workspace, arguments["path"])
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(arguments["content"], encoding="utf-8")
        return {"written": True, "path": str(path), "bytes": len(arguments["content"].encode("utf-8"))}
    if name == "list_files":
        path = resolve_under(workspace, arguments.get("path", "."))
        return {"path": str(path), "entries": [{"name": entry.name, "type": "dir" if entry.is_dir() else "file"} for entry in sorted(path.iterdir(), key=lambda item: (not item.is_dir(), item.name.lower()))]}
    if name == "system_info":
        disk = os.statvfs("/")
        return {
            "hostname": socket.gethostname(),
            "cwd": os.getcwd(),
            "workspace": workspace,
            "runtime_dir": runtime["runtime_dir"],
            "modelfile_dir": runtime["modelfile_dir"],
            "memory_dir": runtime["memory_dir"],
            "python": os.sys.version,
            "loadavg": list(os.getloadavg()),
            "disk_total_bytes": disk.f_frsize * disk.f_blocks,
            "disk_free_bytes": disk.f_frsize * disk.f_bavail,
        }
    if name == "remember":
        bucket = sanitize_name(arguments.get("bucket", default_bucket or "default"))
        entry = {"timestamp": now_iso(), "note": str(arguments["note"]).strip(), "tags": arguments.get("tags") or []}
        append_jsonl(memory_dir / "notes" / f"{bucket}.jsonl", entry)
        return {"stored": True, "bucket": bucket, "entry": entry}
    if name == "recall":
        bucket = sanitize_name(arguments.get("bucket", default_bucket or "default"))
        query = str(arguments.get("query", "")).strip().lower()
        limit = max(1, min(int(arguments.get("limit", 10)), 50))
        entries = read_jsonl(memory_dir / "notes" / f"{bucket}.jsonl")
        if query:
            entries = [
                entry
                for entry in entries
                if query in " ".join([entry.get("note", ""), " ".join(entry.get("tags", []))]).lower()
            ]
        return {"bucket": bucket, "matches": entries[-limit:]}
    if name == "write_modelfile":
        model_name = sanitize_name(arguments["name"])
        from_model = str(arguments["from_model"]).strip()
        system_prompt = str(arguments.get("system_prompt", "")).strip()
        template = str(arguments.get("template", "")).strip()
        parameters = arguments.get("parameters") or {}
        if not isinstance(parameters, dict):
            raise ValueError("parameters must be an object")
        lines = [f"FROM {from_model}", ""]
        if system_prompt:
            lines.extend(['SYSTEM """', system_prompt, '"""', ""])
        for key, value in parameters.items():
            lines.append(f"PARAMETER {key} {value}")
        if parameters:
            lines.append("")
        if template:
            lines.extend(['TEMPLATE """', template, '"""', ""])
        path = resolve_under(runtime["modelfile_dir"], f"{model_name}.Modelfile")
        path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
        result = {"written": True, "path": str(path), "model_name": model_name}
        if arguments.get("create_model", False):
            proc = subprocess.run(["ollama", "create", model_name, "-f", str(path)], capture_output=True, text=True)
            result["create_model"] = {"success": proc.returncode == 0, "stdout": proc.stdout, "stderr": proc.stderr, "exit_code": proc.returncode}
        return result
    if name == "read_runtime_file":
        root_name = arguments.get("root", "runtime")
        path = resolve_under(select_root(runtime, root_name), arguments["path"])
        return {"path": str(path), "content": path.read_text(encoding="utf-8"), "root": root_name}
    if name == "write_runtime_file":
        root_name = arguments.get("root", "runtime")
        path = resolve_under(select_root(runtime, root_name), arguments["path"])
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(arguments["content"], encoding="utf-8")
        return {"written": True, "path": str(path), "root": root_name}

    raise ValueError(f"unknown tool {name!r}")


def merge_tools(runtime_tools, request_tools):
    by_name = {tool["function"]["name"]: tool for tool in runtime_tools}
    for tool in request_tools or []:
        name = tool.get("function", {}).get("name")
        if name and name not in by_name:
            by_name[name] = tool
    return list(by_name.values())


def format_openai_message(message):
    tool_calls = []
    for index, call in enumerate(message.get("tool_calls") or []):
        function = dict(call.get("function", {}))
        tool_calls.append({"id": f"call_{index}", "type": "function", "function": {"name": function.get("name", ""), "arguments": json.dumps(function.get("arguments", {}), ensure_ascii=False)}})
    return {"role": message.get("role", "assistant"), "content": message.get("content", "") or "", **({"tool_calls": tool_calls} if tool_calls else {})}


def build_model_list(config, runtime):
    model_ids = []
    for url, key in [
        (f"{runtime['ollama_base_url']}/v1/models", "data"),
        (f"{runtime['ollama_base_url']}/api/tags", "models"),
    ]:
        try:
            payload = json_request(url)
            for item in payload.get(key) or []:
                model_id = item.get("id") or item.get("name")
                if model_id:
                    model_ids.append(model_id)
        except RuntimeError:
            pass
    if config.get("last_model"):
        model_ids.append(config["last_model"])
    seen = set()
    return {
        "object": "list",
        "data": [
            {"id": model_id, "object": "model", "owned_by": "ollama-tool-proxy"}
            for model_id in model_ids
            if not (model_id in seen or seen.add(model_id))
        ],
    }


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_args):
        try:
            with ACCESS_LOG_PATH.open("a", encoding="utf-8") as handle:
                handle.write(f"{now_iso()} {self.command} {self.path}\n")
        except OSError:
            pass

    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("Access-Control-Allow-Methods", "GET,POST,OPTIONS")

    def send_json(self, payload, status=200):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_raw(body, status=status, content_type="application/json")

    def send_raw(self, body, status=200, content_type="application/json"):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def send_openai_stream(self, model, message):
        stream_id = f"chatcmpl-{int(time.time() * 1000)}"
        created = int(time.time())
        content = message.get("content", "") or ""
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self._cors()
        self.end_headers()

        def write_event(payload):
            self.wfile.write(f"data: {json.dumps(payload, ensure_ascii=False)}\n\n".encode("utf-8"))
            self.wfile.flush()

        write_event({"id": stream_id, "object": "chat.completion.chunk", "created": created, "model": model, "choices": [{"index": 0, "delta": {"role": "assistant"}, "finish_reason": None}]})
        if content:
            write_event({"id": stream_id, "object": "chat.completion.chunk", "created": created, "model": model, "choices": [{"index": 0, "delta": {"content": content}, "finish_reason": None}]})
        write_event({"id": stream_id, "object": "chat.completion.chunk", "created": created, "model": model, "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]})
        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()
        self.close_connection = True

    def send_ollama_stream(self, payload):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8") + b"\n"
        self.send_response(200)
        self.send_header("Content-Type", "application/x-ndjson")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.send_header("Content-Length", str(len(body)))
        self._cors()
        self.end_headers()
        self.wfile.write(body)
        self.wfile.flush()
        self.close_connection = True

    def read_json(self):
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        return json.loads(raw.decode("utf-8"))

    def do_OPTIONS(self):
        self.send_response(200)
        self._cors()
        self.end_headers()

    def do_HEAD(self):
        config, runtime = load_config()
        ensure_dirs(runtime)
        if self.path == "/":
            self.send_response(200)
            self.send_header("Content-Length", "0")
            self._cors()
            self.end_headers()
            return
        if self.path == "/v1/models":
            body = json.dumps(build_model_list(config, runtime), ensure_ascii=False).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self._cors()
            self.end_headers()
            return
        status, body, content_type = raw_request(f"{runtime['ollama_base_url']}{self.path}", method="HEAD")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self._cors()
        self.end_headers()

    def do_GET(self):
        config, runtime = load_config()
        ensure_dirs(runtime)
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            return self.send_json({"status": "ok", "runtime_enabled": runtime["enabled"], "port": runtime["port"], "ollama_base_url": runtime["ollama_base_url"], "workspace": runtime["workspace"]})
        if parsed.path == "/tools":
            return self.send_json({"tools": build_runtime_tools(runtime)})
        if parsed.path == "/config":
            return self.send_json({"agent_runtime": runtime})
        if parsed.path == "/memory":
            params = parse_qs(parsed.query)
            bucket = sanitize_name(params.get("bucket", ["default"])[0])
            limit = max(1, min(int(params.get("limit", ["20"])[0]), 100))
            entries = read_jsonl(Path(runtime["memory_dir"]) / "notes" / f"{bucket}.jsonl")[-limit:]
            return self.send_json({"bucket": bucket, "entries": entries})
        if parsed.path == "/v1/models":
            return self.send_json(build_model_list(config, runtime))
        status, body, content_type = raw_request(f"{runtime['ollama_base_url']}{self.path}", method="GET")
        return self.send_raw(body, status=status, content_type=content_type)

    def do_POST(self):
        _config, runtime = load_config()
        ensure_dirs(runtime)
        parsed = urlparse(self.path)
        try:
            if parsed.path == "/memory/remember":
                body = self.read_json()
                return self.send_json(execute_tool("remember", body, runtime, body.get("bucket", "default")))
            if parsed.path == "/memory/recall":
                body = self.read_json()
                return self.send_json(execute_tool("recall", body, runtime, body.get("bucket", "default")))
            if parsed.path == "/modelfiles":
                body = self.read_json()
                return self.send_json(execute_tool("write_modelfile", body, runtime, body.get("bucket", "default")))
            if parsed.path in ("/api/chat", "/v1/chat/completions"):
                body = self.read_json()
                model = body.get("model")
                if not model:
                    return self.send_json({"error": "model is required"}, 400)
                request_tools = body.get("tools") or []
                conversation_id = body.get("conversation_id") or self.headers.get("X-Conversation-Id", "")
                memory_bucket = body.get("memory_bucket", "default")
                messages = normalize_openai_messages(body.get("messages") or [])
                prelude = []
                if runtime.get("system_prompt"):
                    prelude.append({"role": "system", "content": runtime["system_prompt"]})
                for section in load_memory_context(runtime, memory_bucket, conversation_id):
                    prelude.append({"role": "system", "content": section})
                chat_messages = prelude + messages
                merged_tools = merge_tools(build_runtime_tools(runtime), request_tools)
                passthrough = {key: body[key] for key in ("format", "keep_alive", "options", "think") if key in body}
                final_response = None
                for _ in range(max(1, int(runtime.get("max_tool_iterations", 8)))):
                    response = json_request(
                        f"{runtime['ollama_base_url']}/api/chat",
                        payload={"model": model, "messages": chat_messages, "tools": merged_tools, "stream": False, **passthrough},
                        method="POST",
                    )
                    final_response = response
                    message = response.get("message", {})
                    assistant_message = {"role": "assistant"}
                    if message.get("content"):
                        assistant_message["content"] = message["content"]
                    if message.get("tool_calls"):
                        assistant_message["tool_calls"] = message["tool_calls"]
                    if message.get("thinking"):
                        assistant_message["thinking"] = message["thinking"]
                    chat_messages.append(assistant_message)
                    tool_calls = message.get("tool_calls") or []
                    if not tool_calls:
                        break
                    for call in tool_calls:
                        function = call.get("function", {})
                        tool_name = function.get("name")
                        arguments = function.get("arguments") or {}
                        tool_result = execute_tool(tool_name, arguments, runtime, memory_bucket)
                        chat_messages.append({"role": "tool", "tool_name": tool_name, "content": stringify_tool_result(tool_result)})
                else:
                    raise RuntimeError("max_tool_iterations reached before assistant produced a final response")

                if conversation_id and final_response:
                    append_jsonl(
                        Path(runtime["memory_dir"]) / "conversations" / f"{sanitize_name(conversation_id)}.jsonl",
                        {"timestamp": now_iso(), "model": model, "user": latest_user_text(messages), "assistant": final_response.get("message", {}).get("content", "")},
                    )

                if parsed.path == "/v1/chat/completions":
                    if body.get("stream"):
                        return self.send_openai_stream(model, final_response.get("message", {}))
                    usage = {"prompt_tokens": final_response.get("prompt_eval_count", 0), "completion_tokens": final_response.get("eval_count", 0)}
                    usage["total_tokens"] = usage["prompt_tokens"] + usage["completion_tokens"]
                    return self.send_json({
                        "id": f"chatcmpl-{int(time.time() * 1000)}",
                        "object": "chat.completion",
                        "created": int(time.time()),
                        "model": model,
                        "choices": [{"index": 0, "message": format_openai_message(final_response.get("message", {})), "finish_reason": "stop"}],
                        "usage": usage,
                    })
                if body.get("stream"):
                    return self.send_ollama_stream(final_response)
                return self.send_json(final_response)
        except Exception as exc:
            return self.send_json({"error": str(exc)}, 500)

        content_type = self.headers.get("Content-Type", "application/json")
        length = int(self.headers.get("Content-Length", "0"))
        raw_body = self.rfile.read(length) if length else None
        status, body, response_type = raw_request(f"{runtime['ollama_base_url']}{self.path}", payload=raw_body, method="POST", content_type=content_type)
        return self.send_raw(body, status=status, content_type=response_type)


def main():
    _config, runtime = load_config()
    ensure_dirs(runtime)
    port = int(runtime["port"])
    print(f"Ollama tool proxy listening on http://0.0.0.0:{port}")
    HTTPServer(("0.0.0.0", port), Handler).serve_forever()


if __name__ == "__main__":
    main()

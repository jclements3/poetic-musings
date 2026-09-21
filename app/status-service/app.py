"""Tiny read-only status service.

Serves the repo's STATUS.md as rendered HTML at `/`, as JSON at `/status.json`,
plus `/healthz` (liveness) and `/readyz` (readiness) probes for Kubernetes.

No write endpoints, no external calls, no secrets. STATUS_MD_PATH is the only
configurable input, and it is only ever read from disk.
"""
import html
import os
import re
import time
from pathlib import Path

from flask import Flask, Response, jsonify

app = Flask(__name__)

STATUS_MD_PATH = Path(os.environ.get("STATUS_MD_PATH", "/data/STATUS.md"))
START_TIME = time.time()


def _read_status_md() -> str:
    return STATUS_MD_PATH.read_text(encoding="utf-8")


def _markdown_to_html(md_text: str) -> str:
    """Minimal, dependency-free Markdown -> HTML for headings/tables/lists/paragraphs.

    This is intentionally small: it covers what STATUS.md actually uses
    (#/##, pipe tables, '-' bullet lists, bold, plain paragraphs) rather than
    pulling in a full Markdown dependency for a demo service.
    """
    lines = md_text.splitlines()
    out = []
    in_table = False
    in_list = False

    def close_list():
        nonlocal in_list
        if in_list:
            out.append("</ul>")
            in_list = False

    def close_table():
        nonlocal in_table
        if in_table:
            out.append("</table>")
            in_table = False

    def inline(text: str) -> str:
        text = html.escape(text)
        text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
        text = re.sub(r"`(.+?)`", r"<code>\1</code>", text)
        return text

    for raw in lines:
        line = raw.rstrip("\n")
        stripped = line.strip()

        if not stripped:
            close_list()
            close_table()
            continue

        heading = re.match(r"^(#{1,6})\s+(.*)$", stripped)
        if heading:
            close_list()
            close_table()
            level = len(heading.group(1))
            out.append(f"<h{level}>{inline(heading.group(2))}</h{level}>")
            continue

        if stripped.startswith("|"):
            close_list()
            cells = [c.strip() for c in stripped.strip("|").split("|")]
            if all(re.match(r"^:?-+:?$", c) for c in cells):
                continue  # header separator row
            if not in_table:
                out.append('<table border="1" cellpadding="4" cellspacing="0">')
                in_table = True
                tag = "th"
            else:
                tag = "td"
            row = "".join(f"<{tag}>{inline(c)}</{tag}>" for c in cells)
            out.append(f"<tr>{row}</tr>")
            continue

        if stripped.startswith("- "):
            close_table()
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append(f"<li>{inline(stripped[2:])}</li>")
            continue

        close_list()
        close_table()
        out.append(f"<p>{inline(stripped)}</p>")

    close_list()
    close_table()
    return "\n".join(out)


@app.get("/")
def index() -> Response:
    try:
        md_text = _read_status_md()
    except OSError as exc:
        return Response(f"<h1>status unavailable</h1><p>{html.escape(str(exc))}</p>",
                         status=503, mimetype="text/html")
    body = _markdown_to_html(md_text)
    page = (
        "<!doctype html><html><head><meta charset='utf-8'>"
        "<title>poetic-musings status</title></head><body>"
        f"{body}</body></html>"
    )
    return Response(page, mimetype="text/html")


@app.get("/status.json")
def status_json():
    try:
        md_text = _read_status_md()
    except OSError as exc:
        return jsonify(error=str(exc)), 503
    return jsonify(
        source=str(STATUS_MD_PATH),
        length_bytes=len(md_text.encode("utf-8")),
        content=md_text,
    )


@app.get("/healthz")
def healthz():
    # Liveness: process is up and serving. No I/O, so a stuck filesystem
    # doesn't get confused with a dead process.
    return jsonify(status="alive", uptime_s=round(time.time() - START_TIME, 1))


@app.get("/readyz")
def readyz():
    # Readiness: can we actually read the data we're meant to serve.
    if STATUS_MD_PATH.exists():
        return jsonify(status="ready")
    return jsonify(status="not-ready", reason="STATUS.md not found"), 503


if __name__ == "__main__":
    # Binding all interfaces is correct, not a vulnerability, in a
    # containerized deployment: the container's network namespace is the
    # real boundary, restricted further by the k8s NetworkPolicy in
    # k8s/base/networkpolicy.yaml. Production runs under gunicorn (see
    # Dockerfile CMD), not this block -- it's local-dev-only convenience.
    app.run(host="0.0.0.0", port=8080)  # nosec B104

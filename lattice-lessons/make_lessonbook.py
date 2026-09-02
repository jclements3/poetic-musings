"""Compile the two tracks into one readable study book: LESSONBOOK.html.
Re-run after editing any lesson; the book is generated, never hand-edited."""
import datetime
import html
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))

CHAPTERS = [
    ("Part I — Lattice SDK track", "README.md", [
        "harness.py",
        "lesson01_client_and_config.py",
        "lesson02_models.py",
        "lesson03_publishing.py",
        "lesson04_worldmodel.py",
        "lesson05_python_drills.py",
        "lesson06_tasks_agent.py",
        "lesson07_robustness.py",
        "test_lesson08.py",
    ]),
    ("Part II — HackerRank on Zoom", "hackerrank/README.md", [
        "hackerrank/drill01_stdlib_weapons.py",
        "hackerrank/drill02_io_formats.py",
        "hackerrank/problems.py",
        "hackerrank/mock_test.py",
    ]),
]

def md_to_html(md):
    out, in_table, in_code = [], False, False
    for line in md.splitlines():
        if line.startswith("```"):
            in_code = not in_code
            out.append("<pre><code>" if in_code else "</code></pre>")
            continue
        if in_code:
            out.append(html.escape(line))
            continue
        if line.startswith("|"):
            cells = [c.strip() for c in line.strip("|").split("|")]
            if set("".join(cells)) <= {"-", " ", ":"}:
                continue
            tag = "th" if not in_table else "td"
            if not in_table:
                out.append("<table>")
                in_table = True
            out.append("<tr>" + "".join(f"<{tag}>{html.escape(c)}</{tag}>"
                                        for c in cells) + "</tr>")
            continue
        if in_table:
            out.append("</table>")
            in_table = False
        h = re.match(r"(#{1,3}) (.*)", line)
        esc = html.escape(line)
        esc = re.sub(r"`([^`]+)`", r"<code>\1</code>", esc)
        esc = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", esc)
        if h:
            lvl = len(h.group(1)) + 1
            out.append(f"<h{lvl}>{esc.lstrip('# ')}</h{lvl}>")
        elif line.startswith("    "):
            out.append(f"<pre><code>{html.escape(line[4:])}</code></pre>")
        elif line.strip().startswith("- "):
            out.append(f"<li>{esc.strip()[2:]}</li>")
        elif line.strip():
            out.append(f"<p>{esc}</p>")
    if in_table:
        out.append("</table>")
    return "\n".join(out)

def lesson_to_html(path):
    src = open(os.path.join(HERE, path)).read()
    m = re.match(r'"""(.*?)"""\n?', src, re.S)
    doc = m.group(1) if m else ""
    code = src[m.end():] if m else src
    title = doc.splitlines()[0] if doc else path
    body = html.escape("\n".join(doc.splitlines()[1:]).strip())
    return (f'<h3 id="{path}">{html.escape(title)}</h3>'
            f'<p class="file">{path}</p>'
            f'<div class="doc"><pre>{body}</pre></div>'
            f'<details open><summary>code</summary>'
            f'<pre><code>{html.escape(code.strip())}</code></pre></details>')

toc, parts = [], []
for part_title, readme, files in CHAPTERS:
    toc.append(f'<li><b>{html.escape(part_title)}</b><ul>')
    parts.append(f'<h1>{html.escape(part_title)}</h1>')
    parts.append(md_to_html(open(os.path.join(HERE, readme)).read()))
    for f in files:
        src_line = open(os.path.join(HERE, f)).readline()
        label = f.split("/")[-1]
        toc.append(f'<li><a href="#{f}">{html.escape(label)}</a></li>')
        parts.append(lesson_to_html(f))
    toc.append("</ul></li>")

stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
html_doc = f"""<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<title>Lattice + HackerRank Lesson Book</title>
<style>
body{{font-family:Georgia,serif;max-width:900px;margin:24px auto;padding:0 16px;
     color:#222;line-height:1.45}}
h1{{border-bottom:3px solid #3b5a7a;color:#3b5a7a;padding-bottom:4px}}
h2{{color:#3b5a7a}} h3{{margin-top:36px;border-top:1px solid #ddd;padding-top:18px}}
pre{{background:#f6f4ee;border:1px solid #ddd;padding:10px;overflow-x:auto;
    font-size:13px;line-height:1.35}}
code{{font-family:ui-monospace,Menlo,Consolas,monospace}}
table{{border-collapse:collapse;margin:10px 0}} td,th{{border:1px solid #ccc;
    padding:5px 10px;font-size:14px}} th{{background:#eef1f5}}
.file{{color:#888;font-family:ui-monospace,monospace;font-size:12px;margin:2px 0}}
.doc pre{{background:#fffbe8;border-color:#e6d9a8}}
details summary{{cursor:pointer;color:#3b5a7a;font-family:ui-monospace,monospace}}
.stamp{{color:#999;font-size:12px}}
nav ul{{line-height:1.7}}
@media print{{details{{display:block}} details>summary{{display:none}}}}
</style></head><body>
<h1>Lattice SDK + HackerRank — the Lesson Book</h1>
<p class="stamp">compiled {stamp} from lattice-lessons/ — regenerate with
make_lessonbook.py; the .py files stay the runnable source of truth</p>
<p>How to study: read a chapter here, then RUN its file and do the exercises
in the file before opening the solutions. Yellow blocks are the teaching
notes; collapsible blocks are the full code, solutions included — so do the
exercises at the keyboard first, and treat this book as the review pass.</p>
<nav><h2>Contents</h2><ul>{''.join(toc)}</ul></nav>
{''.join(parts)}
</body></html>"""
open(os.path.join(HERE, "LESSONBOOK.html"), "w").write(html_doc)
print(f"wrote LESSONBOOK.html ({len(html_doc)//1024} KB)")

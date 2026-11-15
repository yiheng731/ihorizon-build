"""Strip comments from the files that ship in the public repository.

Run with --check to report what would change, or --write to apply.  After a
change the patch chain is verified with git apply --check, Python files with
py_compile, YAML with yaml.safe_load and the shader pack with horizon-shader.
"""

from __future__ import annotations

import argparse
import io
import re
import subprocess
import sys
import tokenize
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

RS = {".rs"}
PY = {".py"}
HASH = {".sh", ".yml", ".yaml", ".toml", ".ps1", ".gitignore", ".gitattributes"}
C_LIKE = {".h", ".swift"}
MAKE = {"Makefile"}
PATCH = {".patch"}


def strip_rust(text: str) -> str:
    out: list[str] = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == '"':
            j = i + 1
            while j < n:
                if text[j] == "\\":
                    j += 2
                    continue
                if text[j] == '"':
                    j += 1
                    break
                j += 1
            out.append(text[i:j])
            i = j
            continue
        if c == "r" and i + 1 < n and text[i + 1] in '#"':
            m = re.match(r'r(#*)"', text[i:])
            if m:
                hashes = m.group(1)
                end = text.find('"' + hashes, i + m.end())
                if end != -1:
                    j = end + 1 + len(hashes)
                    out.append(text[i:j])
                    i = j
                    continue
        if text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j == -1 else j
            continue
        if text.startswith("/*", i):
            j = text.find("*/", i + 2)
            i = n if j == -1 else j + 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def strip_python(text: str) -> str:
    try:
        tokens = list(tokenize.generate_tokens(io.StringIO(text).readline))
    except (tokenize.TokenError, IndentationError):
        return text
    comments = [t for t in tokens if t.type == tokenize.COMMENT]
    lines = text.splitlines(keepends=True)
    for t in reversed(comments):
        row, col = t.start
        line = lines[row - 1]
        if line.lstrip().startswith("#"):
            lines[row - 1] = ""
        else:
            lines[row - 1] = line[:col].rstrip() + ("\n" if line.endswith("\n") else "")
    return "".join(lines)


def strip_hash(text: str) -> str:
    out = []
    for line in text.splitlines(keepends=True):
        stripped = line.lstrip()
        if stripped.startswith("#") and not stripped.startswith("#!"):
            out.append("")
        else:
            out.append(line)
    return "".join(out)


def strip_c_like(text: str) -> str:
    return strip_rust(text)


def strip_make(text: str) -> str:
    out = []
    for line in text.splitlines(keepends=True):
        if line.lstrip().startswith("#"):
            out.append("")
        else:
            out.append(line)
    return "".join(out)


def strip_patch(text: str) -> str:
    """Drop comment-only lines that a hunk adds, renumbering its line counts."""
    lines = text.splitlines(keepends=True)
    out: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        m = re.match(r"^@@ -(\d+),(\d+) \+(\d+),(\d+) @@", line)
        if not m:
            out.append(line)
            i += 1
            continue
        head = line
        i += 1
        body: list[str] = []
        while i < len(lines) and not lines[i].startswith(("@@", "diff --git")):
            body.append(lines[i])
            i += 1

        def comment_only(entry: str) -> bool:
            if not entry.startswith("+"):
                return False
            content = entry[1:].strip()
            return content.startswith("//") or content.startswith("/*") or content.startswith("*")

        kept = [b for b in body if not comment_only(b)]
        old_len = sum(1 for b in kept if b.startswith(("-", " ")))
        new_len = sum(1 for b in kept if b.startswith(("+", " ")))
        head = re.sub(
            r"^@@ -\d+,\d+ \+\d+,\d+ @@",
            f"@@ -{m.group(1)},{old_len} +{m.group(3)},{new_len} @@",
            head,
        )
        out.append(head)
        out.extend(kept)
    return "".join(out)


HANDLERS = {
    **{e: strip_rust for e in RS},
    **{e: strip_python for e in PY},
    **{e: strip_hash for e in HASH},
    **{e: strip_c_like for e in C_LIKE},
    **{e: strip_make for e in MAKE},
    **{e: strip_patch for e in PATCH},
}


def targets() -> list[Path]:
    files = subprocess.run(
        ["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True
    ).stdout.split()
    picked = []
    for name in files:
        path = ROOT / name
        if path.suffix in HANDLERS or path.name in HANDLERS:
            picked.append(path)
    return picked


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    if not (args.write or args.check):
        print("pass --write or --check")
        return 2

    changed = 0
    for path in targets():
        handler = HANDLERS.get(path.suffix) or HANDLERS.get(path.name)
        if handler is None:
            continue
        before = path.read_text(encoding="utf-8")
        after = handler(before)
        after = re.sub(r"\n{3,}", "\n\n", after)
        if before.strip() == after.strip():
            continue
        changed += 1
        print(("would strip " if args.check else "stripped ") + str(path.relative_to(ROOT)))
        if args.write:
            path.write_text(after, encoding="utf-8", newline="\n")
    print(f"{changed} file(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

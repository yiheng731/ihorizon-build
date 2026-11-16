import pathlib
import re
import sys

BACKSLASH = "\\"


def strip_rs(text):
    out = []
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c == '"':
            j = i + 1
            while j < n:
                if text[j] == BACKSLASH:
                    j += 2
                    continue
                if text[j] == '"':
                    j += 1
                    break
                j += 1
            out.append(text[i:j])
            i = j
            continue
        if c == "'":
            m = re.match(r"'(?:\\.[^']*|[^'\\])'", text[i:])
            if m:
                out.append(m.group(0))
                i += len(m.group(0))
                continue
        if text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        if text.startswith("/*", i):
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def strip_wgsl(text):
    out = []
    for line in text.splitlines():
        cut = line.find("//")
        out.append(line if cut < 0 else line[:cut].rstrip())
    return "\n".join(out) + "\n"


def main(targets):
    paths = []
    for target in targets:
        target = pathlib.Path(target)
        if target.is_dir():
            paths.extend(sorted(target.rglob("*")))
        else:
            paths.append(target)
    for path in paths:
        if path.suffix not in (".rs", ".wgsl", ".toml"):
            continue
        text = path.read_text(encoding="utf-8")
        if path.suffix == ".rs":
            new = strip_rs(text)
        elif path.suffix == ".wgsl":
            new = strip_wgsl(text)
        else:
            kept = [l for l in text.splitlines() if not l.lstrip().startswith("#")]
            new = "\n".join(kept) + "\n"
        new = re.sub(r"\n{3,}", "\n\n", new).lstrip("\n")
        if new != text:
            path.write_text(new, encoding="utf-8", newline="\n")
            print("stripped", path.as_posix())


if __name__ == "__main__":
    main(sys.argv[1:] or ["ios/crates/horizon-client-ios"])

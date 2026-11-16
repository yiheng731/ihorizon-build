import pathlib
import re
import subprocess
import sys

BASE = "0de8932"
TREE = pathlib.Path(r"C:\Users\hh201\AppData\Local\Temp\hz-14")
PATCH = pathlib.Path(__file__).resolve().parent.parent / "patches" / "ios.patch"
SKIP = re.compile(r"^(crates/horizon-client-ios/|Cargo\.toml$|Cargo\.lock$)")


def changed_files():
    out = subprocess.run(
        ["git", "-C", str(TREE), "status", "--porcelain"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    names = []
    for line in out.splitlines():
        path = line[3:].strip().strip('"')
        if " -> " in path:
            path = path.split(" -> ", 1)[1]
        if SKIP.match(path):
            continue
        names.append(path)
    return sorted(set(names))


def patched_files():
    text = PATCH.read_text(encoding="utf-8")
    return set(re.findall(r"^\+\+\+ b/(.+)$", text, re.M))


def main():
    changed = changed_files()
    patched = patched_files()
    missing = [path for path in changed if path not in patched]
    extra = sorted(patched - set(changed))
    print(f"changed {len(changed)}, in patch {len(patched)}")
    for path in missing:
        print("MISSING from ios.patch:", path)
    for path in extra:
        print("in patch but not in the tree:", path)
    added_comments = re.findall(r"^\+[ \t]*(?://|/\*)", PATCH.read_text(encoding="utf-8"), re.M)
    print("added comment lines:", len(added_comments))
    if missing or added_comments:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

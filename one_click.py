#!/usr/bin/env python3
"""一键：建仓库 → 推代码 → 触发 GitHub Actions → 等 macOS 构建 → 下载 ipa。

只用标准库，Windows / macOS / Linux 都能跑。

    python one_click.py                      # 公开仓库，等构建，自动下载 ipa
    python one_click.py --private            # 私有仓库（macOS 分钟按 10 倍计费）
    python one_click.py --name hz-ios --no-wait    # 只推，不等
    python one_click.py --build-only         # 仓库已推过，只重新跑一次构建
    python one_click.py --dry-run            # 只做本地检查，不联网

令牌顺序：$GITHUB_TOKEN → $GH_TOKEN → `gh auth token` → 交互输入（不会回显、不会落盘）。
"""

from __future__ import annotations

import argparse
import getpass
import http.client
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
API = "https://api.github.com"
API_VERSION = "2022-11-28"
ARTIFACT = "ihorizon-ipa"
# 同一个 workflow 的第二个 job：把 Horizon 自己的客户端（不是绿色三角壳）打成 ipa
CLIENT_ARTIFACT = "ihorizon-client-ipa"
WORKFLOW = "ios-ipa.yml"
# 探针 workflow：只有 macOS 能回答「上游哪些 crate 在 iOS 上编不过」
PROBE_WORKFLOW = "ios-probe.yml"
PROBE_ARTIFACT = "ios-probe-log"
POLL_SECONDS = 15


# ─────────────────────────── 输出 ───────────────────────────

def log(message: str) -> None:
    print(message, flush=True)


def step(message: str) -> None:
    print(f"\n\033[1;32m==> {message}\033[0m", flush=True)


def warn(message: str) -> None:
    print(f"\033[1;33m  ! {message}\033[0m", flush=True)


def die(message: str, hint: str = "") -> "None":
    print(f"\n\033[1;31m✗ {message}\033[0m", flush=True)
    if hint:
        print(f"  {hint}", flush=True)
    sys.exit(1)


# ─────────────────────────── 进程 ───────────────────────────

GIT = "git"  # find_git() 会把它换成绝对路径


def find_git(interactive: bool = True) -> str:
    """git 不一定在 PATH 里：Windows 上常见于 Program Files、scoop、choco，
    甚至只存在于某些工具链自带的 ucrt64/bin。都找不到就当场装一个。"""
    global GIT

    found = shutil.which("git")
    if found:
        GIT = found
        return found

    candidates = [
        Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "Git/cmd/git.exe",
        Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / "Git/cmd/git.exe",
        Path(os.environ.get("LOCALAPPDATA", "")) / "Programs/Git/cmd/git.exe",
        Path(os.environ.get("USERPROFILE", "")) / "scoop/shims/git.exe",
        Path(os.environ.get("ProgramData", r"C:\ProgramData")) / "chocolatey/bin/git.exe",
        Path(os.environ.get("USERPROFILE", ""))
        / ".dsh/profiles/desktop/node_modules/@dsh-ops/bash-win32-x64/ucrt64/bin/git.exe",
    ]
    for candidate in candidates:
        if candidate.is_file():
            GIT = str(candidate)
            break

    if GIT == "git":
        # 最后一搏：在常见安装根目录里浅扫一层
        for root in (Path(os.environ.get("LOCALAPPDATA", "")) / "Programs",
                     Path(os.environ.get("ProgramFiles", r"C:\Program Files"))):
            if root.is_dir():
                hits = list(root.glob("*/cmd/git.exe")) + list(root.glob("*/bin/git.exe"))
                if hits:
                    GIT = str(hits[0])
                    break

    if GIT == "git":
        if not interactive:
            die("找不到 git", "winget install --id Git.Git -e")
        if not shutil.which("winget"):
            die("找不到 git，也没有 winget",
                "手动装 Git for Windows: https://git-scm.com/download/win")
        log("这台机器上没有 git。")
        answer = input("    现在用 winget 装一个？[Y/n] ").strip().lower()
        if answer not in ("", "y", "yes"):
            die("已取消", "装好 git 后重跑本脚本")
        step("安装 Git for Windows")
        run(["winget", "install", "--id", "Git.Git", "-e", "--silent",
             "--accept-package-agreements", "--accept-source-agreements"], check=False)
        for probe in (Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "Git/cmd/git.exe",
                      Path(os.environ.get("LOCALAPPDATA", "")) / "Programs/Git/cmd/git.exe"):
            if probe.is_file():
                GIT = str(probe)
                break
        if GIT == "git":
            die("装完了但没找到 git.exe", "重开一个终端再跑一次")

    # git 会自己去调 git-remote-https 等子程序，所在目录必须在 PATH 上。
    git_dir = str(Path(GIT).parent)
    if git_dir not in os.environ.get("PATH", ""):
        os.environ["PATH"] = git_dir + os.pathsep + os.environ.get("PATH", "")
    return GIT


def run(cmd: list[str], check: bool = True, quiet: bool = False, env: dict | None = None) -> str:
    merged = {
        **os.environ,
        "GIT_TERMINAL_PROMPT": "0",
        "GCM_INTERACTIVE": "never",
        "GCM_GUI_PROMPT": "false",
        "GIT_ASKPASS": "",
        "SSH_ASKPASS": "",
    }
    if env:
        merged.update(env)
    result = subprocess.run(
        cmd, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace", env=merged
    )
    if not quiet and result.stdout.strip():
        print("\n".join("    " + line for line in result.stdout.strip().splitlines()), flush=True)
    if check and result.returncode != 0:
        die(
            f"命令失败（exit {result.returncode}）：{' '.join(cmd[:3])}",
            (result.stderr or result.stdout).strip()[:600],
        )
    return result.stdout


def git(*args: str, check: bool = True, quiet: bool = False) -> str:
    return run([GIT, "-c", "credential.helper=", *args], check=check, quiet=quiet)


def git_value(key: str) -> str:
    out = git("config", "--get", key, check=False, quiet=True)
    return out.strip()


# ─────────────────────────── GitHub API ───────────────────────────

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: D102
        return None


def api(method: str, path: str, token: str, payload: dict | None = None) -> dict:
    body = json.dumps(payload).encode() if payload is not None else None
    request = urllib.request.Request(f"{API}{path}", data=body, method=method)
    request.add_header("Accept", "application/vnd.github+json")
    request.add_header("X-GitHub-Api-Version", API_VERSION)
    request.add_header("User-Agent", "ihorizon-onclick")
    request.add_header("Authorization", f"Bearer {token}")
    if body:
        request.add_header("Content-Type", "application/json")
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=45) as response:
                raw = response.read()
                return json.loads(raw) if raw else {}
        except (http.client.IncompleteRead, TimeoutError, ConnectionError) as error:
            # A long poll can outlive the connection: ask again, the answer is idempotent.
            if attempt == 3:
                die("和 GitHub 的连接反复中断", repr(error))
            time.sleep(2 + attempt * 3)
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", "replace")[:400]
            if error.code == 401:
                die("GitHub 令牌无效或已过期", detail)
            if error.code == 403:
                die("令牌权限不足（需要 Contents + Actions 的读写）", detail)
            raise GitHubError(error.code, detail) from None
        except urllib.error.URLError as error:
            if attempt == 3:
                die("连不上 api.github.com", str(error.reason))
            time.sleep(2 + attempt * 3)
    raise AssertionError("unreachable")


class GitHubError(Exception):
    def __init__(self, code: int, detail: str) -> None:
        super().__init__(f"HTTP {code}")
        self.code = code
        self.detail = detail


# ─────────────────────────── 令牌 ───────────────────────────

INVISIBLE = dict.fromkeys(map(ord, "\u200b\u200c\u200d\ufeff\u00a0\r\n\t "), None)


def scrub(token: str) -> str:
    """粘进来的令牌常带零宽字符、换行或被包在引号里，全清掉。"""
    return token.translate(INVISIBLE).strip().strip("'\"")


def fingerprint(token: str) -> str:
    head = token[:11] if token.startswith("github_pat_") else token[:4]
    return f"长度 {len(token)}，{head}…{token[-4:]}"


def check_token(token: str) -> tuple[bool, str]:
    """直接问 /user，不经过 api()：401 不该杀掉重试循环。"""
    request = urllib.request.Request(f"{API}/user")
    request.add_header("Accept", "application/vnd.github+json")
    request.add_header("X-GitHub-Api-Version", API_VERSION)
    request.add_header("User-Agent", "ihorizon-onclick")
    request.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return True, json.loads(response.read() or b"{}").get("login", "?")
    except urllib.error.HTTPError as error:
        return False, error.read().decode("utf-8", "replace")[:160]
    except urllib.error.URLError as error:
        die("连不上 api.github.com", str(error.reason))


def resolve_token(interactive: bool, explicit: str | None = None) -> str:
    sources: list[tuple[str, str]] = []
    if explicit:
        sources.append(("--token", explicit))
    for name in ("GITHUB_TOKEN", "GH_TOKEN"):
        value = os.environ.get(name, "").strip()
        if value:
            sources.append((f"${name}", value))
    token_file = ROOT / "token.txt"
    if token_file.is_file():
        sources.append(("token.txt", token_file.read_text(encoding="utf-8")))
    if shutil.which("gh"):
        out = run(["gh", "auth", "token"], check=False, quiet=True).strip()
        if out:
            sources.append(("gh CLI", out))

    if not interactive and not sources:
        die("没有令牌", "设 GITHUB_TOKEN，或先跑 gh auth login")

    log("需要 GitHub 令牌（Settings → Developer settings → Personal access tokens →")
    log("            经典令牌勾 repo + workflow；fine-grained 勾 Contents/Actions 读写）")

    if not sources:
        log("            更稳的做法：set GITHUB_TOKEN=xxx 再跑，绕开不回显的粘贴")

    while True:
        if sources:
            source, raw = sources.pop(0)
        else:
            if not interactive:
                die("没有可用令牌")
            raw = getpass.getpass("    粘贴令牌（不回显）: ")
            source = "手动输入"
        token = scrub(raw)
        if not token:
            warn(f"{source} 里是空的，跳过")
            continue
        ok, detail = check_token(token)
        if ok:
            log(f"    {source}：{fingerprint(token)}，登录为 {detail}")
            return token
        warn(f"{source} 的令牌无效：{fingerprint(token)}")
        log(f"    GitHub 说：{detail.strip()[:120]}")
        if not interactive and not sources:
            die("令牌无效", "去 https://github.com/settings/tokens 重新生成")
        if not sources:
            log("    常见原因：复制漏字符 / 已过期 / 已被撤销 / 复制成了别的文字")
            log("    建议：set GITHUB_TOKEN=xxx  再跑一次")


# ─────────────────────────── 本地仓库 ───────────────────────────

def ensure_git() -> None:
    find_git(interactive=True)


def ensure_repo() -> None:
    inside = run(["git", "rev-parse", "--is-inside-work-tree"], check=False, quiet=True).strip()
    if inside != "true":
        step("初始化仓库")
        git("init", "-b", "main")
    branch = git("rev-parse", "--abbrev-ref", "HEAD", check=False, quiet=True).strip()
    if branch not in ("main", ""):
        git("branch", "-M", "main")


def ensure_identity(token: str | None) -> None:
    name, email = git_value("user.name"), git_value("user.email")
    if name and email:
        log(f"    身份：{name} <{email}>")
        return

    if token:
        me = api("GET", "/user", token)
        login, uid = me["login"], me["id"]
        name = name or me.get("name") or login
        email = email or f"{uid}+{login}@users.noreply.github.com"
    else:
        name = name or "ihorizon"
        email = email or "ihorizon@users.noreply.github.com"
        warn("没有令牌，提交身份用占位值")

    git("config", "user.name", name)
    git("config", "user.email", email)
    log(f"    身份：{name} <{email}>（本仓库局部配置）")


def ensure_staged() -> bool:
    git("add", "-A")
    git("add", "--renormalize", ".", check=False)
    staged = git("diff", "--cached", "--name-only", quiet=True).strip()
    if not staged:
        return False
    count = len(staged.splitlines())
    log(f"    暂存 {count} 个文件")
    return True


def commit(staged: bool) -> None:
    head = git("rev-parse", "--verify", "HEAD", check=False, quiet=True).strip()
    if not staged and head:
        log("    没有改动，跳过提交")
        return
    message = "horizon ios shell: wgpu Metal surface + ipa toolchain"
    if staged:
        git("commit", "-q", "-m", message)
    else:
        git("commit", "-q", "--allow-empty", "-m", message)
    short = git("rev-parse", "--short", "HEAD", quiet=True).strip()
    log(f"    已提交 {short}")


# ─────────────────────────── 远端 ───────────────────────────

def whoami(token: str) -> str:
    return api("GET", "/user", token)["login"]


def ensure_remote_repo(token: str, owner: str, name: str, private: bool, create: bool) -> tuple[str, str]:
    try:
        repo = api("GET", f"/repos/{owner}/{name}", token)
        log(f"    仓库已存在：{repo['full_name']}")
        return repo["owner"]["login"], repo["name"]
    except GitHubError as error:
        if error.code != 404:
            die(f"查仓库失败（HTTP {error.code}）", error.detail)

    if not create:
        die(f"仓库 {owner}/{name} 不存在", "去掉 --no-create 让脚本自动建")

    step("创建仓库")
    payload = {
        "name": name,
        "private": private,
        "description": "Horizon (Rust Minecraft) on iOS: CAMetalLayer + wgpu shell, thin ipa with asset import",
        "has_issues": True,
        "auto_init": False,
    }
    try:
        repo = api("POST", "/user/repos", token, payload)
    except GitHubError as error:
        die(f"建仓库失败（HTTP {error.code}）", error.detail)
    log(f"    {repo['full_name']}（{'私有' if private else '公开'}）")
    return repo["owner"]["login"], repo["name"]


def ensure_remote(owner: str, name: str) -> None:
    url = f"https://github.com/{owner}/{name}.git"
    current = git("remote", "get-url", "origin", check=False, quiet=True).strip()
    if current:
        if current != url:
            git("remote", "set-url", "origin", url)
            log(f"    origin → {url}")
    else:
        git("remote", "add", "origin", url)
        log(f"    origin → {url}")


def push(token: str, owner: str, name: str) -> None:
    step("推送 main")
    # 令牌只出现在这一次命令行里，不写进 .git/config。
    url = f"https://x-access-token:{token}@github.com/{owner}/{name}.git"
    result = subprocess.run(
        [GIT, "-c", "credential.helper=", "push", "-u", url, "HEAD:main"],
        cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace",
        env={**os.environ, "GIT_TERMINAL_PROMPT": "0", "GCM_INTERACTIVE": "never",
             "GCM_GUI_PROMPT": "false", "GIT_ASKPASS": "", "SSH_ASKPASS": ""},
    )
    output = (result.stdout + result.stderr).replace(token, "***")
    if result.returncode != 0:
        if "workflow" in output and "refusing" in output:
            die(
                "推送被拒：令牌缺 workflow 权限",
                "经典令牌要同时勾 repo + workflow；"
                "直达链接：https://github.com/settings/tokens/new?scopes=repo,workflow",
            )
        if "403" in output or "Permission" in output:
            die("推送被拒：令牌没有这个仓库的写权限", output.strip()[:400])
        die("推送失败", output.strip()[:600])
    log("    已推送，workflow 应该已经触发")


# ─────────────────────────── Actions ───────────────────────────

def dispatch(token: str, owner: str, name: str, workflow: str = WORKFLOW) -> None:
    step("手动触发 workflow")
    try:
        api("POST", f"/repos/{owner}/{name}/actions/workflows/{workflow}/dispatches", token,
            {"ref": "main"})
    except GitHubError as error:
        die(f"触发失败（HTTP {error.code}）", error.detail + "\n  workflow 里有 workflow_dispatch 才能在已推的仓库上重跑")
    log("    已触发")


def epoch_of(rfc3339: str) -> float:
    from datetime import datetime, timezone
    try:
        return datetime.fromisoformat(rfc3339.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return 0.0


def find_run(token: str, owner: str, name: str, since: float,
             workflow: str = WORKFLOW) -> dict | None:
    runs = api("GET", f"/repos/{owner}/{name}/actions/runs?per_page=20", token).get("workflow_runs", [])
    mine = [
        r for r in runs
        if r.get("path", "").endswith(workflow)
        and epoch_of(r.get("created_at", "")) >= since - 120  # 容忍时钟偏差
    ]
    if not mine:
        return None
    # push 和 dispatch 会各起一次 run，concurrency 会砍掉其中一个：优先没被取消的那个。
    for run_ in mine:
        if run_.get("conclusion") != "cancelled":
            return run_
    return mine[0]


def wait_for_run(token: str, owner: str, name: str, timeout: int,
                 workflow: str = WORKFLOW) -> dict:
    step("等待 macOS 构建")
    started = time.time()
    seen: dict | None = None
    while time.time() - started < timeout:
        try:
            run_ = find_run(token, owner, name, started, workflow)
        except GitHubError as error:
            warn(f"查询失败（HTTP {error.code}），重试")
            run_ = None

        if run_:
            seen = run_
            status, conclusion = run_.get("status"), run_.get("conclusion")
            elapsed = int(time.time() - started)
            log(f"    [{elapsed:>4}s] {status}{f' / {conclusion}' if conclusion else ''}"
                f"  {run_.get('html_url', '')}")
            if status == "completed":
                if conclusion == "success":
                    return run_
                if conclusion == "cancelled" and time.time() - started < 180:
                    # 另一个 run 抢了 concurrency 组；等它出来。
                    log("    这个 run 被 concurrency 取消了，等替代的 run")
                    time.sleep(POLL_SECONDS)
                    continue
                die(
                    f"构建失败（{conclusion}）",
                    f"看日志：{run_.get('html_url', '')}\n"
                    "  打开网页里第一个失败的红叉，把那一屏贴出来（clone 失败 ≠ 代码错）。",
                )
        else:
            log("    还没看到 run，等 15 秒")
        time.sleep(POLL_SECONDS)

    die("等待超时", f"继续看：{seen.get('html_url') if seen else f'https://github.com/{owner}/{name}/actions'}")


def download_artifact(token: str, owner: str, name: str, run_id: int, dest_dir: Path,
                      artifact: str = ARTIFACT, required: bool = True) -> Path | None:
    step("下载 ipa")
    artifacts = api("GET", f"/repos/{owner}/{name}/actions/runs/{run_id}/artifacts", token)
    target = next((a for a in artifacts.get("artifacts", []) if a["name"] == artifact), None)
    if not target:
        if not required:
            log(f"    （这次没有 {artifact} 产物，跳过）")
            return None
        names = ", ".join(a["name"] for a in artifacts.get("artifacts", [])) or "(空)"
        die(f"这次构建没有 {artifact} 产物", f"实际有：{names}")

    dest_dir.mkdir(parents=True, exist_ok=True)
    zip_path = dest_dir / f"{artifact}.zip"

    # 第一步要令牌，重定向到签名 URL 后必须去掉 Authorization，否则 401。
    opener = urllib.request.build_opener(NoRedirect)
    request = urllib.request.Request(f"{API}/repos/{owner}/{name}/actions/artifacts/{target['id']}/zip")
    request.add_header("Accept", "application/vnd.github+json")
    request.add_header("Authorization", f"Bearer {token}")
    request.add_header("User-Agent", "ihorizon-onclick")
    try:
        opener.open(request, timeout=60)
    except urllib.error.HTTPError as error:
        if error.code not in (301, 302, 303, 307, 308):
            die(f"取下载地址失败（HTTP {error.code}）", error.read().decode("utf-8", "replace")[:300])
        location = error.headers.get("Location")
        if not location:
            die("没有拿到重定向地址")
        with urllib.request.urlopen(location, timeout=600) as response, zip_path.open("wb") as handle:
            shutil.copyfileobj(response, handle)

    size = zip_path.stat().st_size
    log(f"    {zip_path.name}  {size / 1048576:.1f} MB")

    with zipfile.ZipFile(zip_path) as archive:
        archive.extractall(dest_dir)
    if artifact != ARTIFACT:
        # 探针产物就是一份日志，不是 ipa。
        logs = sorted(dest_dir.glob("*.log"))
        return logs[0] if logs else zip_path
    ipas = sorted(dest_dir.glob("*.ipa"))
    if not ipas:
        die("压缩包里没有 .ipa", f"内容：{[p.name for p in dest_dir.iterdir()]}")
    return ipas[0]


# ─────────────────────────── 主流程 ───────────────────────────

def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(
        description="一键把 ihorizon 推到 GitHub，等 macOS 编出 ipa 并下载",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--name", default="ihorizon", help="仓库名（默认 ihorizon）")
    parser.add_argument("--private", action="store_true", help="建私有仓库（macOS 分钟 10 倍计费）")
    parser.add_argument("--no-create", action="store_true", help="仓库要自己先建好")
    parser.add_argument("--no-wait", action="store_true", help="推完就走，不等构建")
    parser.add_argument("--build-only", action="store_true", help="只重新触发一次构建并下载")
    parser.add_argument("--token", help="直接给令牌，绕开不回显的粘贴")
    parser.add_argument("--probe", action="store_true",
                        help="跑上游 iOS 编译探针（macOS runner），拿回哪些 crate 编不过的清单")
    parser.add_argument("--probe-timeout", type=int, default=7200, help="探针超时秒数（默认 7200）")
    parser.add_argument("--timeout", type=int, default=2400, help="等构建的秒数上限（默认 2400）")
    parser.add_argument("--out", type=Path, default=ROOT / "dist", help="ipa 落地目录（默认 dist/）")
    parser.add_argument("--dry-run", action="store_true", help="只做本地检查")
    args = parser.parse_args()

    log("Horizon iOS 一键构建")
    log(f"目录：{ROOT}")

    step("检查工具")
    ensure_git()
    log(f"    {GIT}")
    log(f"    {run([GIT, '--version'], quiet=True).strip()}")
    if not (ROOT / ".github" / "workflows" / WORKFLOW).exists():
        die(f"缺 {WORKFLOW}", "这个脚本要放在 ihorizon 仓库根目录")
    for required in ("project.yml", "crates/horizon-ios-shell", "ios/Horizon"):
        if not (ROOT / required).exists():
            die(f"缺 {required}")

    if args.dry_run:
        ensure_repo()
        step("本地检查")
        ensure_staged()
        log("    dry-run：不联网、不提交。去掉 --dry-run 才真推。")
        git("status", "--short", check=False)
        return 0

    step("取令牌")
    token = resolve_token(interactive=True, explicit=args.token)

    if args.probe:
        owner = git_value("remote.origin.url").rstrip("/").split("/")[-2]
        name = git_value("remote.origin.url").rstrip("/").split("/")[-1].removesuffix(".git")
        # 关键：workflow 本身也在仓库里，改动不推上去，dispatch 跑的还是旧的 yml。
        step("推送当前改动")
        staged = ensure_staged()
        commit(staged)
        push(token, owner, name)
        dispatch(token, owner, name, PROBE_WORKFLOW)
        run_ = wait_for_run(token, owner, name, args.probe_timeout, PROBE_WORKFLOW)
        archive = download_artifact(token, owner, name, run_["id"], args.out / "probe", PROBE_ARTIFACT)
        report_probe(archive)
        return 0

    if args.build_only:
        owner = git_value("remote.origin.url").rstrip("/").split("/")[-2]
        name = git_value("remote.origin.url").rstrip("/").split("/")[-1].removesuffix(".git")
        if not owner or not name:
            die("读不出 origin", "先正常跑一遍不带 --build-only 的流程")
        step("推送当前改动")
        staged = ensure_staged()
        commit(staged)
        push(token, owner, name)
        # 推送本身就会触发 workflow；再 dispatch 会多起一个 run，互相取消。
        time.sleep(8)
        try:
            already = find_run(token, owner, name, time.time() - 300)
        except GitHubError:
            already = None
        if already is None:
            dispatch(token, owner, name)
        else:
            log(f"    推送已触发 run {already['id']}，不再重复 dispatch")
        run_ = wait_for_run(token, owner, name, args.timeout)
        ipa = download_artifact(token, owner, name, run_["id"], args.out)
        client = download_artifact(token, owner, name, run_["id"], args.out,
                                   CLIENT_ARTIFACT, required=False)
        report(ipa, owner, name, client)
        return 0

    step("准备仓库")
    ensure_repo()
    ensure_identity(token)
    staged = ensure_staged()
    commit(staged)

    step("确认远端")
    login = whoami(token)
    log(f"    登录为 {login}")
    owner, name = ensure_remote_repo(token, login, args.name, args.private, create=not args.no_create)
    ensure_remote(owner, name)

    push(token, owner, name)

    if args.no_wait:
        log(f"\n已推送。构建看：https://github.com/{owner}/{name}/actions")
        return 0

    run_ = wait_for_run(token, owner, name, args.timeout)
    ipa = download_artifact(token, owner, name, run_["id"], args.out)
    client = download_artifact(token, owner, name, run_["id"], args.out,
                               CLIENT_ARTIFACT, required=False)
    report(ipa, owner, name, client)
    return 0


def report_probe(path: Path) -> None:
    print()
    log(f"[1;32m✓ 探针日志：{path}[0m")
    text = path.read_text(encoding="utf-8", errors="replace") if path.is_file() else ""
    lines = [l for l in text.splitlines() if l.startswith("RESULT ")]
    if lines:
        print()
        log("结果：")
        for line in lines:
            _, crate, verdict = line.split()
            log(f"  {'OK  ' if verdict == 'ok' else 'FAIL'} {crate}")
    print()
    log("这份日志里 grep '^error' 就是完整的阻塞清单。")


def report(ipa: Path, owner: str, name: str, client: Path | None = None) -> None:
    size = ipa.stat().st_size / 1048576
    print()
    log(f"\033[1;32m✓ 壳 ipa：{ipa}  ({size:.1f} MB)\033[0m")
    if client is not None:
        csize = client.stat().st_size / 1048576
        log(f"\033[1;32m✓ 真客户端 ipa：{client}  ({csize:.1f} MB)\033[0m")
        print()
        log("装机用**真客户端**那个（第二个）：它就是 Horizon 本体，不再是绿色三角。")
    print()
    log("下一步：")
    log("  1. 装 Sideloadly（https://sideloadly.io），拖 ipa 进去，填 Apple ID")
    log("  2. 抽资源：$env:HORIZON_REPO=...; .\\scripts\\prepare_assets.ps1")
    log("  3. 传 zip 到手机 → 打开 Horizon → 导入 → 开始游戏")
    log(f"  仓库：https://github.com/{owner}/{name}")


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\n已中断", flush=True)
        sys.exit(130)

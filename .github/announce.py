"""Post this release's CHANGELOG.md section to Discord (the #announcements webhook).

Run by release.yml after the packager, from the repo root:
    python3 .github/announce.py v1.4.0
Env: DISCORD_WEBHOOK (the webhook URL, a repo secret), DISCORD_ROLE (optional repo
variable: the "<Addon> updates" role id to ping). Pre-release tags (with a "-") are skipped.
Check locally without posting:
    python .github/announce.py v1.4.0 --print

Same file in every addon repo that releases from GitHub: keep them in step.
"""

import glob
import json
import os
import re
import sys
import urllib.error
import urllib.request

LIMIT = 3800  # embed descriptions max out at 4096 characters
COLOR = 0xE8BB4A  # the server icon's gold


def warn(message):
    print(f"::warning::{message}")


def toc_info():
    tocs = sorted(glob.glob("*.toc"))
    if not tocs:
        return None, None, None
    folder = os.path.splitext(os.path.basename(tocs[0]))[0]
    text = open(tocs[0], encoding="utf-8-sig").read()

    def field(key):
        match = re.search(rf"^## {key}:\s*(.+?)\s*$", text, re.M)
        return match.group(1) if match else None

    title = field("Title") or folder
    title = re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", title)  # strip WoW color codes
    return folder, title, field("X-Curse-Project-ID")


def changelog_section(version):
    """The lines under '## v<version>' (or '## <version>'), up to the next '## '."""
    try:
        lines = open("CHANGELOG.md", encoding="utf-8-sig").read().splitlines()
    except FileNotFoundError:
        return None
    heading = re.compile(rf"^##\s+v?{re.escape(version)}(?=\s|$)")
    out, inside = [], False
    for line in lines:
        if inside and re.match(r"^##\s", line):
            break
        if inside:
            out.append(line)
        elif heading.match(line):
            inside = True
    body = "\n".join(out).strip()
    return body or None


def shorten(body, link):
    if len(body) <= LIMIT:
        return body
    cut = body.rfind("\n", 0, LIMIT)
    return body[: cut if cut > 0 else LIMIT].rstrip() + f"\n\n… [Full changelog]({link})"


def build(tag):
    version = tag[1:] if tag.startswith("v") else tag
    folder, title, curse = toc_info()
    if not folder:
        warn("No .toc file in the repo root; nothing announced.")
        return None
    body = changelog_section(version)
    if not body:
        warn(f"CHANGELOG.md has no '## {tag}' section; nothing announced.")
        return None

    repo = os.environ.get("GITHUB_REPOSITORY", f"lalibertemarc/{folder}")
    server = os.environ.get("GITHUB_SERVER_URL", "https://github.com")
    release = f"{server}/{repo}/releases/tag/{tag}"
    links = [f"[GitHub]({release})"]
    page = release
    if curse:
        page = f"https://www.curseforge.com/projects/{curse}"
        links.insert(0, f"[CurseForge]({page})")

    description = shorten(body, release) + "\n\n" + " · ".join(links)
    payload = {
        "embeds": [{"title": f"{title} {tag}", "url": page, "description": description, "color": COLOR}],
        "allowed_mentions": {"parse": []},
    }
    role = os.environ.get("DISCORD_ROLE", "").strip()
    if role:
        payload["content"] = f"<@&{role}>"
        payload["allowed_mentions"] = {"roles": [role]}
    return payload


def post(url, payload):
    request = urllib.request.Request(
        url, data=json.dumps(payload).encode("utf-8"), method="POST",
        # Discord turns away urllib's default user agent.
        headers={"Content-Type": "application/json", "User-Agent": "EzAddons-release/1.0"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            print(f"Announced on Discord ({response.status}).")
    except urllib.error.HTTPError as err:
        sys.exit(f"Discord refused the announcement: {err.code} {err.read().decode('utf-8', 'replace')}")


def main():
    args = [a for a in sys.argv[1:] if a != "--print"]
    if len(args) != 1:
        sys.exit("usage: announce.py <tag> [--print]")
    tag = args[0].removeprefix("refs/tags/")
    if "-" in tag:
        print(f"{tag} is a pre-release; not announced.")
        return
    payload = build(tag)
    if payload is None:
        return
    if "--print" in sys.argv:
        sys.stdout.reconfigure(encoding="utf-8")
        print(json.dumps(payload, indent=2, ensure_ascii=False))
        return
    url = os.environ.get("DISCORD_WEBHOOK", "").strip()
    if not url:
        print("DISCORD_WEBHOOK isn't set; not announced.")
        return
    post(url, payload)


if __name__ == "__main__":
    main()

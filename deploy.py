#!/usr/bin/env python3
"""Deploy the TH663i audit dashboard to GitHub Pages."""
import os
import subprocess
import urllib.request
import json
import sys

USER = "oclaw260-maker"
REPO = "th663i-audit"
SITE_DIR = "/home/turbo/th663-audit-site"

# Read token from saved env
token = None
env_path = os.path.expanduser("~/.hermes/.env")
with open(env_path) as f:
    for line in f:
        if line.startswith("GITHUB_TOKEN="):
            token = line.strip().split("=", 1)[1]
            break
assert token, "GITHUB_TOKEN not found in ~/.hermes/.env"

os.chdir(SITE_DIR)

# Init git if needed
if not os.path.exists(".git"):
    subprocess.run(["git", "init", "-b", "main"], check=True, capture_output=True)
    subprocess.run(["git", "config", "user.name", "oclaw260"], check=True)
    subprocess.run(["git", "config", "user.email", "oclaw260@gmail.com"], check=True)

# Commit
result = subprocess.run(["git", "add", "-A"], capture_output=True, text=True)
result = subprocess.run(["git", "commit", "-m", "Deploy TH663i audit dashboard"], capture_output=True, text=True)
print(f"git commit: {result.stdout}{result.stderr}")

# Create repo via API (idempotent)
req_body = json.dumps({
    "name": REPO,
    "private": False,
    "description": "Tropicana Macmahon TH663i weighing audit, sandvik FDM Event Hub data",
}).encode()
req = urllib.request.Request(
    f"https://api.github.com/user/repos",
    data=req_body,
    method="POST",
    headers={
        "Authorization": f"token {token}",
        "Accept": "application/vnd.github.v3+json",
        "Content-Type": "application/json",
    },
)
try:
    with urllib.request.urlopen(req, timeout=15) as r:
        print(f"Repo created: HTTP {r.status}")
        print(r.read().decode()[:500])
except urllib.error.HTTPError as e:
    body = e.read().decode()
    if e.code == 422 and "name already exists" in body:
        print(f"Repo already exists — proceeding to push")
    else:
        print(f"HTTP {e.code}: {body[:500]}")
        sys.exit(1)

# Set remote URL
subprocess.run(["git", "remote", "remove", "origin"], capture_output=True)
subprocess.run(
    ["git", "remote", "add", "origin", f"https://{token}@github.com/{USER}/{REPO}.git"],
    check=True,
)
# Push
result = subprocess.run(["git", "push", "-u", "origin", "main", "--force"], capture_output=True, text=True)
print(f"git push: {result.stdout}\n{result.stderr}")
if result.returncode != 0:
    print("Push failed")
    sys.exit(1)

# Enable Pages
req_body = json.dumps({"source": {"branch": "main", "path": "/"}}).encode()
req = urllib.request.Request(
    f"https://api.github.com/repos/{USER}/{REPO}/pages",
    data=req_body,
    method="POST",
    headers={
        "Authorization": f"token {token}",
        "Accept": "application/vnd.github.v3+json",
        "Content-Type": "application/json",
    },
)
try:
    with urllib.request.urlopen(req, timeout=15) as r:
        print(f"Pages enabled: HTTP {r.status}")
        print(r.read().decode()[:500])
except urllib.error.HTTPError as e:
    body = e.read().decode()
    if e.code == 409 or e.code == 422:
        print(f"Pages already enabled or in conflict: HTTP {e.code}")
    else:
        print(f"HTTP {e.code}: {body[:500]}")

print()
print(f"URL: https://{USER}.github.io/{REPO}/")

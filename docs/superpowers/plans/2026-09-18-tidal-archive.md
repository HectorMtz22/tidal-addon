# Tidal Archive Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A local-only repo that vendors the reviewed OrpheusDL framework + Tidal module with TLS hardening committed, builds a hardened non-root container, and ships TrueNAS deploy files + runbook for archiving Tidal HiFi to FLAC.

**Architecture:** Two TrueNAS apps — Navidrome from the catalog (reads `tank/music` read-only, serves Subsonic on 4533 over Tailscale) and a custom-app OrpheusDL container built from this repo's vendored fork (writes `tank/music`, exec-driven, no ports). Egress to Tidal domains only, by construction: no pip/git/network at build or runtime.

**Tech Stack:** Python 3.11-slim (Docker), ffmpeg binary, OrpheusDL framework (Python, vendored), docker compose (TrueNAS custom app), plain bash test script.

**Spec:** `docs/superpowers/specs/2026-09-18-tidal-archive-design.md` (read it before executing; this plan argues from it).

## Global Constraints

- Repo is **local-only**: never add a remote, never push (upstream code has no license).
- Vendored upstream refs are pinned and must not drift without re-review:
  - framework `yarrm80s/orpheusdl` @ `a45ff47913508d4c09971bdb847d5845984f1e64` (2023-12-16)
  - module `Dniel97/orpheusdl-tidal` @ `0d805ff5bf88441690a59c06c8c0dc1ae4fcbf3c` (2025-12-15)
- TLS hardening: **no** `os.environ['CURL_CA_BUNDLE'] = ''`, no `urllib3.disable_warnings(...)`, no `verify=False` anywhere in vendored code. Fixes are commits *inside* each vendored clone's own git history (nested repos are intentional gitlinks in this repo).
- Base image `python:3.11-slim`; container runs as uid 1000; container filesystem read-only at runtime; tmpfs `/tmp`.
- OrpheusDL container exposes **no ports**; entrypoint idles (`sleep infinity`); operator drives via `docker exec -it`.
- Login is TV/device-code ONLY (never the Mobile option — it prompts for the account password).
- `config/loginstorage.bin` is gitignored and must never enter git history.
- Egress allowlist (documented contract): `auth.tidal.com`, `api.tidal.com`, `resources.tidal.com`, `tidal.com`, `dd.tidal.com`.
- No runtime or build-time access to GitHub/PyPI in the deployed image (deps baked in via `docker/requirements.lock`).

## File Structure

```
tidal-addon/
├── CONTEXT.md                        # exists
├── docs/superpowers/specs/           # exists (spec committed)
├── docs/superpowers/plans/           # this plan
├── vendor/
│   ├── orpheusdl-framework/          # Task 1: clone @ pinned commit + TLS fix commits
│   └── orpheusdl-tidal/              # Task 2: clone @ pinned commit + TLS fix commit
├── VENDOR.md                         # Task 2: upstream refs + review dates
├── docker/
│   ├── requirements.txt              # Task 3: verbatim copy of framework requirements
│   ├── requirements.lock             # Task 3: pip freeze output (exact pins)
│   ├── Dockerfile                    # Task 3
│   └── .dockerignore                 # Task 3
├── deploy/
│   └── orpheusdl-compose.truenas.yml # Task 5
├── tests/
│   └── hardening.sh                  # Task 4: build + hardening assertions
├── docs/
│   ├── RUNBOOK.md                    # Task 6
│   └── review-workflow.md            # Task 6
└── .gitignore                        # Task 1
```

---

### Task 1: Vendor the framework clone with TLS fixes

**Files:**
- Create: `vendor/orpheusdl-framework/` (git clone of upstream @ pinned commit, nested repo)
- Create: `.gitignore`
- Modify: `vendor/orpheusdl-framework/orpheus/core.py` (delete lines 9–10)
- Modify: `vendor/orpheusdl-framework/utils/utils.py:47` (drop `verify=False`)

**Interfaces:**
- Produces: `vendor/orpheusdl-framework/` at fixed commit with fixes committed locally; Tasks 3–4 consume this directory verbatim via Dockerfile COPY.

- [ ] **Step 1: Create .gitignore**

Create `/Users/kilo/dev/tidal-addon/.gitignore`:

```gitignore
# credentials — must never enter git history
config/
*.bin
loginstorage.bin

# music output (in case of accidental local runs)
downloads/

# macos noise
.DS_Store
```

- [ ] **Step 2: Clone framework at pinned commit**

```bash
cd /Users/kilo/dev/tidal-addon/vendor
git clone https://github.com/yarrm80s/orpheusdl orpheusdl-framework
cd orpheusdl-framework
git checkout a45ff47913508d4c09971bdb847d5845984f1e64
git log -1 --format='%H %ci'   # must print a45ff47913508d4c09971bdb847d5845984f1e64 2023-12-16
```

Expected: HEAD is the pinned commit. If HEAD differs, STOP and report — the reviewed code is the only trusted code.

- [ ] **Step 3: Verify the insecure code is present (pre-fix state)**

```bash
grep -n "CURL_CA_BUNDLE\|disable_warnings" orpheus/core.py
grep -n "verify=False" utils/utils.py
```

Expected: `orpheus/core.py` line 9 shows `os.environ['CURL_CA_BUNDLE'] = ''`, line 10 shows `urllib3.disable_warnings(...)`; `utils/utils.py` line 47 shows `verify=False`. If not found, STOP and report — upstream moved.

- [ ] **Step 4: Apply the TLS fix in core.py**

Delete these two lines from `orpheus/core.py` (lines 9–10), keeping the rest intact:

```python
os.environ['CURL_CA_BUNDLE'] = ''  # Hack to disable SSL errors for requests module for easier debugging
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)  # Make SSL warnings hidden
```

Also remove the now-unused `urllib3` from the import on line 1, changing:

```python
import importlib, json, logging, os, pickle, requests, urllib3, base64, shutil
```

to:

```python
import importlib, json, logging, os, pickle, requests, base64, shutil
```

- [ ] **Step 5: Apply the TLS fix in utils/utils.py:47**

Change:

```python
    r = r_session.get(url, stream=True, headers=headers, verify=False)
```

to:

```python
    r = r_session.get(url, stream=True, headers=headers)
```

(requests defaults to `verify=True`.)

- [ ] **Step 6: Verify fixes + syntax**

```bash
! grep -rn "CURL_CA_BUNDLE\|disable_warnings\|verify=False" orpheus/ utils/ modules/ || echo "FAIL: insecure code still present"
python3 -m py_compile orpheus/core.py utils/utils.py orpheus.py
```

Expected: the compound grep prints `FAIL` **only** if insecure code remains (target: no output at all from the `!` test — i.e. grep found nothing); py_compile exits 0 with no output.

- [ ] **Step 7: Commit the fix inside the vendored clone**

```bash
git add orpheus/core.py utils/utils.py
git commit -m "Restore TLS verification (remove CURL_CA_BUNDLE hack, verify=False, warning suppression)"
```

- [ ] **Step 8: Return to parent repo and stage the gitlink**

```bash
cd /Users/kilo/dev/tidal-addon
git add .gitignore vendor/orpheusdl-framework
git status   # vendor/orpheusdl-framework shows as one entry (embedded repo) — expected
git commit -m "Vendor orpheusdl framework @ a45ff47 with TLS hardening"
```

Note: git records the vendored clone as an embedded repo (gitlink). This is intentional: fixes live as commits inside the clone's own history, and `git diff upstream/main` inside `vendor/orpheusdl-framework` stays meaningful. The repo is local-only, so the NAS gets the directory via rsync/copy including its nested `.git`.

---

### Task 2: Vendor the tidal module clone with TLS fix + VENDOR.md

**Files:**
- Create: `vendor/orpheusdl-tidal/` (git clone of upstream @ pinned commit, nested repo)
- Create: `VENDOR.md`
- Modify: `vendor/orpheusdl-tidal/interface.py:841` (drop `verify=False`)

**Interfaces:**
- Produces: `vendor/orpheusdl-tidal/` with `__init__.py`, `interface.py`, `tidal_api.py`, `mqa_identifier_python/`; Task 3 copies it to `/orpheus/modules/tidal/`. The framework discovers modules via `modules/<dir>/interface.py` exposing `module_information` (a `ModuleInformation` with `service_name="TIDAL"`).

- [ ] **Step 1: Clone module at pinned commit**

```bash
cd /Users/kilo/dev/tidal-addon/vendor
git clone https://github.com/Dniel97/orpheusdl-tidal orpheusdl-tidal
cd orpheusdl-tidal
git checkout 0d805ff5bf88441690a59c06c8c0dc1ae4fcbf3c
git log -1 --format='%H %ci'   # must print 0d805ff5bf88441690a59c06c8c0dc1ae4fcbf3c 2025-12-15
```

Expected: HEAD is the pinned commit; if not, STOP and report.

- [ ] **Step 2: Verify pre-fix state**

```bash
grep -n "verify=False" interface.py
```

Expected: line 841 `r = r_session.get(file_url, stream=True, verify=False)`. If not found, STOP and report.

- [ ] **Step 3: Apply the fix**

Change line 841 to:

```python
        r = r_session.get(file_url, stream=True)
```

- [ ] **Step 4: Verify + syntax check + commit**

```bash
! grep -rn "verify=False\|verify =" interface.py tidal_api.py __init__.py || echo "FAIL: insecure verify still present"
python3 -m py_compile interface.py tidal_api.py
git add interface.py
git commit -m "Restore TLS verification in download_temp_header"
```

Expected: no FAIL line; py_compile clean; commit created.

- [ ] **Step 5: Write VENDOR.md**

Create `/Users/kilo/dev/tidal-addon/VENDOR.md`:

```markdown
# Vendored upstreams

Both vendored codebases have NO license file ("all rights reserved" formally).
This repo and its vendored code are LOCAL-ONLY — never publish, never push.

| Vendored dir          | Upstream                          | Pinned commit                                | Reviewed     | Notes                              |
|-----------------------|-----------------------------------|----------------------------------------------|--------------|------------------------------------|
| vendor/orpheusdl-framework | https://github.com/yarrm80s/orpheusdl   | a45ff47913508d4c09971bdb847d5845984f1e64 | 2026-09 (two full source reviews) | Frozen Dec 2023 |
| vendor/orpheusdl-tidal     | https://github.com/Dniel97/orpheusdl-tidal | 0d805ff5bf88441690a59c06c8c0dc1ae4fcbf3c | 2026-09 (two full source reviews) | Active Dec 2025 |

TLS hardening is committed on top of each pinned snapshot:
- framework: remove `CURL_CA_BUNDLE` env deletion + `urllib3.disable_warnings` (orpheus/core.py),
  remove `verify=False` (utils/utils.py:47).
- module: remove `verify=False` (interface.py:841).

Any future change requires the diff review in docs/review-workflow.md first.
```

- [ ] **Step 6: Commit**

```bash
cd /Users/kilo/dev/tidal-addon
git add VENDOR.md vendor/orpheusdl-tidal
git commit -m "Vendor Dniel97 orpheusdl-tidal @ 0d805ff with TLS hardening; add VENDOR.md"
```

---

### Task 3: requirements lock + Dockerfile + .dockerignore

**Files:**
- Create: `docker/requirements.txt` (verbatim copy of framework requirements)
- Create: `docker/requirements.lock` (exact pins, generated)
- Create: `docker/Dockerfile`
- Create: `docker/.dockerignore`

**Interfaces:**
- Consumes: `vendor/orpheusdl-framework/` and `vendor/orpheusdl-tidal/` from Tasks 1–2 (paths exactly as there).
- Produces: image buildable as `orpheusdl:hardened` with layout `/orpheus/` = framework root, `/orpheus/modules/tidal/` = module, `/orpheus/config` and `/orpheus/music` mount points, uid 1000 user `orpheus`. Tasks 4–6 rely on this layout.

- [ ] **Step 1: Copy framework requirements verbatim**

```bash
cp /Users/kilo/dev/tidal-addon/vendor/orpheusdl-framework/requirements.txt /Users/kilo/dev/tidal-addon/docker/requirements.txt
```

The file content is exactly:

```
defusedxml>=0.7.1
protobuf==3.15.8
pycryptodomex>=3.10.1
requests>=2.25.1
Pillow>=8.2.0
tqdm>=4.60.0
mutagen>=1.45.1
ffmpeg-python>=0.2.0
m3u8>=2.0.0
```

(Trailing newline, no `m3u8` line break — the upstream file ends `m3u8>=2.0.0` without a newline; ensure the copy preserves it, then normalize by adding a trailing newline.)

- [ ] **Step 2: Generate requirements.lock (exact pins)**

```bash
cd /Users/kilo/dev/tidal-addon
docker run --rm -v "$PWD/docker:/tmp/docker" python:3.11-slim \
  sh -c 'pip install --quiet -r /tmp/docker/requirements.txt && pip freeze | sort > /tmp/docker/requirements.lock'
cat docker/requirements.lock
```

Expected: a lock file with pinned versions including `protobuf==3.15.8` and a line for each of defusedxml, pycryptodomex, requests, Pillow, tqdm, mutagen, ffmpeg-python, m3u8 and their transitive deps. Commit the lock verbatim — do not hand-edit.

- [ ] **Step 3: Write the Dockerfile**

Create `/Users/kilo/dev/tidal-addon/docker/Dockerfile`:

```dockerfile
FROM python:3.11-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends ffmpeg \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /orpheus
COPY vendor/orpheusdl-framework/ /orpheus/
COPY vendor/orpheusdl-tidal/ /orpheus/modules/tidal/

COPY docker/requirements.lock /tmp/requirements.lock
RUN pip install --no-cache-dir -r /tmp/requirements.lock \
 && rm /tmp/requirements.lock

RUN useradd -u 1000 -m orpheus \
 && mkdir -p /orpheus/config /orpheus/music \
 && chown -R orpheus:orpheus /orpheus

USER orpheus
WORKDIR /orpheus

CMD ["sleep", "infinity"]
```

Rationale baked in: framework root is the working dir (config auto-creates at `/orpheus/config`); module lands at `/orpheus/modules/tidal/` matching the framework's `modules/<name>/interface.py` discovery; `ffmpeg` binary is required at runtime by `orpheus/music_downloader.py` codec-conversion fallback; no network access at runtime since everything is baked in.

- [ ] **Step 4: Write .dockerignore**

Create `/Users/kilo/dev/tidal-addon/docker/.dockerignore`... note: docker build context root is the repo root (Task 5 invokes `docker build` from repo root), so this file must live at the repo root as `.dockerignore`, not under `docker/`:

Create `/Users/kilo/dev/tidal-addon/.dockerignore`:

```
**/.git
**/config
**/downloads
docs/
deploy/
tests/
```

This keeps nested `.git` dirs out of the image and the context small.

- [ ] **Step 5: Build the image — NAS-SIDE ONLY (do not run Docker on the Mac)**

Building and verification happen on the NAS during deployment (RUNBOOK §2):

```bash
docker build -f docker/Dockerfile -t orpheusdl:hardened .   # run on the NAS
```

Note the `-f docker/Dockerfile` form: build context is the repo root. Expected: build succeeds; final stages show `useradd` and `pip install` completing without network errors.

- [ ] **Step 6: Smoke-test the module import inside the image (NAS-side)**

```bash
docker run --rm orpheusdl:hardened python -c \
  "import sys; sys.path.insert(0, '/orpheus'); from modules.tidal.interface import module_information as mi; assert mi.service_name == 'TIDAL', mi.service_name; print('module import OK')"
```

Expected: `module import OK`. If it fails with `ModuleNotFoundError`, a transitive dep is missing from `requirements.lock` — regenerate the lock (Step 2) from a session that also installs the module, then rebuild. Only regenerate if Step 6 actually failed — do not pre-optimize.

If Docker is unavailable in the implementation environment, Step 7 commits the files unexecuted and Steps 5–6 transfer to the NAS deployment (RUNBOOK §2 + tests/hardening.sh from Task 4 covers both). Record the transfer in the plan ledger.

- [ ] **Step 7: Commit**

```bash
cd /Users/kilo/dev/tidal-addon
git add docker/requirements.txt docker/requirements.lock docker/Dockerfile .dockerignore
git commit -m "Add hardened OrpheusDL image: pinned deps, ffmpeg, non-root uid 1000"
```

---

### Task 4: Hardening test script

**Files:**
- Create: `tests/hardening.sh`

**Interfaces:**
- Consumes: image `orpheusdl:hardened` (Task 3) and vendored paths (Tasks 1–2).
- Produces: repeatable verification entry point used by the runbook's build step.

- [ ] **Step 1: Write the script**

Create `/Users/kilo/dev/tidal-addon/tests/hardening.sh`:

```bash
#!/usr/bin/env bash
# Hardening assertions for the orpheusdl:hardened image.
# Exit 0 = all pass. Any FAIL exits 1.
set -u
cd "$(dirname "$0")/.."

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: $1"; }

# 1. No TLS-stripping code anywhere in vendored sources
if grep -rn "CURL_CA_BUNDLE\|disable_warnings\|verify=False" \
    vendor/orpheusdl-framework/orpheus vendor/orpheusdl-framework/utils \
    vendor/orpheusdl-tidal/interface.py vendor/orpheusdl-tidal/tidal_api.py 2>/dev/null; then
  fail "insecure TLS code still present in vendored sources"
fi
pass "no TLS-stripping code in vendored sources"

# 2. Image exists
docker image inspect orpheusdl:hardened > /dev/null 2>&1 || fail "image orpheusdl:hardened not built"

# 3. Container runs as non-root uid 1000
uid="$(docker run --rm orpheusdl:hardened id -u)"
[ "$uid" = "1000" ] || fail "container uid is $uid, expected 1000"
pass "container runs as uid 1000"

# 4. Tidal module loads in the image
docker run --rm orpheusdl:hardened python -c \
  "import sys; sys.path.insert(0, '/orpheus'); from modules.tidal.interface import module_information as mi; assert mi.service_name == 'TIDAL'" \
  || fail "tidal module failed to import in image"
pass "tidal module imports in image"

# 5. ffmpeg binary present in image
docker run --rm orpheusdl:hardened ffmpeg -version > /dev/null 2>&1 || fail "ffmpeg missing in image"
pass "ffmpeg present in image"

echo "All hardening checks passed."
```

- [ ] **Step 2: Run it — NAS-SIDE ONLY (requires the built image)**

```bash
chmod +x tests/hardening.sh && ./tests/hardening.sh
```

This script needs `orpheusdl:hardened` (check 2–5) — run it on the NAS during deployment (RUNBOOK §2). In the implementation environment WITHOUT Docker: `docker image inspect`/`docker run` calls will fail — that is the expected result locally; checks 1 (source grep) must pass locally. If Docker IS available and the user has approved NAS-side-equivalent builds, all five PASS lines are expected. If check 1 fails, Tasks 1–2 fixes were not applied correctly — fix the vendored code first.

- [ ] **Step 3: Commit**

```bash
git add tests/hardening.sh
git commit -m "Add hardening assertions for vendored sources and image"
```

---

### Task 5: TrueNAS deploy compose file

**Files:**
- Create: `deploy/orpheusdl-compose.truenas.yml`

**Interfaces:**
- Consumes: image `orpheusdl:hardened` (built on the NAS per runbook), dataset paths defined below.
- Produces: the exact YAML pasted into TrueNAS Apps → Discover Apps → Install via YAML.

- [ ] **Step 1: Write the compose file**

Create `/Users/kilo/dev/tidal-addon/deploy/orpheusdl-compose.truenas.yml`:

```yaml
# OrpheusDL (hardened vendored fork) — TrueNAS custom app.
# Build the image on the NAS first: docker build -t orpheusdl:hardened <repo-dir>
# No ports: exec-driven only (docker exec -it orpheusdl python orpheus.py).
services:
  orpheusdl:
    image: orpheusdl:hardened
    container_name: orpheusdl
    user: "1000:1000"
    command: ["sleep", "infinity"]
    read_only: true
    tmpfs:
      - /tmp
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    restart: unless-stopped
    volumes:
      - /mnt/tank/music:/orpheus/music
      - /mnt/tank/apps/orpheusdl/config:/orpheus/config
```

Dataset paths are the spec's `tank/music` and `tank/apps/orpheusdl/config`; adjust the pool name in the YAML only if the NAS pool is not named `tank` (runbook says so too).

- [ ] **Step 2: Validate locally**

```bash
docker compose -f deploy/orpheusdl-compose.truenas.yml config > /dev/null && echo "compose valid"
```

Expected: `compose valid`. (Image may not exist locally as `orpheusdl:hardened` unless Task 3 Step 5 built it — compose `config` does not require the image to exist.)

- [ ] **Step 3: Commit**

```bash
git add deploy/orpheusdl-compose.truenas.yml
git commit -m "Add TrueNAS custom-app compose for OrpheusDL"
```

---

### Task 6: Runbook + review workflow

**Files:**
- Create: `docs/RUNBOOK.md`
- Create: `docs/review-workflow.md`

**Interfaces:**
- Consumes: compose file (Task 5), image name `orpheusdl:hardened` (Task 3), dataset paths (spec), `tests/hardening.sh` (Task 4).

- [ ] **Step 1: Write RUNBOOK.md**

Create `/Users/kilo/dev/tidal-addon/docs/RUNBOOK.md`:

````markdown
# Tidal Archive Runbook

Prereq: image built from this repo (tests/hardening.sh passes). Login is
TV/device-code ONLY — never the Mobile option (it asks for your Tidal password
in the terminal).

## 1. Datasets (TrueNAS shell or UI)

```sh
zfs create tank/music
zfs create -p tank/apps/orpheusdl/config
```

If the pool is not `tank`, substitute your pool name everywhere (including
deploy/orpheusdl-compose.truenas.yml).

Set ownership for the container's uid 1000:

```sh
chown -R 1000:1000 /mnt/tank/apps/orpheusdl/config
# tank/music can stay root-owned; container uid 1000 needs write access:
chmod 775 /mnt/tank/music
# or, cleaner: chown 1000:1000 /mnt/tank/music
```

## 2. Get the repo + image onto the NAS

From the Mac (repo is local-only; no GitHub push, no Docker builds on the Mac):

```sh
rsync -a /Users/kilo/dev/tidal-addon/ nas:/opt/tidal-addon/
```

(Do not exclude `.git`: the vendored clones need their nested `.git` preserved
for future diff review. The parent repo has no remote, so nothing is pushed.)

On the NAS:

```sh
cd /opt/tidal-addon
./tests/hardening.sh          # builds nothing; asserts vendored code + image
docker build -t orpheusdl:hardened .
./tests/hardening.sh          # now everything passes
```

## 2b. Alternative: build on the Mac, load on the NAS

Removed by ruling (2026-09-18): builds happen on the NAS only; the Mac is used
for repo authoring and review, not Docker execution.

## 3. Install the custom app

TrueNAS UI: Apps → Discover Apps → ⋮ → Install via YAML → paste
`deploy/orpheusdl-compose.truenas.yml`. Verify:

```sh
docker ps | grep orpheusdl
docker exec orpheusdl id -u    # -> 1000
```

## 4. First login (TV/device-code only)

```sh
docker exec -it orpheusdl python orpheus.py
```

- Choose the TIDAL module. At the login prompt choose **1. TV (browser)**,
  open the shown URL on your phone, enter the code.
- NEVER choose the Mobile option (it prompts for your account password).
- After login, immediately lock the credential file down:

```sh
chmod 700 /mnt/tank/apps/orpheusdl/config
chmod 600 /mnt/tank/apps/orpheusdl/config/loginstorage.bin
```

`loginstorage.bin` is a plaintext pickle of your Tidal access+refresh tokens —
treat it as account-equivalent.

## 5. Point downloads at the music dataset

On first run the framework generated `config/settings.py`. Edit it (from the
Mac or via exec):

```
"download_path": "/orpheus/music/"
"download_quality": "hifi"     # already the default; FLAC
```

Then inside orpheus: paste album/playlist URLs, pick from search results.
Files land in `Artist/Album/` folders on `tank/music`.

## 6. Navidrome (catalog app)

- Apps → Discover Apps → Navidrome → install; mount `/mnt/tank/music`
  (READ-ONLY), port 4533 (default).
- Create the Subsonic user in Navidrome's UI (its own user/pass).
- Verify: `curl http://<nas-ip>:4533/ping` → `{"status":"ok"}` (or Tailscale IP).
- iPhone: install play:Sub / Amperfy / Symfonium → add server
  `http://<tailscale-ip>:4533` + Subsonic creds → check screen-off playback,
  offline sync, and cell streaming.

## 7. Update the vendored code (trust gate — mandatory)

See docs/review-workflow.md. Short version: pull upstream inside the vendored
clone ON THE MAC, read the full diff against the checklist, merge only if
clean, then rebuild the image on the NAS. The container itself never touches
GitHub or PyPI.

## 8. Leak response

If `loginstorage.bin` or the config dataset is exposed:

1. Change your Tidal password immediately.
2. Tidal web → Settings → sign out of ALL devices (invalidates refresh tokens).
3. Delete `loginstorage.bin`, re-login with the TV flow, re-apply chmod 700/600.

## 9. Known limits

- The old Tidal API this module uses may close at any time (Widevine/DRM
  rollout). Archive your essential library early.
- ToS risk: account action is possible; accepted.
- AAC-only tracks (Atmos/360) download as AAC; proprietary codecs stay disabled.
````

- [ ] **Step 2: Write review-workflow.md**

Create `/Users/kilo/dev/tidal-addon/docs/review-workflow.md`:

````markdown
# Upstream diff review workflow (mandatory before any vendor update)

The container runs only code that was read. Every upstream update goes through
this gate on the Mac, before the image is rebuilt.

## 1. Snapshot the current state

```sh
cd vendor/orpheusdl-framework    # (or orpheusdl-tidal)
git diff HEAD > /tmp/before.diff # local TLS fix layer
git remote -v                    # upstream must be yarrm80s/orpheusdl (or Dniel97/orpheusdl-tidal)
```

## 2. Fetch and diff

```sh
git fetch origin
git log --oneline HEAD..origin/master        # what's new?
git diff HEAD origin/master                  # the actual diff to review
```

## 3. Review checklist (all must be answered)

- [ ] Any new outbound domain/URL? (grep for `https://`, domain strings; must
      be Tidal domains only: auth/api/resources/dd .tidal.com, tidal.com)
- [ ] Any new subprocess/exec/eval/execfile/importlib usage?
- [ ] Any new file write outside the module dir or download path?
- [ ] Any change touching auth, token storage, or login flow?
- [ ] Any new third-party dependency (requirements.txt changes)? If yes:
      review that package's source too, or reject the update.
- [ ] Any obfuscated/encoded blobs (base64 > ~200 chars, hex strings, pyc)?
- [ ] TLS hygiene: still no verify=False / CURL_CA_BUNDLE / disable_warnings?
- [ ] Does the diff break our vendored layout (file/dir renames)?

## 4. Merge or reject

```sh
git merge origin/master        # if and only if every box is ticked
# re-apply/verify the TLS hardening still holds:
! grep -rn "verify=False\|CURL_CA_BUNDLE\|disable_warnings" . --include='*.py'
```

If any box is unticked: reject, stay on the pinned commit, and note it in
VENDOR.md. Never merge unreviewed.

## 5. Rebuild

Re-run Task 3 lock regeneration (requirements.txt may have changed),
rebuild the image, run tests/hardening.sh, then update VENDOR.md with the new
commit hash + review date.
````

- [ ] **Step 3: Commit**

```bash
git add docs/RUNBOOK.md docs/review-workflow.md
git commit -m "Add runbook and upstream review workflow"
```

---

## Final verification (after all tasks)

- [ ] `./tests/hardening.sh` → all PASS.
- [ ] `git log --oneline` shows ~6 clean commits; no `loginstorage.bin` or `config/` tracked (`git ls-files | grep -i "login\|config/"` → empty).
- [ ] No remote configured (`git remote -v` → empty).
- [ ] Navidrome side is a catalog install, not in this repo — only documented.

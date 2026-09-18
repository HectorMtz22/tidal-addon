# Tidal Archive Runbook

Prereq: image built from this repo (tests/hardening.sh passes). Login is
TV/device-code ONLY — never the Mobile option (it asks for your Tidal password
in the terminal).

## 1. Datasets (TrueNAS shell or UI)

```sh
zfs create drive/music
zfs create -p drive/orpheusdl/config
```

If the pool is not `drive`, substitute your pool name everywhere (including
deploy/orpheusdl-compose.truenas.yml).

Set ownership for the app user — nothing to do if the dataset already has
TrueNAS app ACLs (uid 568, the same user catalog apps like Navidrome use;
the container runs as 568 by default in the compose). Only if your dataset
is root-owned with no ACLs, grant write access:

```sh
chown 1000:1000 /mnt/drive/music-library   # or set ACLs in the TrueNAS UI
```

## 2. Get the repo + image onto the NAS

The repo is public now (user override, see VENDOR.md): the NAS can clone it
directly, and the CI-published image can be pulled instead of built. The
GitHub Action on every push to main builds the image and publishes
`ghcr.io/hectormtz22/tidal-addon:latest` (+ a sha tag) after the hardening
suite passes in CI. One-time: make the package public (GitHub profile ->
Packages -> tidal-addon -> Package settings -> Change visibility -> Public).

Clone on the NAS:

```sh
git clone https://github.com/HectorMtz22/tidal-addon /opt/tidal-addon
cd /opt/tidal-addon
```

The compose file (`deploy/orpheusdl-compose.truenas.yml`) already points at the
CI image `ghcr.io/hectormtz22/tidal-addon:latest` — that is the default path:

```sh
docker pull ghcr.io/hectormtz22/tidal-addon:latest
ORPHEUS_IMAGE=ghcr.io/hectormtz22/tidal-addon:latest ./tests/hardening.sh   # all five PASS
```

Option A (fallback, build on the NAS — never build on the Mac):

```sh
docker build -f docker/Dockerfile -t orpheusdl:hardened .
./tests/hardening.sh          # all five checks PASS
# then edit deploy/orpheusdl-compose.truenas.yml image: back to orpheusdl:hardened
```

(The previous rsync path still works if you ever want an unpublished copy:
`rsync -a /Users/kilo/dev/tidal-addon/ nas:/opt/tidal-addon/`. Do not exclude
`.git`.)

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
chmod 700 /mnt/drive/orpheusdl/config
chmod 600 /mnt/drive/orpheusdl/config/loginstorage.bin

stat -c '%a' /mnt/drive/orpheusdl/config                  # expect 700
stat -c '%a' /mnt/drive/orpheusdl/config/loginstorage.bin # expect 600
```

`loginstorage.bin` is a plaintext pickle of your Tidal access+refresh tokens —
treat it as account-equivalent.

## 5. Point downloads at the music dataset

On first run the framework generated `config/settings.json` (JSON, not .py).
Edit it (from the Mac or via exec) so the two keys read exactly:

```json
"download_path": "/orpheus/music/",
"download_quality": "hifi"
```

(Valid JSON: no trailing commas. The default `"./downloads/"` would hit the
container's read-only root and crash with `[Errno 30]`.)

Then inside orpheus: paste album/playlist URLs, pick from search results.
Files land in `Artist/Album/` folders on `drive/music`.

## 6. Navidrome (catalog app or custom app)

- Option A (catalog): Apps → Discover Apps → Navidrome → install; mount
  `/mnt/drive/music` (READ-ONLY), port 4533 (default).
- Option B (YAML): Apps → Discover Apps → ⋮ → Install via YAML → paste
  `deploy/navidrome-compose.truenas.yml` — music path, port 4533, read-only
  mount and scan schedule are already configured in the file.
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

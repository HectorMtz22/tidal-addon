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
# container uid 1000 needs write access:
chown 1000:1000 /mnt/tank/music
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
docker build -f docker/Dockerfile -t orpheusdl:hardened .
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

stat -c '%a' /mnt/tank/apps/orpheusdl/config                  # expect 700
stat -c '%a' /mnt/tank/apps/orpheusdl/config/loginstorage.bin # expect 600
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

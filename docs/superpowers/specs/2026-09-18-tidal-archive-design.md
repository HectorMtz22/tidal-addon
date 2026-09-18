# Tidal Archive — Design (2026-09-18)

Status: approved design, pending implementation plan.
Local-only repo: `/Users/kilo/dev/tidal-addon` (git, no remote).

## Purpose

Archive the owner's paid Tidal HiFi library to the TrueNAS NAS as bit-perfect FLAC
files, served to an iPhone over Tailscale by Navidrome. This is a hedge against
Tidal's Widevine/API cutover, which may close the download path used here at any
time. Not a Stremio addon despite the folder name; purely archival.

## Decisions locked (from prior research sessions)

- Archival tool: OrpheusDL framework (yarrm80s/orpheusdl, frozen Dec 2023) with
  Dniel97/orpheusdl-tidal module (active Dec 2025). Both were fully source-reviewed
  (two subagent reviews); no malicious code found. All outbound traffic is Tidal
  domains only.
- Server: Navidrome (Subsonic API), chosen over Jellyfin. iOS clients:
  play:Sub / Amperfy / Symfonium.
- Download quality: FLAC (bit-perfect). The module fetches the same stream manifest
  the official Tidal app receives and downloads the raw file bytes — no re-encode,
  no recording. AAC where Tidal has no FLAC; proprietary codecs left disabled.
- Deployment: two apps on TrueNAS — Navidrome from the catalog, OrpheusDL as a
  custom app installed via YAML.
- Fork policy: full vendored fork, local-only. No GitHub remote for this repo; the
  no-license ("all rights reserved") upstreams must never be republished.
- Interaction: stock interactive CLI via `docker exec` (TTY). Device-code login only.

## Mandatory hardening (baked into vendored code / deployment)

1. Restore TLS: remove `os.environ['CURL_CA_BUNDLE'] = ''` and adjacent
   `urllib3.disable_warnings` at orpheus/core.py:9; remove `verify=False` at
   utils/utils.py:47 and modules/tidal/interface.py:841. These land as commits on
   top of the vendored upstream snapshots.
2. Dedicated unprivileged user (uid 1000), read-only container filesystem,
   tmpfs /tmp.
3. Post-first-login permissions: `chmod 700 config/ && chmod 600
   config/loginstorage.bin` (plaintext pickle of access+refresh tokens —
   account-equivalent; pickle.load is RCE if writable by others).
4. Login via TV/device-code flow ONLY. Never the Mobile option (takes the account
   password in-terminal).
5. Container has zero outbound access except Tidal domains — by construction
   (no pip/git/network in the image; updates applied via reviewed vendor merges
   on the Mac, not in the container).
6. Leak response: change Tidal password and sign out all devices.

## Architecture

```
┌─ TrueNAS SCALE ─────────────────────────────────────────┐
│  Custom app "orpheusdl"            Catalog app          │
│  ┌──────────────────────────┐      ┌─────────────────┐  │
│  │ hardened-fork container  │      │ Navidrome       │  │
│  │ (this repo's Dockerfile) │      │ (official)      │  │
│  │ non-root uid 1000        │      │                 │  │
│  └───────┬──────────────────┘      └────────┬────────┘  │
│          │ rw (downloads)                   │ ro (serve)│
│          ▼                                  ▼           │
│  tank/music  (ZFS dataset, shared mount)                │
│  tank/apps/orpheusdl/config  (config + loginstorage)    │
└─────────────────────────────────────────────────────────┘

iPhone ──▶ Navidrome (Subsonic API) over Tailscale, port 4533
Mac ──▶ docker exec (TTY) ──▶ orpheusdl container
```

- OrpheusDL container exposes no ports; exec-driven only.
- Navidrome serves HTTP on 4533; transport security is provided by Tailscale
  (WireGuard), matching the youtube-addon trust model. No LAN-without-Tailscale
  exposure; if that changes, revisit Navidrome TLS options.
- Navidrome credentials are its own (Subsonic user/pass), unrelated to Tidal.

## Repo layout

```
tidal-addon/
├── CONTEXT.md
├── vendor/
│   ├── orpheusdl-framework/     # full clone + TLS fixes committed on top
│   └── orpheusdl-tidal/         # full clone + TLS fixes committed on top
├── docker/
│   ├── Dockerfile               # python:3.11-slim, non-root
│   └── requirements.lock        # exact pip pins from the reviewed state
├── deploy/
│   └── orpheusdl-compose.truenas.yml
├── docs/
│   ├── RUNBOOK.md
│   ├── review-workflow.md
│   └── superpowers/specs/       # this file
├── tests/                       # build + hardening assertions (plain script)
├── VENDOR.md                    # upstream refs: commit hashes + review dates
└── .gitignore                   # config/, *.bin, music outputs
```

- Vendored clones keep their git history; TLS fixes are commits, so future
  `git diff upstream` stays meaningful.
- The module is COPY'd into the framework's `modules/` dir at docker build.
- `config/loginstorage.bin` is gitignored and must never enter git history.

## Docker image

- Base: `python:3.11-slim` (framework frozen Dec 2023; pin the python minor).
- Nothing patched at build time; fixes are already committed in vendor/.
- Non-root uid 1000, no shell login. Entrypoint idles (sleep infinity); the
  operator runs `docker exec -it ... python orpheus.py`.
- Container root read-only; tmpfs /tmp. Writable mounts: config dataset, music
  dataset. No secrets in environment variables.
- `requirements.lock` pins pip deps exactly.

## Datasets (TrueNAS)

```
tank/music                        # FLAC archive; OrpheusDL rw, Navidrome ro
tank/apps/orpheusdl/config        # OrpheusDL config + loginstorage.bin (chmod 700/600)
```

Config is separated from music because it holds credentials and never needs
browsing; music is browsed/shared.

## Trust model & update workflow

- The container never talks to anything except Tidal domains; this holds by
  construction, not by enforcement (no proxy sidecar, no NET_ADMIN).
- Egress allowlist (review contract, documented): auth.tidal.com, api.tidal.com,
  resources.tidal.com, tidal.com, dd.tidal.com.
- Update path: on the Mac, `git pull upstream` inside vendor/, read the full diff
  against the review checklist (docs/review-workflow.md), merge if clean, rebuild
  the image on the NAS. The review step is the trust gate; skipping it is a
  documented residual risk.
- Hard enforcement (proxy sidecar with domain allowlist) is deferred; can be added
  later without restructuring.

## Runbook outline (docs/RUNBOOK.md)

1. Dataset prep (create datasets, uid 1000 ownership).
2. Build on NAS (repo to NAS or docker save/load; build; install custom app YAML).
3. First login (exec + TV device-code; then chmod 700/600 on config).
4. Download sessions (exec, paste URLs, FLAC).
5. Navidrome verify (albums appear on iPhone).
6. Update procedure (pull, review diff, rebuild).
7. Leak response (password change, sign out all devices).
8. iPhone checklist (screen-off playback, offline sync, cell streaming).

## Testing & verification

- `tests/` plain script asserting on the built image:
  a) TLS fixes present (absence of CURL_CA_BUNDLE deletion / verify=False),
  b) runs as non-root,
  c) default loginstorage.bin permissions are restrictive.
- Runbook functional one-liners: Navidrome /ping, orpheus --help, config perms.
- No unit tests for vendored code — the reviewed-snapshot + diff-review model is
  the quality gate for third-party code.

## Risks (accepted, documented)

- API cutover: Widevine/DRM rollout can break the module without warning. Archive
  the essential library early — this is the project's whole reason to exist.
- ToS violation: possible account action; accepted.
- No license: local fork only; never redistribute or publish.
- Unreviewed future upstream diffs: mitigated by the mandatory review workflow;
  residual risk remains if skipped (documented in runbook).
- loginstorage.bin leak: account-equivalent credentials; chmod post-login +
  gitignore + separate config dataset reduce blast radius; leak response step
  invalidates tokens.

## Out of scope

- SponsorBlock / tag fixups beyond what the framework already does.
- Non-interactive/batch download scripting (interactive exec only for v1).
- Public redistribution of any vendored code.
- Music library management beyond what Navidrome provides.

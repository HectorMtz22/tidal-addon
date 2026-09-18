# Session Context — YouTube/Tidal NAS project (kilo)

Feed this file to a fresh session: "Read /Users/kilo/dev/youtube-addon/CONTEXT.md and continue."
Last updated: 2026-09-18.

## Who I am / environment
- Security-conscious home-lab user. Trust third-party code only after source review.
- Self-hosted device: TrueNAS SCALE (custom apps installed via YAML, Docker under the hood).
- iPhone (iOS 26 era) — wants ad-free YouTube and music with screen-off playback.
- GitHub: HectorMtz22 (SSH auth). Prefers LAN/Tailscale-only exposure, bearer-token auth, no cookies where avoidable.
- Communication style: direct, concise; likes decisions surfaced with trade-offs; accepts documented risk after honest framing.

## Completed work — youtube-addon (public repo, merged to main)
Repo: https://github.com/HectorMtz22/youtube-addon (public). Local: /Users/kilo/dev/youtube-addon (branch main).
- A self-hosted Stremio addon: ad-free YouTube search + playback in Stremio on iOS.
  Node 22 ESM/Express, stateless, token-authenticated (all routes under /{token}/, token >= 20 chars, ADDON_TOKEN env, no defaults).
- Playback ladder: HLS manifest URL from yt-dlp (primary, native seek/PiP) -> ffmpeg `-c copy` fMP4 remux (fallback, broken seeking accepted) -> 360p itag 18 (last resort).
  Route paths: /:token/manifest.json, /catalog/:type/:id/:extra?.json, /meta/:type/:videoId.json, /stream/:type/:videoId.json, /play/:videoId.mp4?height=h.
  Stremio ids use `yt:` prefix (idPrefixes). No cookies ever. No SponsorBlock (v1 non-goal).
- yt-dlp pinned per build + SHA256-verified in Dockerfile; non-root, read_only fs, tmpfs /tmp.
- Tests: `npm test` -> 27/27 passing (node --test, glob script due to Node 24 quirk).
- CI: .github/workflows/docker-publish.yml pushes ghcr.io/hectormtz22/youtube-addon:latest (+ sha tag) on every main merge; yt-dlp version auto-resolved to latest release at build time. Workflow green.
- Deployment doc: docs/RUNBOOK.md (TrueNAS custom-app section + plain Docker + iPhone verification checklist).
- Spec + plan kept locally ONLY (gitignored): docs/superpowers/spec-2026-09-17.md, plan-2026-09-17.md.

## Completed work — tidal-archive (public repo, merged to main)
Repo: https://github.com/HectorMtz22/tidal-addon (PUBLIC — user explicitly overrode the "never publish / no license" rule on 2026-09-18; risk accepted, recorded in VENDOR.md). Local: /Users/kilo/dev/tidal-addon (branch main, remote = github SSH).
- Vendors the reviewed OrpheusDL framework (yarrm80s/orpheusdl @ a45ff47) and Dniel97/orpheusdl-tidal @ 0d805ff as nested git clones with TLS-hardening commits on top (CURL_CA_BUNDLE, disable_warnings, verify=False all removed; also mqa_identifier_python vendored @ ff0c9f1).
- Docker image: CI-published ghcr.io/hectormtz22/tidal-addon:latest on every main push (docker-publish.yml: build -> hardening.sh all-PASS -> push); one-time UI flip makes the package public. NAS can clone the repo or pull the image (RUNBOOK §2 Option A/B).
- deploy/orpheusdl-compose.truenas.yml (custom app; no ports, cap_drop ALL, read_only, tmpfs, user 1000); tests/hardening.sh (check 1 = source TLS gate, runs anywhere; checks 2–5 need the image, run on NAS).
- docs/RUNBOOK.md (datasets, NAS build, TV-only login, chmod 700/600, settings download_path=/orpheus/music/, Navidrome catalog app + iPhone checklist, leak response) + docs/review-workflow.md (mandatory upstream diff review) + VENDOR.md (pinned refs + hardening record).
- Spec + plan: docs/superpowers/specs/2026-09-18-tidal-archive-design.md, docs/superpowers/plans/2026-09-18-tidal-archive.md. Full subagent-driven execution with reviews; final review fixes merged.

## PENDING (user actions, not done yet)
1. Deploy tidal-archive on TrueNAS per docs/RUNBOOK.md §1–§6 (datasets → rsync → NAS build + hardening.sh all-PASS → custom app YAML → TV login → chmod → downloads → Navidrome catalog app).
2. Navidrome: mount tank/music read-only, port 4533, Subsonic creds; iPhone client via Tailscale.
3. Archive essential Tidal library EARLY (old API may close with Widevine rollout).

## PENDING — youtube-addon (carried from previous session)
1. Flip ghcr container package to public: GitHub profile -> Packages -> youtube-addon -> Package settings -> Change visibility -> Public. (Repo is public; the package is still private.)
2. Deploy on TrueNAS: Apps -> Discover Apps -> Install via YAML -> paste deploy/docker-compose.truenas.yml, set ADDON_TOKEN (openssl rand -hex 16), Web UI port 7000. Verify curls in runbook.
3. Stremio iOS: install via http://<nas-ip>:7000/<token>/manifest.json; run the runbook iPhone checklist. NOTE: the "HLS-first" POC verdict is PROVISIONAL — the cross-IP (iPhone/Tailscale) playback check was never performed; if HLS fails cross-IP, extraction URLs are IP-bound and fMP4 becomes the ladder top.

## Tidal plan (IMPLEMENTED — see Completed work above)
Decision made by user: archive Tidal (paid account) to NAS via OrpheusDL + Dniel97/orpheusdl-tidal, served by Navidrome (Subsonic; iOS clients: play:Sub/Amperfy/Symfonium). Full source review WAS DONE (two subagent reviews, all code read): no malicious code. Security decisions preserved in docs/superpowers/specs/2026-09-18-tidal-archive-design.md:
1. TLS restored in vendored code (see VENDOR.md hardening record).
2. Unprivileged uid 1000 container; post-login chmod 700 config/ && 600 loginstorage.bin (plaintext pickle of access+refresh tokens = account-equivalent; pickle.load = RCE if writable by others).
3. Login via TV/device-code flow ONLY (never Mobile option — takes password in-terminal).
4. Egress = Tidal domains only, by construction (no pip/git/network in image; updates via reviewed vendor merges on the Mac — docs/review-workflow.md).
5. Only vendored modules whose source was read; re-check diffs on upstream pull.
6. Leak response in RUNBOOK §8: change Tidal password + sign out all devices (invalidates refresh tokens).
License reality: NO license file in either repo -> local fork only, never publish.
Structural risk (accepted): Tidal Widevine rollout may close the old API any time — archive essentials early. ToS risk = account action.

## Tool landscape decisions (do not re-litigate)
- Piped: mainline dead (SABR); Invidious oscillates; not our path.
- Tubio+ (Stremio YouTube addon): reviewed 3 subagent lenses — no malware but broken headline features (SponsorBlock dead code, no seeking >360p, no auth), deprecated by author; rejected as untrusted.
- Brave on iOS: background-play breakage (Jan 2026) is YouTube-vs-browsers cat-and-mouse; fix = Settings > Shields & Privacy > Content Filtering > Update Lists + Settings > Media > Enable Background Audio; custom filters youtube.com##+js(brave-video-bg-play) / brave-disable-page-view... (see conversation if needed). Sideloaded Brave pointless.
- Sideload path (unused but valid): uYouPlus/YTLitePlus via AltStore/SideStore; YTLite GitHub Actions build takes user's decrypted IPA URL.
- FreeTube iOS exists (yt-dlp in-process, native SwiftUI); newpipe-ios (BenjaminH7) exists as reference for custom clients.
- Piped/Invidious self-hosting: fine for IP bans at personal scale, but SABR broke Piped mainline — not reliable.

## Session conventions (how work was done)
- Superpowers skills used: brainstorming -> spec (docs/superpowers/specs/... in git history) -> writing-plans -> subagent-driven-development (implementer + task reviewer per task, final whole-branch review, fix loop) -> finishing-a-development-branch.
- Ledger of rulings/parked findings lived in .superpowers/sdd/<plan>/progress.md (deleted after completion; rulings are summarized in PR #1 description and this file).
- Reviews: dispatch parallel subagents per lens (senior engineer / security engineer / architecture), give them cloned repo paths, require severity + file:line + verdict.
- Never force-push without explicit user request. Only commit when asked or when delivering explicitly requested changes.

## Temp artifacts (reclone if needed)
- /var/folders/kq/dcbcq8gj62v_d5htm0jgxbhm0000gn/T/opencode/orpheusdl (tidal module clone)
- /var/folders/kq/dcbcq8gj62v_d5htm0jgxbhm0000gn/T/opencode/orpheusdl-framework (shallow clone — reclone with full history if provenance matters)
- /var/folders/kq/dcbcq8gj62v_d5htm0jgxbhm0000gn/T/opencode/tubioplus (Tubio+ clone, reviewed)

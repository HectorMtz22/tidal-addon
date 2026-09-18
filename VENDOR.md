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

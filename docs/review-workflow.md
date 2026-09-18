# Upstream diff review workflow (mandatory before any vendor update)

The container runs only code that was read. Every upstream update goes through
this gate on the Mac, before the image is rebuilt.

Vendored code is committed as plain files (no nested git repos), so "fetch and
diff" works against a fresh upstream clone, not in-place.

## 1. Fresh-clone upstream and diff against the vendored tree

```sh
git clone https://github.com/yarrm80s/orpheusdl /tmp/upstream-framework   # (or Dniel97/orpheusdl-tidal)
# diff what's new since our pinned commit vs what we carry:
git -C /tmp/upstream-framework log --oneline a45ff47913508d4c09971bdb847d5845984f1e64..origin/master   # what's new?
diff -ru --exclude='__pycache__' --exclude='.git' vendor/orpheusdl-framework /tmp/upstream-framework > /tmp/vendor-diff.diff
```

The interesting review surface is (a) the upstream log range since our pin and
(b) the vendor-vs-upstream diff, which also shows our TLS hardening layer
(known and intentional: CURL_CA_BUNDLE / disable_warnings / verify=False lines
should appear as removed-by-us; anything else needs explanation).

## 2. Review checklist (all must be answered)

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

## 3. Apply or reject

If and only if every box is ticked: copy the changed files into the vendored
tree (preserving our TLS hardening), and re-verify:

```sh
! grep -rn "verify=False\|CURL_CA_BUNDLE\|disable_warnings" vendor --include='*.py'
./tests/hardening.sh          # check 1 must pass; full run needs the built image
```

If any box is unticked: reject, stay on the pinned snapshot, and note it in
VENDOR.md. Never apply unreviewed upstream changes.

## 4. Rebuild

Regenerate `docker/requirements.lock` (requirements.txt may have changed),
rebuild the image, run `tests/hardening.sh` (all five checks must pass), then
update VENDOR.md with the new pinned commit hash + review date.

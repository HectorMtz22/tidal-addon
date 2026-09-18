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

#!/usr/bin/env bash
# Hardening assertions for the orpheusdl:hardened image.
# Exit 0 = all pass. Any FAIL exits 1.
set -u
cd "$(dirname "$0")/.."

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: $1"; }

# 1. No TLS-stripping code anywhere in vendored sources
[ -d vendor/orpheusdl-framework/orpheus ] || fail "vendor/orpheusdl-framework/orpheus missing — vendored tree absent or renamed"
[ -d vendor/orpheusdl-tidal ] || fail "vendor/orpheusdl-tidal missing — vendored tree absent or renamed"
grep -rn "CURL_CA_BUNDLE\|disable_warnings\|verify=False" vendor \
  --include='*.py' --exclude-dir=.git --exclude-dir=__pycache__ >/dev/null 2>&1 \
  && fail "insecure TLS code still present in vendored sources"
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

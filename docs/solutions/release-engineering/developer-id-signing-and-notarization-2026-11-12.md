---
title: Developer ID signing + notarization in CI, and the intermediate that made it look broken
date: 2026-11-12
category: release-engineering
module: release-pipeline
problem_type: ci_cd
component: build_pipeline
symptoms:
  - "Keychain Access reports \"Developer ID Application certificate is not trusted\""
  - "security find-identity -v -p codesigning prints 0 valid identities despite the cert being visible"
  - "codesign cannot find a signing identity on a machine that just created one"
  - "Release downloads are blocked by Gatekeeper: \"Apple could not verify Keryx is free of malware\""
root_cause: environment_missing_dependency
resolution_type: ci_config_fix
severity: high
related_components:
  - "release_workflow"
  - "documentation"
tags: [codesign, notarization, developer-id, notarytool, gatekeeper, app-store-connect, keychain, github-actions, macos]
---

# Developer ID signing + notarization in CI

## Problem

Keryx releases were ad-hoc signed (`codesign --sign -`), so every download was
blocked on first launch by Gatekeeper. Issue #1 tracked the fix. Two things
made the fix harder than the checklist suggested: an Apple-side trap that
looks like a bad certificate, and a pipeline design that must not depend on
one machine's credentials.

## Symptoms

- `security find-identity -v -p codesigning` → `0 valid identities found` on
  the very machine where the Developer ID certificate had just been created
- Keychain Access shows the certificate with "Developer ID Application
  certificate is not trusted" (red ✗)
- The certificate itself is perfectly valid — correct subject, correct team,
  valid dates, downloaded from the portal

## Root cause

The **issuing intermediate was missing from the keychain**. The leaf chains to
`CN=Developer ID Certification Authority, OU=G2, O=Apple Inc.` (the "Developer
ID - G2" CA, valid 2021–2031). Fresh macOS installs do not necessarily ship
that intermediate: `SystemRootCertificates.keychain` has `Apple Root CA`,
`Apple Root CA - G2` and `Apple Root CA - G3`, but the Developer ID
intermediate still has to be installed.

No intermediate → chain evaluation fails → Keychain renders the cert
"not trusted" → `find-identity` reports zero valid identities → `codesign`
cannot even look up the identity, so the failure surfaces much later and
looks unrelated.

Diagnose by comparing the leaf's issuer against installed certificates:

```sh
security find-identity -v -p codesigning            # 0 valid identities?
security find-certificate -a -c "Developer ID Application" -p \
  ~/Library/Keychains/login.keychain-db | openssl x509 -noout -subject -issuer
security find-certificate -a -c "Developer ID Certification Authority"   # empty = missing
```

## Solution

Install Apple's intermediate from the CA page, after confirming its subject
matches the leaf's issuer:

```sh
curl -sSLO https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer
openssl x509 -inform DER -in DeveloperIDG2CA.cer -noout -subject -issuer
# subject=CN=Developer ID Certification Authority, OU=G2, O=Apple Inc., C=US  ← matches issuer
security import DeveloperIDG2CA.cer -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign
security find-identity -v -p codesigning   # 1 valid identities found
```

### Pipeline design (`.github/workflows/release.yml`)

- **Signing is opt-in on secrets.** With `DEVELOPER_ID_CERT_P12` unset the job
  still produces the old ad-hoc bundle, so the pipeline never depends on one
  machine's credentials. Partial configuration (cert set, notary credentials
  missing) fails loudly instead of shipping an unsigned artifact.
- **Throwaway keychain per run**, unlocked with a random password, then
  `security set-key-partition-list -S apple-tool:,apple:,codesign:` so
  `codesign` can use the key non-interactively. Prepend it to the user search
  list or `find-identity`/`codesign` will not see it.
- **`codesign --force --options runtime --timestamp`** — hardened runtime is
  required for notarization; the timestamp is required for signatures that
  must outlive the certificate.
- **Identity is discovered, not hardcoded**: `find-identity` + `sed` pulls
  `Developer ID Application: …` out of the keychain, so cert renewals and name
  changes need no workflow edit.
- **notarytool with an App Store Connect API key** (`--key --key-id --issuer`)
  instead of an Apple ID + app-specific password: never expires, not tied to
  a human's 2FA.
- **Staple, then package.** `stapler staple` rewrites the bundle, so the
  distribution zip must be created *after* stapling. Use
  `ditto -c -k --keepParent` rather than `zip -r` — `zip` mangles symlinks and
  resource forks in bundles.
- **Assert Gatekeeper acceptance** instead of trusting the notary status:
  `spctl -a -t exec -vvv Keryx.app` must print `source=Notarized Developer ID`,
  otherwise the job fails.
- **`workflow_dispatch` dry run** that signs, notarizes and verifies but skips
  publishing (`if: github.ref_type == 'tag'`), so credentials can be validated
  without burning a real version number.

### A password-less `.p12` is fine

Keychain Access permits exporting with an empty export password. That imports
cleanly with `security import … -P ""`, so `DEVELOPER_ID_CERT_PASSWORD` is
treated as optional rather than required. Verify locally before touching CI by
importing into a throwaway keychain and checking `find-identity` on it.

## Verification

Local pre-flight (no Apple round trip needed):

```sh
security create-keychain -p verifypass /tmp/kx.keychain-db
security unlock-keychain -p verifypass /tmp/kx.keychain-db
security import developerID.p12 -k /tmp/kx.keychain-db -P "" -T /usr/bin/codesign
security find-identity -v -p codesigning /tmp/kx.keychain-db
security delete-keychain /tmp/kx.keychain-db
```

End-to-end evidence from the first successful CI dry run:

- `CodeDirectory … flags=0x10000(runtime)` with `Authority=` chain ending at
  `Apple Root CA`
- `notarytool submit … status: Accepted`
- `The staple and validate action worked!`
- `spctl`: `Keryx.app: accepted` / `source=Notarized Developer ID`

## Notes / sharp edges

- `security`, `base64` and `bash` on macOS runners are BSD/3.2 — use
  `openssl base64 -d -A` rather than `base64 --decode`/`-d`, and avoid bash-4
  features (namerefs, `${var,,}`, `${sha::7}`-style slicing is fine).
- Developer ID Application certificates cap at 5 per team and last ~13 months;
  a calendar reminder matters because expiry breaks the release job silently
  at the signing step.
- The `.p8` App Store Connect key is downloadable exactly once. Losing it means
  revoking the key, not re-downloading it.
- Team keys require Account Holder/Admin on the Apple Developer account.

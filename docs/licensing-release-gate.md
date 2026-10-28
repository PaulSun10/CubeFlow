# Licensing Migration and Public-Push Gate

Review date: 2026-10-23. Starting feature tip:
`9b751f67feecb92237b94c13fc4a9044290f148c`. Remote `origin/main`, checked with
`git ls-remote`, remains `c551de97919551e2ef1051a2ba45adbef16f1836`.
The ten feature commits are retained in order, without rewriting history.

## Decision: NOT PUSHED

First-party GPL-3.0-only migration is complete in source/notices. Public
distribution is **not cleared**: gates B and C below have concrete outstanding
materials. These are not speculative concerns or optional documentation polish.
No public push, tag, release, signing, archive or deployment is performed.

| Gate | Finding | Required action |
| --- | --- | --- |
| A: credential exposure | `WCAAuthManager.swift` still contains a literal OAuth client secret. Compared without printing the value: it is identical at `origin/main` and the feature tip. Its original exposure predates the ten commits; they did not introduce it. Active/revoked status is not established. | Obtain confirmation from the credential owner that the exposed value is revoked or otherwise safe for publication; remediate an active secret in a separately authorized task. Do not infer inactivity, test the credential, rotate it, or rewrite history in this migration. |
| B: native Corresponding Source | TNoodle, matching-release Graal, Gluon Substrate native-support/build source and GluonFX source archives are now included, with checksums and a static verifier. G1-G4 remain: actual static JDK and cross-CLIB source/patch mapping, sufficient original shared-library recipe, and complete incorporated-dependency delivery. Verdict remains INCOMPLETE, not a cleared gate. | Complete the specific builder/supplier requests in [TNOODLE-SOURCE.md](TNOODLE-SOURCE.md) and its source manifest. Do not substitute default candidate SDK binaries or an integrity pass for corresponding source. No native rebuild is performed or implied. |
| C: bundled resource rights | Actual inherited SpeedCubeDB-attributed data, thousands of algorithm PNGs, and the `adj_parity` seed lack a verified per-family permission record. DrawScramble's intermediate origin and local font derivation also remain unresolved. | Recover permissions/licenses and source-to-artifact records for the included materials. If replacement/removal is necessary, request separate authorization; do not relabel unknown resources under GPL. |
| D: consistent notices | Root official GPL text; explicit first-party GPL-3.0-only grant; historical MIT grant preserved; existing third-party texts unchanged; About corrected; source limitations stated. | Passed for this migration's declarations, without asserting that unresolved components are cleared. |
| E: new sensitive material | Migration adds notices/docs and a verified upstream source ZIP; only license/source-attribution literals change in app source. No credentials, private keys, provisioning profiles or signed products added. | Passed focused migration review; this is not a claim of an exhaustive historical secret audit. Existing exposed OAuth material is tracked separately under A. |

Because B and C independently fail, no conclusion about credential validity is
needed to justify withholding this push. Never report the credential as confirmed
active or revoked without evidence. Excluding its unchanged file from a new commit
would not remove earlier exposure, and has not been attempted.

## Migration Contents

- Root LICENSE: complete unmodified official
  [GNU GPL version 3 text](https://www.gnu.org/licenses/gpl-3.0.txt), downloaded
  2026-10-23; SHA-256
  `3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986`.
- README and NOTICE: project owner copyright, GPL-3.0-only scope, third-party
  exclusions, historical MIT grants and links to the inventories.
- `LICENSES/CubeFlow-MIT-historical.txt`: original root MIT notice preserved
  verbatim; not a new dual-license offer for post-migration changes.
- About: CubeFlow label GPL-3.0-only; TNoodle label GPLv3 and actual native-fork
  attribution/source; existing min2phaseCXX presentation unchanged.
- Central third-party inventory and content-audit cross-reference; MIT Cubing
  Icons and GPL csTimer texts added without changing their source/assets.
- Pinned TNoodle project source ZIP plus checksum file; source-delivery inventory
  differentiates provided Java code from missing linked-runtime/build materials.

## OAuth Retirement and Publication Update (2026-10-28)

The owner confirmed permanent destruction of the exposed **old native OAuth application**.
The separate production Broker application remains active and was not changed. The obsolete
credential constants, native grant/refresh implementation and fallback are removed from the
current app source. Historical copies remain revoked; no history rewriting or credential
rotation is performed. Gate A's unknown-active-status finding above is historical, not the
current credential status. This does not clear unrelated native-source, privacy or asset-rights
uncertainties. The owner now authorizes normal commits and fast-forward publication of the
completed work; older no-push statements below describe their original investigation scope.

## Focused TNoodle Recovery Follow-Up

The uncommitted source-delivery follow-up adds three original pinned source
archives (about 35 MB total, no compiler installation), a machine-readable
manifest and read-only static verifier. It recovers native support and build
definitions previously represented only by links/research source JARs. The
Graal export metadata names three native helper/JVM libraries; Gluon Substrate's
native iOS dummy support is also identified in the binary. These observations
improve the mapping but do not authenticate unknown static-JDK/platform patches.

The correct official default SDK and cross-CLIB packages were inspected only as
candidate research inputs. They contain binaries, not the missing source, and
are not part of the delivery set. G1-G4 remain concrete source-delivery gaps.
All other publication-gate findings remain unchanged; this follow-up does not
re-audit historical assets, OAuth, Apple distribution or privacy matters.

No commit or push is authorized for this follow-up. The existing eleven local
commits, including the licensing migration, are preserved. Integrity validation
does not update the gate to COMPLETE.

## Validation and Scope

Focused static checks cover official LICENSE byte equality, historical MIT and
existing notice preservation, upstream source ZIP identity/CRC/checksum, local
notice links and source paths, About literal-only diff, unchanged native input,
ignored `build/`, and staged diff whitespace/sensitive-file review. No application
behavior, OAuth, signing, native algorithms, resource content, or deployment
configuration changes are part of the migration.

No Xcode build or test suite is required for documentation and these string/URL
literal substitutions; no build, simulator/device interaction or signing is run.
Static checks are not a full legal opinion, complete SBOM, credential-revocation
proof or physical acceptance result. Broader release/privacy/runtime work is not
reopened here.

## Minimum Follow-Up

1. Complete TNoodle's exact linked-runtime/source and required build-material
   inventory, then provide a maintained corresponding-source delivery set.
2. Obtain the actual inherited resource permissions and font/DrawScramble
   derivation records; escalate any necessary replacement rather than silently
   changing resources or making an unsupported license claim.
3. Confirm the pre-existing exposed credential's disposition with its owner.
4. Re-evaluate A-E and, only if passed, perform a normal non-force push of the
   preserved feature series plus licensing commit. This review does not approve
   a later push while those conditions remain unresolved.

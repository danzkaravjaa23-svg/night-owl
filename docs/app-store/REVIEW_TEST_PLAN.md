# Night Owl UB — native acceptance and reviewer test plan

Prepared 2026-11-03, Asia/Ulaanbaatar. **Not executed on the final signed native build. Not an App Store readiness certificate.** Run against the exact candidate archive and record every applicable result. Web/widget captures, isolated HTTP/crypto tests and synthetic SQL fixtures do not replace device or hosted staging verification. Final source/build identifiers and automated evidence belong in [release readiness](../RELEASE_READINESS.md) and [BUILD_VERIFICATION.json](../BUILD_VERIFICATION.json).

## Current entry conditions

Current client `23a7258` passes 886 Flutter tests, static analysis, unsigned iPhone/simulator compile and iPhone/iPad startup (CI41616509440 attempt2). Current actual isolated Auth/Storage/Edge passes 10 component groups ([CI 41616849314](https://github.com/danzkaravjaa23-svg/night-owl/actions/runs/41616849314)). The new native startup result is recorded in [latest native evidence](evidence/native-build-latest.json); a previous `7cbbeb3` startup pass is historical and must not substitute for the current candidate. Neither result executes the signed-device acceptance cases below or certifies production schema parity.

- Historical public read-only preflight at `2026-11-03T06:51:19Z`: Apple provider disabled; Google and email enabled; account-deletion function returned `404 / NOT_FOUND`; support/privacy were actual static HTML. Evidence: `build/audit/2026-11-03/app-store-prep/public-preflight.json`. These observations do not certify a later deployment.
- Current inactive Edge deployment (2026-11-03T10:03Z): exact source ZIP matches; `ACCOUNT_DELETION_ENABLED=false`, gateway JWT validation ON; missing Auth401 and public anon503/deletion_unavailable. No account deleted. Free-project automatic backup unavailable; manual database/Storage recovery not yet verified. [Evidence](evidence/hosted-edge-disabled.json).
- Source implements 008 durable account erasure and 009 manual UGC review/reporting plus client changes. They must be rolled out together and accepted on hosted staging before production enablement. Earlier installed admin/storage protections are not evidence that 008/009 or an enabled deletion service are live.
- Settings and unfinished setup expose **Бүртгэл устгах**. A validated saved local receipt reveals **Өмнөх устгалын төлөвийг шалгах** on the signed-out landing screen; `/settings/delete-account` is public for status recovery. The entry points do not prove hosted erasure works.
- The manual moderation queue needs a responsible operator, response coverage, escalation and appeals. Code does not supply those owner decisions. No signed archive, actual Apple login/revoke, device screenshots or completed questionnaire is implied by this plan.

## Candidate and owner fields

| Field | Required value before testing/submission |
|---|---|
| Candidate Git commit / archive checksum | Pending |
| Marketing version / build number | Pending; confirm unused build number in App Store Connect |
| Bundle ID / Team ID / provisioning profile | Pending signed-archive verification; intended bundle ID `com.nightowl.ub.nightOwlUb` |
| Xcode / SDK / iOS / device model | Record exact final build/device evidence; unsigned CI compile is separate |
| Staging backend and disposable accounts A/B/moderator | Pending; never use existing production users for destructive tests |
| Review account with representative safe content | Pending owner-controlled non-admin account; credentials only in App Store Connect Review Information |
| Reviewer contact name / phone / email | Pending owner confirmation; public support currently `osokhe@gmail.com` |
| Moderator / coverage / response target / escalation / appeal process | Pending owner decision and operational test |
| Data retention, erasure recovery and journal-pruning operation | Pending owner confirmation against actual hosted behavior |
| Countries / age rating / privacy answers / export compliance | Pending owner verification; no automatic answers supplied |

For each case record tester, UTC time, device/iOS, candidate build, backend environment, account aliases, expected/actual result, evidence path and PASS / FAIL / BLOCKED. Do not record passwords, JWTs, Apple codes/tokens, receipt capabilities, signing keys, unrelated private messages or real abusive content.

## Native acceptance cases

| ID | Steps | Acceptance condition |
|---|---|---|
| N01 — install and guest | Fresh install; deny location; browse Explore, venue details and policy/support links; repeat offline and after resume. | No crash, blank view or indefinite loading; map browsing does not require location or silently create an account. Errors are actionable. |
| N02 — email account | Create disposable A; verify email if required; complete setup; sign out/in; use valid, cancelled and expired password-recovery callbacks. | Correct account/session; consent is personally supplied; recovery fails safely when invalid; drafts/cache do not cross accounts. |
| N03 — Google account | Start/cancel/finish login; native callback; sign out; repeat with slow network and after reinstall. | Intended session returns; no false success, raw provider error or stuck loading. |
| N04 — Apple account | After provider/capability/signing setup, test first/returning authorization, Hide My Email, cancellation, callback failure and account switching on a signed iPhone. | Real equivalent login works; nonce/audience checks pass; initial name does not overwrite an existing name; cancellation does not create a session. A provider-disabled message is not a passing login test. |
| N05 — profile and permissions | Each bundled avatar; own photo/cover; edit public fields; moderator approve/reject; deny/limited/allow Photos and camera where requested. | Author sees pending/rejected state; an existing approved profile remains public while candidate edits wait. Only approved media/identity becomes public. Permission failures recover without unrelated access demands. |
| N06 — post and canonical Reel | Photo/carousel, one-video Reel, story; add/change/remove UUID and OSM venues; optional no-venue; duplicate taps; lost response/retry; switch account during picker/upload. | One immutable original ID/caption/media/venue is recovered without another upload after an uncertain insert. No publish under the new account. Reel rejects images, uses single-video picker and returns to Reels. Draft/cancel and pending-review feedback are honest. |
| N07 — weekly map activity | In staging approve a tagged post/Reel; compare story/post breakdown; test before/at 168 elapsed hours; edit caption/tag; delete/remove tag; approve a post after its window; pause/resume. | Only approved, viewer-readable content counts. Original publication clock never restarts on edit/approval/retry. Post/tag persist after activity expires; stories use the current Ulaanbaatar day and expiry. Unknown network state is not zero or a crowd/opening claim. |
| N08 — private/follow/block | A private; B requests follow; accept/revoke; block both directions; repeat Feed/profile/story/signed media/map/active cluster sheet; switch accounts with requests in flight. | Forbidden content and counts clear; old responses cannot restore them; interactions obey server rules. No promise to erase copies already downloaded. |
| N09 — private messaging | Contact policies and request acceptance/rejection; one-to-one/group send/retry; background/resume; account switch; report one received bubble by long press and VoiceOver action. | Rules enforced server-side; draft/cache stay scoped. Report presents selected-message consent, transmits target ID/reason, and gives moderator only the selected snapshot, never blanket thread/inbox access. DM/group messages are not placed in public prepublication review. |
| N10 — report coverage | Use every path in the coverage checklist below; submit/retry/duplicate; cancel; switch account while sheet or RPC is pending; attempt an invisible target directly. | Reachable exact-target reporting, validated reason/details and safe retry; draft cannot be sent by a new account. Invisible targets rejected by server; no sensitive raw errors or unrelated context leaks. |
| N11 — moderation workflow | Authorized moderator opens pending queue and reports; reviews text/photo/video/audio context where present; approve/reject with reason; stale-version retry; revoked/non-admin access; private media expiry. | Only allowed admin roles act; original submitted version is checked; stale decision fails; audit/report resolution consistent. Published views and map refresh. Pending private media remains inaccessible to other members; moderator gets only authorized preview. Operator demonstrates coverage/escalation/appeals. |
| N12 — prepublication manual review | New/edit post/Reel, story, comment, event, venue review, profile candidate, note, public collection and owner venue fields; test normal composer and direct supported writes. Use safe synthetic policy fixtures only. | Server pending/rejected/approved rules hold on every surface. Author can read status; another user sees only approved content/baseline. Rejection and resubmission are honest; service failure cannot publish unchecked content. Do not label this AI moderation or rely on size validation/reporting alone. |
| N13 — erasure and recovery | Execute the detailed disposable-account cases below after hosted enable gates pass. | Only server-confirmed completion is success. Storage/Auth/data/revocation checks pass; partial progress is reported honestly; no foreign/new session is logged out. |
| N14 — analytics and disclosures | Fresh install/account; inspect default-off analytics; opt in/out with failed writes; switch account; inspect actual media/device requests; compare policy and App Privacy inventory. | Consent optional/server-enforced; linked account/content/message/location/SDK data declared accurately. Do not claim No Data Collected, all metadata removed, or provider-wide No Tracking without evidence. |
| N15 — accessibility/layout | Small/large iPhone, supported iPad, day/night/system, large text, VoiceOver, Reduce Motion, keyboard/safe areas on auth/composer/map/reports/erasure. | Reachable labelled controls and final actions; no overflow; understandable loading/error/confirmation; motion respects accessibility and lifecycle. |
| N16 — final archive and listing | Verify signed archive entitlements/bundle/version/privacy manifests, distribution validation, actual native screenshots, privacy/age/export forms, reviewer access and policy URLs. | Exact submitted candidate is tested; no browser captures represented as native screenshots; owner fields complete; no secrets in artifacts. Internal TestFlight is not public App Store approval. |

### UGC/report coverage checklist

- Feed post and Reel: action menu → report; account options → block/report user.
- Story: header report action; return resumes appropriately after cancel/submission. Pending author story is labelled; another viewer cannot load it before approval.
- Comment: report that comment from its displayed row. The parent post must also be visible.
- Venue and venue review: report venue details or the exact review from preview/full review views. Existing catalog facts and newly authored venue fields must respect their distinct source/review rules.
- Event: event detail → **Эвентийн агуулгыг мэдээлэх**; check organizer pending status and admin-only featured selection separately.
- Note: note detail → **Note-г мэдээлэх**, using actual note UUID rather than its author's user ID.
- Public collection: collection detail report action using collection UUID; private visibility still applies.
- DM/group: received bubble long press or accessible **Мессежийг мэдээлэх** action. Verify selected-message-only snapshot, unrelated messages unavailable to moderator and non-members denied.
- Profile: user options report/block; public profile edits use private review candidate with approved baseline preserved. Report, block and approval are separate actions.

Every applicable item requires device and hosted enforcement evidence; a user-level report does not substitute for missing exact-content paths. Own-content edit/delete controls may replace report actions; test reports using the other disposable account.

### N13 disposable erasure cases

1. Settings and unfinished setup entry; acknowledgement/final confirmation cancel; unavailable handler; stale/other-account token; duplicate request. Preparation alone must not revoke Apple or erase data.
2. Apple-linked iPhone: server five-minute challenge → SHA-256 nonce → fresh native identity/code without signing into or replacing Supabase auth. Wrong Apple ID, cancel, expired nonce/code, bad audience/config/revoke failure must not claim completion.
3. Apple-linked web: official SDK loaded only on requested action, fresh explicit popup click after preparation, configured Services ID/exact HTTPS redirect. Test popup cancellation/blocking and correct/incorrect identity. Android Apple reauthorization is intentionally unavailable; iPhone/web guidance must be clear.
4. Fail Storage removal/list/verification, DB cleanup or Auth deletion; interrupted app/process; network response lost before/after completion; two workers and expired lease; upload concurrent with claim. Account writes freeze during a partial job; deliberate retry checks status first and resumes verified checkpoints. A later Apple sign-in/identity change must invalidate an older revoke checkpoint.
5. Restart after Auth is already gone. Secure storage holds only owner/opaque receipt/start time, never Apple proof. Signed-out landing reveals **Өмнөх устгалын төлөвийг шалгах**, then status-only recovery; it must not automatically restart erasure. Another currently signed-in account cannot use/clear that owner's receipt or be signed out by a late result.
6. Verify actual Storage/FK/Auth removal, shared content belonging to others preserved, and report snapshot redaction/retained security audit consistent with policy. Test receipt-storage failure before destructive request; malformed/future/expired records ignored; confirmed completion clears only matching saved receipt.
7. Record retention and operational recovery: client capability expires 30 days from preparation; completed server journal 30 days from completion, with operator pruning configured. Failed jobs need authenticated recovery/operator attention and are not automatically unfrozen. Lost capability with no Auth session requires the documented support path; do not promise indefinite local recovery.

## Reviewer navigation draft

Use these notes only after the same paths pass on the submitted binary:

1. Guest **Explore** opens the map and venue details; device location is optional.
2. Use owner-supplied non-admin review access, seeded with licensed safe content and completed setup. Store credentials only in Connect. Use a separate disposable account for destructive erasure and provide it privately if requested.
3. Create → post/story or **Богино видео**. Location tags are optional. New public content is submitted for manual review; approval may require the designated operator. Explain any waiting period with working representative approved content available.
4. Report post/Reel via **⋯**; story/header, comment/review/venue/event/note/collection offer exact-content reporting. Received DM/group bubbles support long press and accessible report action; only the selected message is shared. User options include blocking.
5. Profile → Settings → **Нууцлал, хүсэлтүүд** manages private/follow/contact controls. Profile edits can remain pending while approved identity stays public; verify exact labels before copying.
6. Profile → Settings → **Бүртгэл устгах**, also unfinished setup; Apple accounts require fresh authorization. After interrupted erasure, signed-out recovery appears only when this device has a valid saved receipt. Do not describe hosted deletion as working until N13 passes.
7. Recheck [Privacy](https://nightowl-ub.netlify.app/privacy.html), [Support](https://nightowl-ub.netlify.app/support.html), [Terms](https://nightowl-ub.netlify.app/terms.html). The release is free; no payment, calls, streaming, delivered remote push, guaranteed opening or live attendance claim.

## Submission gates and references

Keep submission blocked until working erasure, eligible login, hosted UGC safeguards/operations, device evidence, signed validation, privacy/age/export declarations, review access and owner fields are complete. Apple/service enablement, real account erasure, agreements, purchases and App Store submission are separate actions, not outcomes of this checklist.

- [Apple account deletion](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion): in-app initiation/completion and Apple revocation.
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/): UGC §1.2, login §4.8, privacy §5.1 and review access/completeness; references checked 2026-11-03.
- [App Privacy details](https://developer.apple.com/app-store/app-privacy-details/): actual collection and third-party practices.
- [Submission pack](../APP_STORE_SUBMISSION.md), [Apple setup](../APPLE_SIGN_IN_SETUP.md), [deletion protocol](../../supabase/functions/delete-account/README.md).

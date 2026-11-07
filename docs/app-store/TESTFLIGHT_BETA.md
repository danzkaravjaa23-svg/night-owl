# Night Owl UB — TestFlight beta preparation

Updated 2026-11-06, Asia/Ulaanbaatar. This is a local preparation record; external review and invitations have not been completed.

## Current distribution

- **Staging 1.0.0 (3)** contains the configured-provider login UI fix from `d56e6efcf10dd98d567a388e05aa4c52a3393a65`. Archive/export/signature checks and independent review passed; the fixed uploader has 25 passing offline tests. IPA **33,646,028 bytes**, SHA256 `0cccb95a1d11c8d9090ad9a5f35d1351eeeaf74d3318913570b0a9bfd33526e3`. Apple processing completed **COMPLETE / VALID / APP_STORE_ELIGIBLE**, uploader exit 0. Build/upload ID `842f61af-c585-4c7a-a672-6c5f7543d4ce`; file ID `622bcaa1-bac2-4c46-9c17-6ad650bfffad`. The encryption questionnaire was separately saved (standard outside Apple OS; France No), yielding **Ready to Submit**. Build 3 is attached to **Night Owl Internal**, with one tester, and its What to Test notes show **Saved**. Screenshot: `build/audit/2026-11-05/testflight-build-3-internal.png`. Device installation remains unverified; no external-review submission has been made.
- Staging **1.0.0 (1)** is uploaded, **VALID / INTERNAL_ONLY**; the latest TestFlight UI shows **Testing** with one invitation. Its saved encryption answers are standard encryption outside Apple OS and France **No**. Existing signed artifacts and receipts remain unchanged. The Testing label does not establish device installation or acceptance.
- The owner internal group `a67e050b-665b-49e9-9e3c-f58cfede8de1` now contains **one tester and builds 1 and 3**. The owner's invitation is **Invited**, as verified in the UI. This does not establish acceptance of the invitation or installation on a device. Screenshot: `build/audit/2026-11-05/testflight-owner-invitation.png`.
- **Staging 1.0.0 (2) uploaded successfully, uploader exit 0; Apple reports COMPLETE / VALID / APP_STORE_ELIGIBLE.** Source `67e8b1c79764285df6cd21981e066b62790eac70`; IPA **33,639,969 bytes**, SHA256 `6a226eed784a60a4136405df6598106e3545e4c0b315acb64905ce9176b7cfda`. It uses normal export without the internal-only flag. Build/upload ID `2bf25fda-b90d-44db-b499-d15b84cd4c27`; file ID `e3ba91c3-2330-4260-8db6-cc6a5c514881`. Local signature/identity checks and remote identity/audience checks passed. Build 1 remains unchanged and cannot be converted into an external-testing build.
- After upload, the encryption questionnaire was saved separately as **standard encryption outside Apple OS; France No**. Build 2 now shows **Ready to Submit** in TestFlight. This is not beta review approval or external distribution. Screenshot: `build/audit/2026-11-05/testflight-external-build-ready.png`. The upload-time encryption flag and immutable signed artifact remain unchanged.
- External group **Night Owl Early Access**, `7222927f-9055-4e7d-8bd9-e6f7e380caad`, exists with **zero testers and zero builds**. Screenshot: `build/audit/2026-11-05/testflight-external-group.png`. A public invitation link has now been created with the owner-confirmed limit of 50: (URL withheld from this public repository; see TestFlight > External Testing > Night Owl Early Access in App Store Connect). No external review has been submitted and no approved build is in the group, so external installation is not ready. Screenshot: `build/audit/2026-11-05/testflight-public-link-50.png`.
- Apple requires an internal group before an external group. The first external build needs TestFlight App Review approval before external testers can install through email invitations or a public link. Internal testers are App Store Connect users with account access; they are not an alternative role for ordinary public beta testers.

## Current functional gaps

A read-only `GET /auth/v1/settings` against the exact candidate's staging backend returned HTTP **200** at **2026-11-05T16:15:30.507121Z**. The enabled provider list was **`email` only**. No credentials or other settings were printed or saved. Provider flags alone do not verify signup, email delivery, password recovery or device login.

- Apple and Google login are currently unavailable in staging. Build 3 now fetches public provider availability and hides unavailable login options; email remains available, with an accessible retry for provider-fetch errors. The fix passed 78 focused tests and scoped static analysis. Builds 1 and 2 still expose the older login options. This client fix does not enable providers or establish email delivery/device acceptance.
- The Sign in with Apple key `KW5USR3XYB` was created, but its private handoff remains unresolved; the latest checks did not find the exact file in Desktop, Downloads or the approved private folder. Do not search unrelated files or create another key merely to complete this document. The upload API key is a separate credential and cannot replace it.
- Public email delivery/recovery and signed iPhone/iPad acceptance remain unverified. Existing synthetic staging API successes do not establish those device paths.
- Apple login/revocation, interrupted account-deletion recovery, hosted failure/concurrency/shared-content cases and operational moderation/retention acceptance remain open. See [the existing test plan](REVIEW_TEST_PLAN.md) and [owner steps](OWNER_NEXT_STEPS.md).

## Beta information prepared locally

Draft copy is in [metadata/testflight/en-US](metadata/testflight/en-US). It describes the staging environment and current limitations honestly. It has not been saved to App Store Connect. Owner confirmed public-link invitations limited to 50 people and supplied review contact name/email/telephone. These contact values are prepared in the browser but not yet saved; telephone is intentionally excluded from repository records. Moderator coverage is still unconfirmed.

- Beta description and What to Test can be reviewed and entered as draft text now.
- Feedback email uses the existing public support address, `osokhe@gmail.com`; this does not establish the review contact's name or telephone number, or a moderation response commitment.
- Privacy URL uses the existing published policy. The saved App Privacy draft and final owner publication review are separate from these beta text files.
- A persistent non-admin staging review account now passes password-login and privilege checks. Its fictional profile name/valid username were corrected; first-login onboarding and personal 18+/rules confirmation remain. Owner permission to put these generated credentials in Apple review fields is pending. Credentials stay in a Git-external 0700/0600 private file, never these drafts.
- Owner-confirmed review contact details are now available. A responsible moderator and response coverage remain unconfirmed.

## Next actions

1. Resolve the exposed login flows, public email access and signed-device smoke tests. Keep the reviewed staging backend available throughout review/testing; production rollout is a separate task.
2. Complete beta contact/demo-account fields and reviewer notes. Build 3's export-compliance questionnaire is saved. Add build 3 to the existing external group; this association has not been made yet.
3. Submit the first external build to TestFlight App Review when functional and metadata gaps are closed. The public link and 50-person limit are configured; after approval, verify that its approved build can actually be installed before sharing it as ready. No external emails were sent.

App Store production release, final Store screenshots and production backend rollout are separate from beta distribution. Beta apps still need functioning review access, accurate privacy information and compliance with the App Review Guidelines.

[Sanitized beta preparation evidence](evidence/testflight-beta-preparation.json).

Sources: [Apple external testing](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/), [beta test information](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information/), [internal testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/), [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

Current Apple login follow-up: the previous Sign in with Apple private file was not found in the scoped locations. A replacement SIWA-only key form is prepared, but automatic approval review blocked Configure because the previous permission covered only the original key. No replacement key was created; explicit owner confirmation is pending.

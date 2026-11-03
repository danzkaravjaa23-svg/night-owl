# App Store metadata drafts

Prepared 2026-11-03. These are reviewable first-submission drafts, not an uploaded listing or evidence that the iOS app is ready to submit. Copy only the contents of an individual `.txt` field after completing the current submission gates. This README is not store copy.

`en-US` is a provisional listing locale. The app's main interface is Mongolian; the English description states this explicitly. The owner must confirm the primary language, app-name availability and final wording in App Store Connect. No English app localization, native-device test, or signed build is implied by these files.

## Fields and limits

The values below exclude each file's final newline. All fields are UTF-8 plain text; no HTML or Markdown is needed in the copied fields. The short fields are ASCII, so character and UTF-8 byte counts match.

| File in `en-US/` | Draft length | Apple limit |
|---|---:|---|
| `name.txt` | 12 | 30 characters |
| `subtitle.txt` | 27 | 30 characters |
| `promotional_text.txt` | 151 | 170 characters |
| `keywords.txt` | 88 | 100 UTF-8 bytes |
| `description.txt` | 1755 | 4000 characters |
| `review_notes.txt` | 1859 | 4000 UTF-8 bytes |

Keywords are separated by commas without spaces, contain no duplicate terms or app-name words, and each term has more than two characters. `UB` is intentionally omitted from keywords.

Limits were checked against Apple's [App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information) and [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information) on 2026-11-03. Name and subtitle allow 30 characters; promotional text allows 170, description 4,000, keywords 100 UTF-8 bytes and review notes 4,000 UTF-8 bytes. Recheck the actual fields before copying. A first version has no What's New field, so no update-history text is supplied.

## Before using these drafts

The description reflects current source capabilities: optional canonical venue tags, today's active stories in Ulaanbaatar time, a rolling 168-hour post-activity window, 3D map emotions, profiles, follows, messaging, reports, blocks and appearance choices. It does not claim live crowd measurements, guaranteed opening status, universally verified businesses, calls, streaming, delivered push notifications or native validation. The app remains free, and payments are deferred.

`review_notes.txt` assumes a valid review account will be entered separately in App Store Connect's private Sign-in Information fields. No account, password or review contact is included here. Create and verify suitable review access and the walkthrough on the actual submission build before using the notes; keep credentials out of Git and chat. The [review test plan](../REVIEW_TEST_PLAN.md) and current submission report describe remaining verification.

Confirm the privacy/support URLs, moderation and account-deletion operation, privacy answers, age-rating questionnaire, Apple sign-in, signing and native-device checks in the [submission pack](../../APP_STORE_SUBMISSION.md) and [release readiness report](../../RELEASE_READINESS.md). The app's 18+ community acknowledgment does not set the App Store age rating. Screenshots must come from the final eligible native build; browser/widget captures are development evidence only. No store record, upload, review submission, publication, purchase or agreement acceptance was performed for these drafts.

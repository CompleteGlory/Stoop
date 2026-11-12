# App Store Connect answers

What to enter in App Store Connect so it matches the app. If the app's behaviour changes, change this and the privacy manifest (`PlaceRating/PrivacyInfo.xcprivacy`) with it.

## URLs and contact

| Field | Value |
| --- | --- |
| Privacy Policy URL | `https://place-rating-api-production.up.railway.app/privacy` |
| Terms of Use (add to the app description, or use the standard EULA) | `https://place-rating-api-production.up.railway.app/terms` |
| Support URL | the same `/terms` page lists the contact; or a GitHub repository link |
| Support / review contact email | `magddevf@gmail.com` |

Both pages are served by the API (English and Arabic) and the app links to them from the sign-in screen, the create-account screen and the profile sheet.

## App Privacy ("nutrition label")

Tracking: **No**. Nothing is used to track people across other apps or websites, and there are no advertising or analytics SDKs.

Data collected, all **linked to the user**, purpose **App Functionality** only:

| Category | What it is |
| --- | --- |
| Contact Info: Email Address | Only if the person signs up with email (or Apple/Google share it) |
| Contact Info: Name | Display name, and the name Apple shares if the person allows it |
| Identifiers: User ID | The account id and the Apple/Google sign-in identifier |
| Location: Precise Location | Sent to friends while the app is open; held in server memory for 60 s, never stored |
| User Content: Photos or Videos | Place and menu photos (location data stripped) |
| User Content: Other User Content | Ratings and comments |

Not collected: contacts, browsing history, search history (place searches go to Apple Maps from the device), purchases, health data, diagnostics.

## Age rating

User-generated content and unrestricted web access are not offered, but people can post comments and photos, so answer the "user-generated content" question as **yes** and describe the controls below. Suggested rating: **12+** (frequent/intense mature content: none; infrequent user-generated content). The terms say Stoop is for people 13 and older.

## Review notes (paste into "Notes for review")

> Stoop shows friends on a map and lets people rate places. Sign in with Apple (or email and password with a 6-digit code, or Google). After sign-in, choose a username and a cartoon character.
>
> User-generated content controls: every rating, photo and person has a Report option (the "..." menu), every person can be blocked (Profile > Blocked people to unblock), and terms are linked at sign-in. Reports are reviewed daily. Accounts can be deleted in the app: Profile > Delete account.
>
> Location is shared only with accepted friends, only while the app is open, and ghost mode hides you.
> Contact: magddevf@gmail.com

## Before submitting

- A real two-phone check from TestFlight (the brief's definition of done for milestone 9).
- Sign in with Apple: account deletion should also revoke the Apple token (a known gap, see the API repository's `docs/operations.md`).

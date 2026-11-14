# App Store Connect answers

What to enter in App Store Connect so it matches the app. If the app's behaviour changes, change this and the privacy manifest (`PlaceRating/PrivacyInfo.xcprivacy`) with it.

## Listing (English, the primary language)

| Field | Value |
| --- | --- |
| Name (30) | `Stoop` (if the name is taken, `Stoop: Friends & Places`) |
| Subtitle (30) | `Friends and places on one map` |
| Primary / secondary category | Social Networking / Food & Drink |
| Promotional text (170) | `New: nearby alerts. Get a heads-up when a friend is within 500 m, once a day per friend. Off until you turn it on.` |
| Keywords (100) | `friends,map,location,rate,places,reviews,cafe,restaurant,nearby,share,hangout,food,cairo,arabic` |
| Copyright | `2026 Magd Kamal` |
| Support URL | `https://place-rating-api-production.up.railway.app/terms` (lists the contact address) |
| Marketing URL | leave empty |
| Price | Free, all countries |

Description:

```text
Stoop puts your friends and your favourite places on one map.

SEE YOUR FRIENDS
• Friends you accept appear as their characters and move as they move.
• Only accepted friends can see you, and only while Stoop is open.
• Ghost mode hides you from everyone in one tap.

RATE ANY PLACE
• Tap a café, restaurant or shop on the map to see its average and reviews.
• Rate it in one tap and add a short review. Friends' reviews come first.
• Add photos of the place and its menu, and save anyone's photo.

NEARBY ALERTS (OPTIONAL)
• Get a notification when a friend is within 500 m, at most once a day per friend.
• Off until you turn it on. Your rough location is only compared with your friends' and never shown on the map.

SHARE
• Send a place to WhatsApp or Instagram with a link that opens it in Stoop.
• Open any place in Google Maps.

MADE FOR YOU
• English and Arabic, light and dark, nine map styles.
• A cartoon character instead of a photo of you.
• Report and block anyone, and delete your account from the app at any time.

Terms of Use: https://place-rating-api-production.up.railway.app/terms
Privacy Policy: https://place-rating-api-production.up.railway.app/privacy
```

## Listing (Arabic localization)

| Field | Value |
| --- | --- |
| Name | `Stoop` |
| Subtitle | `أصدقاؤك وأماكنك على خريطة` |
| Promotional text | `جديد: تنبيهات الأصدقاء القريبين. يصلك إشعار عندما يكون صديق على بعد 500 متر، مرة في اليوم لكل صديق. معطّلة حتى تفعّلها.` |
| Keywords | `أصدقاء,خريطة,موقع,تقييم,أماكن,مراجعات,مقهى,مطعم,قريب,مشاركة,خروجات,أكل,القاهرة` |

Description:

```text
يجمع Stoop أصدقاءك وأماكنك المفضلة على خريطة واحدة.

شاهد أصدقاءك
• يظهر الأصدقاء الذين تقبلهم بشخصياتهم ويتحركون معهم.
• لا يراك إلا أصدقاؤك المقبولون، وفقط أثناء فتح Stoop.
• وضع الإخفاء يخفيك عن الجميع بلمسة واحدة.

قيّم أي مكان
• اضغط على مقهى أو مطعم أو متجر على الخريطة لترى تقييمه ومراجعاته.
• قيّمه بلمسة واحدة وأضف مراجعة قصيرة. مراجعات أصدقائك أولًا.
• أضف صور المكان وقائمته، واحفظ أي صورة.

تنبيهات الأصدقاء القريبين (اختيارية)
• يصلك إشعار عندما يكون صديق على بعد 500 متر، مرة واحدة في اليوم لكل صديق على الأكثر.
• معطّلة حتى تفعّلها. يُقارن موقعك التقريبي بمواقع أصدقائك فقط ولا يظهر على الخريطة.

شارك
• أرسل مكانًا إلى واتساب أو إنستغرام برابط يفتحه في Stoop.
• افتح أي مكان في خرائط Google.

مصمم لك
• العربية والإنجليزية، فاتح وداكن، وتسعة أنماط للخريطة.
• شخصية كرتونية بدل صورتك.
• أبلغ عن أي شخص أو احظره، واحذف حسابك من التطبيق في أي وقت.

شروط الاستخدام: https://place-rating-api-production.up.railway.app/terms
سياسة الخصوصية: https://place-rating-api-production.up.railway.app/privacy
```

## Screenshots

Seven 6.9-inch iPhone screenshots (1320 × 2868) per language, from the deck in `marketing/screenshots` (open the editor, then Export, iPhone). App Store Connect scales them for smaller iPhones. `docs/screenshots/{en,ar}/` holds 440 px copies for the README.

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
| Location: Precise Location | Sent to friends while the app is open; held in server memory for 60 s, never stored. With the opt-in Nearby friends alert, also a rough position after each move of about 500 m, even in the background, kept by the server for 30 min (rounded to about 110 m) and never shown to anyone |
| User Content: Photos or Videos | Place and menu photos (location data stripped) |
| User Content: Other User Content | Ratings and comments |

Push notification tokens are not a data type in App Store Connect; they are used only to deliver Stoop's own notifications and removed at sign-out.

Not collected: contacts, browsing history, search history (place searches go to Apple Maps from the device), purchases, health data, diagnostics.

## Age rating

User-generated content and unrestricted web access are not offered, but people can post comments and photos, so answer the "user-generated content" question as **yes** and describe the controls below. Suggested rating: **12+** (frequent/intense mature content: none; infrequent user-generated content). The terms say Stoop is for people 13 and older.

## Review notes (paste into "Notes for review")

> Stoop shows friends on a map and lets people rate places. Sign in with Apple (or email and password with a 6-digit code, or Google). After sign-in, choose a username and a cartoon character.
>
> User-generated content controls: every rating, photo and person has a Report option (the "..." menu), every person can be blocked (Profile > Blocked people to unblock), and terms are linked at sign-in. Reports are reviewed daily. Accounts can be deleted in the app: Profile > Delete account.
>
> Location is shared only with accepted friends, only while the app is open, and ghost mode hides you.
>
> "Always" location is used only by the optional Nearby friends alert (Profile > Notifications > Nearby friends), which is off by default. When the person turns it on, the app asks for notifications and then for Always location, and uses iOS significant-location changes: after the phone moves about 500 m it sends a rough position to our server, which only checks whether an accepted friend is within 500 m and, if so, sends both a notification (at most once a day per friend). The position is never shown on the map, never shared with anyone, and deleted after 30 minutes. Turning the switch off, or ghost mode, stops it.
>
> Test accounts: <reviewer email> / <password>, already friends with <second email> / <password>.
> Contact: magddevf@gmail.com

## Before submitting

- A real two-phone check from TestFlight (the brief's definition of done for milestone 9).
- Sign in with Apple: account deletion revokes the Apple token once `APPLE_KEY_ID` and `APPLE_PRIVATE_KEY` are set on Railway.
- Push notifications: the App ID has Push Notifications enabled and Railway has `APNS_KEY_ID` and `APNS_PRIVATE_KEY` (the API repository's `docs/operations.md`).
- Fill in the two test accounts in the review notes; production has no developer sign-in.

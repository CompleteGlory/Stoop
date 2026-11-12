# Stoop

A one-screen SwiftUI and MapKit app. Friends see each other move on a map (friends only, never strangers), and everyone rates the places they tap: stars, a short review, and photos of the place and its menu. Requires iOS 18 or later. The backend is the separate [`place-rating-api`](https://github.com/CompleteGlory/Stoop-api) repository (NestJS, PostGIS, Redis).

<p align="center">
  <img src="docs/screenshots/en/01.jpg" width="15%" alt="Your friends, on one map">
  <img src="docs/screenshots/en/02.jpg" width="15%" alt="Tap a place, see its stars">
  <img src="docs/screenshots/en/03.jpg" width="15%" alt="Rate it in one tap">
  <img src="docs/screenshots/en/04.jpg" width="15%" alt="Only friends see you">
  <img src="docs/screenshots/en/05.jpg" width="15%" alt="The night map">
  <img src="docs/screenshots/en/06.jpg" width="15%" alt="English or Arabic">
</p>

<details>
<summary>In Arabic</summary>

<p align="center">
  <img src="docs/screenshots/ar/01.jpg" width="15%" alt="Your friends, on one map (Arabic)">
  <img src="docs/screenshots/ar/02.jpg" width="15%" alt="Tap a place, see its stars (Arabic)">
  <img src="docs/screenshots/ar/03.jpg" width="15%" alt="Rate it in one tap (Arabic)">
  <img src="docs/screenshots/ar/04.jpg" width="15%" alt="Only friends see you (Arabic)">
  <img src="docs/screenshots/ar/05.jpg" width="15%" alt="The night map (Arabic)">
  <img src="docs/screenshots/ar/06.jpg" width="15%" alt="English or Arabic (Arabic)">
</p>

</details>

The screenshots are real captures of the app against demo data, laid out with the editor in [`marketing/screenshots`](marketing/screenshots) (see its section below).

## What it does

- **Sign in** with Apple, Google, or email and password, then pick a username and a DiceBear character.
- **Live map.** Accepted friends appear as their characters and move as they move. Ghost mode hides you. The server keeps a position for 60 seconds and never stores it.
- **Rate any place** by tapping it on the map or finding it with search. Stars save on tap, and the review saves when you finish typing. Friends' reviews come first.
- **Photos** of the place and its menu, from the camera or the library. Save anyone's photo to your library, or share it.
- **Share a place** with a link that opens its sheet in Stoop. Without the app, the link opens a web page with Google Maps and Apple Maps links. Each place also has an Open in Google Maps button.
- **Safety.** Report people, reviews and photos. Block people, which hides both of you from each other everywhere.
- **Settings.** Light, dark or system appearance; English or Arabic (right to left) without restarting; your character; ghost mode; account deletion. Nine map themes are picked on the map itself.

## Architecture

The views are small and hold no logic. Each screen has an `@Observable` view model on the main actor. Every outside dependency sits behind a protocol, so the tests swap in fakes: the network, location, the live socket, the photo library and Apple Maps search.

```mermaid
flowchart TB
    subgraph UI["Views (SwiftUI)"]
        root["RootView<br/>switches on SessionStore.phase"]
        onboarding["SignInView · EmailAuthView<br/>UsernameView · CharacterView"]
        map["MapScreen + MapSheet"]
        sheets["PlaceSheet · FriendsSheet<br/>SettingsSheet · BlockedSheet"]
    end
    subgraph VM["View models (@Observable, main actor)"]
        session["SessionStore"]
        mapvm["MapViewModel"]
        placevm["PlaceViewModel<br/>PlacePhotosViewModel"]
        others["FriendsViewModel · SafetyViewModel<br/>SettingsViewModel · PlaceSearchViewModel"]
    end
    subgraph S["Services (protocols at the seams)"]
        api["APIClient<br/>PlacesAPI · FriendsAPI · PhotosAPI<br/>ModerationAPI · LiveAuth"]
        live["LiveSocketClient"]
        loc["LiveLocationService"]
        cache["PlacesChunkCache + HexGrid"]
        misc["MapKitPlaceSearch · PhotoLibrarySaver<br/>DiceBearRenderer · KeychainTokenStore"]
    end
    server[("place-rating-api<br/>REST + /live WebSocket")]

    root --> onboarding & map
    map --> sheets
    onboarding --> session
    map --> mapvm
    sheets --> placevm & others
    mapvm --> api & live & loc & cache
    placevm --> api & misc
    session --> api
    api --> server
    live --> server
```

## Data flow by section

### Sign-in and onboarding

```mermaid
sequenceDiagram
    actor P as Person
    participant V as SignInView
    participant SVM as SignInViewModel
    participant SS as SessionStore
    participant API as APIClient
    participant KC as Keychain
    participant S as Server

    P->>V: Sign in with Apple
    V->>SVM: identity token, one-time code, name
    SVM->>API: signInWithApple(token, raw nonce, name, code)
    API->>S: POST /auth/apple
    S-->>API: access and refresh tokens, user
    API->>KC: save the tokens
    SVM->>SS: signed in
    alt no username yet
        SS-->>V: phase = needsUsername
    else no character yet
        SS-->>V: phase = needsCharacter
    else
        SS-->>V: phase = ready, the map opens
    end
    Note over SS: During onboarding the app warms map tiles and preloads rated places around the last known location.
```

Email sign-up checks the username as you type (`GET /users/availability`, which needs no sign-in) and shows a password strength bar. Google sign-in sends Google's ID token to `POST /auth/google`. On a 401, `AuthSession` refreshes the tokens once and retries. If that fails too, the app goes back to sign-in.

### Map and live location

```mermaid
sequenceDiagram
    participant L as LiveLocationService
    participant M as MapViewModel
    participant WS as LiveSocketClient
    participant S as Server /live
    participant F as Friend's app

    M->>WS: start()
    WS->>S: connect with the access token
    S-->>WS: hello: ghost mode, friends' latest positions
    WS-->>M: .hello, show the friends
    loop while the app is open
        L-->>M: new position
        M->>WS: at most one every 2 s
        WS->>S: loc frame
        S-->>F: position, to accepted friends only
        S-->>WS: a friend's loc frame
        WS-->>M: .loc, move that friend
    end
    Note over M: A friend with no update for 30 s is dimmed and is removed after 60 s. A dropped connection retries after 1, 2, 4, 8 and 16 s, then every 30 s, with jitter.
```

### Places and ratings

```mermaid
flowchart LR
    cam["Camera settles"] --> grid["HexGrid:<br/>hexagons covering the view"]
    grid --> cache{"PlacesChunkCache:<br/>loaded in the last 5 min?"}
    cache -- "yes" --> pins["Pins from memory"]
    cache -- "missing hexagons" --> bbox["GET /places?bbox=…<br/>one request"] --> cache
    tap["Tap a point of interest<br/>or a search result"] --> preview["PlaceSheet opens at once<br/>with Apple's name and category"]
    preview --> resolve["POST /places/resolve<br/>find or create"] --> detail["GET /places/:id<br/>GET /places/:id/ratings"]
    detail --> sheet["Average, star bars,<br/>friends' average, reviews"]
    stars["Tap stars or finish the review"] --> put["PUT /places/:id/rating<br/>debounced, idempotent"] --> update["New average"] --> cache
```

Standing still for 20 seconds preloads a wider ring of hexagons, so nearby places open with their ratings already there.

### Photos

```mermaid
sequenceDiagram
    participant V as PlacePhotosSection
    participant PVM as PlacePhotosViewModel
    participant API as PhotosAPI
    participant S as Server
    participant B as Private bucket
    participant Lib as Photo library

    V->>PVM: picked or captured image
    PVM->>PVM: re-encode as JPEG, at most 2400 px
    PVM->>API: add(placeId, kind, jpeg)
    API->>S: POST /places/:id/photos/upload-url
    API->>B: PUT the JPEG
    API->>S: POST /places/:id/photos {kind, key}
    S-->>API: photo: resized to 1600 px with a thumbnail, metadata removed
    PVM-->>V: newest first
    V->>PVM: Save
    PVM->>Lib: add-only access, the bytes from Nuke's cache
    Note over V: Share hands the JPEG itself to the share sheet.
```

### Friends

```mermaid
flowchart LR
    search["Search by username"] --> req["POST /friends/requests"]
    req --> incoming["Their app: incoming request"]
    incoming -- "accept" --> accepted["POST /friends/requests/:id/accept"]
    accepted --> event["The server tells both live connections"]
    event --> map["Both maps show each other"]
    incoming -- "decline" --> gone["DELETE /friends/:userId"]
```

### Safety

```mermaid
flowchart LR
    menu["SafetyMenu on a person,<br/>review or photo"] --> report["Report: POST /reports"]
    menu --> block["Block: POST /blocks"]
    block --> hide["SafetyViewModel hides their reviews,<br/>photos and marker at once"]
    block --> server["The server ends the friendship<br/>and stops their live frames"]
```

### Settings and account deletion

```mermaid
sequenceDiagram
    actor P as Person
    participant Set as SettingsSheet
    participant SS as SessionStore
    participant S as Server
    participant A as Apple

    P->>Set: Delete my account, then confirm
    Set->>SS: deleteAccount()
    SS->>S: DELETE /me
    S->>S: remove ratings, photos, friendships, blocks and sessions, anonymise the user
    S->>A: revoke the Sign in with Apple token, when the server has the Apple key
    S-->>SS: 204
    SS->>SS: clear the Keychain and image caches
    SS-->>Set: phase = signedOut
```

Appearance, language and map theme are kept on the device (`AppSettings`, in `UserDefaults`) and apply at once.

### Shared place links

```mermaid
sequenceDiagram
    actor A as Sender
    participant App as Stoop
    participant WA as WhatsApp or Instagram
    actor B as Friend
    participant S as Server

    A->>App: Share on a place
    App->>WA: https://…/p/placeId
    WA-->>B: link with a preview: name and average
    alt Stoop is installed
        B->>App: tap, iOS opens Stoop (universal link)
        App->>App: SessionStore keeps the link, the map opens the place sheet and flies there
    else no Stoop
        B->>S: GET /p/placeId
        S-->>B: web page with Open in Stoop, Google Maps and Apple Maps
    end
```

## Classes and models

```mermaid
classDiagram
    direction LR

    class SessionStore {
        phase: Phase
        pendingLink: DeepLink?
        start()
        handle(url) Bool
        deleteAccount()
    }
    class MapViewModel {
        camera
        sheet: Sheet
        friends: FriendsState
        places: [Place]
        placeModel: PlaceViewModel?
        start()
        select(feature)
        openShared(link)
        handle(event)
    }
    class PlaceViewModel {
        place: Place?
        stars: Int
        comment: String
        load()
        setStars(n)
    }
    class PlacePhotosViewModel {
        kind: PhotoKind
        photos: [PlacePhoto]
        add(imageData)
        delete(photo)
        save(photo)
    }
    class SafetyViewModel {
        blocked: [PublicUser]
        isBlocked(id) Bool
        block(user)
    }
    class FriendsViewModel
    class SettingsViewModel
    class PlaceSearchViewModel
    class AppSettings {
        appearance
        language
        mapTheme
    }

    class APIClient
    class APIClientProtocol
    <<protocol>> APIClientProtocol
    class PlacesAPI
    <<protocol>> PlacesAPI
    class FriendsAPI
    <<protocol>> FriendsAPI
    class PhotosAPI
    <<protocol>> PhotosAPI
    class ModerationAPI
    <<protocol>> ModerationAPI
    class LiveAuth
    <<protocol>> LiveAuth
    class AuthSession
    <<actor>> AuthSession
    class HTTPClient
    class TokenStore
    <<protocol>> TokenStore
    class KeychainTokenStore
    class LiveSocketProtocol
    <<protocol>> LiveSocketProtocol
    class LiveSocketClient
    class LocationServiceProtocol
    <<protocol>> LocationServiceProtocol
    class LiveLocationService
    class PlacesChunkCache
    class HexGrid
    class PhotoSaving
    <<protocol>> PhotoSaving
    class PhotoLibrarySaver
    class PlaceSearching
    <<protocol>> PlaceSearching
    class MapKitPlaceSearch

    class SelfUser {
        id
        username
        displayName
        avatar
        ghostMode
    }
    class PublicUser
    class Avatar {
        style
        options
    }
    class Place {
        id
        appleId
        name
        category
        latitude
        longitude
        avgRating
        ratingCount
    }
    class PlaceDetail
    class MyRating
    class PlaceRating {
        stars
        comment
    }
    class PlacePhoto {
        kind
        url
        thumbnailUrl
    }
    class FriendsList
    class FriendshipEntry
    class FriendsState
    class FriendFix
    class LiveEvent
    <<enum>> LiveEvent
    class DeepLink
    <<enum>> DeepLink

    SessionStore --> APIClientProtocol
    SessionStore --> PlacesChunkCache
    SessionStore ..> DeepLink
    MapViewModel --> PlacesAPI
    MapViewModel --> FriendsAPI
    MapViewModel --> LiveSocketProtocol
    MapViewModel --> LocationServiceProtocol
    MapViewModel --> PlacesChunkCache
    MapViewModel *-- PlaceSearchViewModel
    MapViewModel *-- SafetyViewModel
    MapViewModel o-- PlaceViewModel
    MapViewModel o-- FriendsViewModel
    MapViewModel *-- FriendsState
    PlaceViewModel --> PlacesAPI
    PlaceViewModel *-- PlacePhotosViewModel
    PlaceViewModel --> SafetyViewModel
    PlacePhotosViewModel --> PhotosAPI
    PlacePhotosViewModel --> PhotoSaving
    SafetyViewModel --> ModerationAPI
    PlaceSearchViewModel --> PlaceSearching
    SettingsViewModel --> SessionStore
    PlacesChunkCache --> HexGrid
    PlacesChunkCache --> PlacesAPI

    APIClientProtocol <|.. APIClient
    PlacesAPI <|.. APIClient
    FriendsAPI <|.. APIClient
    PhotosAPI <|.. APIClient
    ModerationAPI <|.. APIClient
    LiveAuth <|.. APIClient
    APIClient *-- HTTPClient
    APIClient *-- AuthSession
    AuthSession --> TokenStore
    TokenStore <|.. KeychainTokenStore
    LiveSocketProtocol <|.. LiveSocketClient
    LiveSocketClient --> LiveAuth
    LiveSocketClient ..> LiveEvent
    LocationServiceProtocol <|.. LiveLocationService
    PhotoSaving <|.. PhotoLibrarySaver
    PlaceSearching <|.. MapKitPlaceSearch

    SelfUser *-- Avatar
    PublicUser *-- Avatar
    PlaceDetail *-- Place
    PlaceDetail *-- MyRating
    PlaceRating --> PublicUser
    PlacePhoto --> PublicUser
    FriendsList *-- FriendshipEntry
    FriendshipEntry --> PublicUser
    FriendsState *-- FriendFix
    LiveEvent ..> FriendFix
```

## Run it

Start the backend locally (see its `CLAUDE.md`), then open `PlaceRating.xcodeproj` and run the `PlaceRating` scheme. Debug builds talk to `http://localhost:3000` (you can switch to production on the sign-in screen). Release builds always use production.

`project.yml` is the source of truth for project settings. After changing it or adding files, regenerate the project:

```bash
xcodegen generate
```

User-facing strings live in `tools/strings/make_strings.py` with their Arabic translations. After adding one, regenerate the String Catalogs:

```bash
python3 tools/strings/make_strings.py PlaceRating/Resources
```

## Releasing

Every push to `main` runs `.github/workflows/testflight.yml`: the tests on a simulator, then a Release archive with a new build number (the UTC date and time), uploaded to TestFlight. Signing is automatic, with an App Store Connect API key in the repository secrets `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID` and `APP_STORE_CONNECT_KEY` (the `.p8` contents). The key needs the Admin role, so Xcode can create the distribution certificate and profile itself. Google sign-in in those builds needs the repository variables `GOOGLE_CLIENT_ID` and `GOOGLE_REVERSED_CLIENT_ID`. The version shown in the App Store is `MARKETING_VERSION` in `project.yml`.

## Screenshots

`marketing/screenshots` is the App Store screenshot editor from the [app-store-screenshots](https://github.com/ParthJadhav/app-store-screenshots) skill, with Stoop's deck in `app-store-screenshots.json` and the raw captures under `public/screenshots/apple/iphone/{en,ar}/`. To change the copy or layout, run it and press **Export bundle** for every App Store iPhone size in both languages:

```bash
pnpm --dir marketing/screenshots install
```

```bash
pnpm --dir marketing/screenshots exec next dev --port 3100
```

To retake the captures, run the API locally with demo data and launch a Debug build with the screenshot options in `PlaceRating/Debug/ScreenshotRun.swift` (they sign in, open a place or sheet, and frame the map without tapping). Apple's device bezels are not in git: copy `public/frames/` from the skill's template if you want them instead of the editor's drawn frames.

## Tests

Swift Testing, with a fake for every protocol above (`PlaceRatingTests/Support.swift`). Run them in Xcode with ⌘U, or:

```bash
xcodebuild test -project PlaceRating.xcodeproj -scheme PlaceRating -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

## Layout

```text
PlaceRating/
  App/        entry point, RootView, SessionStore, settings, brand colours
  Features/   Onboarding, Map, Place, Friends, Search, Safety, Settings: a view and its view model each
  Models/     Codable types matching the API
  Services/   API client, auth session, live socket, location, hexagon cache, links, photo saving
  Resources/  String Catalogs (English and Arabic), assets
PlaceRatingTests/
docs/app-store.md   App Store listing, privacy answers and review notes
```

## Privacy

Location is shared only while the app is open and only with accepted friends. The server keeps a position for 60 seconds and never writes it to a database. Photos are re-encoded on the server, which removes their location metadata. The privacy manifest is `PlaceRating/PrivacyInfo.xcprivacy`, and the API serves the privacy policy at `/privacy`.

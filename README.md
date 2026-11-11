# Stoop

A one-screen SwiftUI and MapKit app: friends see each other move on a map and rate places by tapping them. Requires iOS 18 or later. The backend is the separate `place-rating-api` repository.

## Run it

Start the backend locally (see its `CLAUDE.md`), then open `PlaceRating.xcodeproj` and run the `PlaceRating` scheme. Debug builds talk to `http://localhost:3000`, Release builds to production.

`project.yml` is the source of truth for project settings. After changing it or adding files, regenerate the project:

```bash
xcodegen generate
```

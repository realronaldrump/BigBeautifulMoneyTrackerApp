# Big Beautiful Money Tracker App

Local-first iPhone earnings tracker built with SwiftUI, SwiftData, WidgetKit, ActivityKit, App Intents, and reminders.

## Current Status

- SwiftUI app with onboarding, concurrent jobs, live shift tracking, history editing, schedules, templates, summaries, and PDF exports.
- Earnings support dated rates, night premiums, daily and weekly overtime, and a configurable workweek start.
- Newly saved shifts retain priced earning segments so later settings changes do not move their earnings between periods.
- Take-home estimates use 2026 federal, Colorado, and FICA rules, with insurance, retirement, and paycheck adjustments.
- SwiftData stays local. The app and widgets share an App Group store; existing app data is copied with SQLite's online backup before switching stores.
- See [the correctness review](docs/review-2026-10-24.md) and [UI/UX polish notes](docs/ui-ux-review-2026-10-25.md) for changes, test coverage, and device verification limits.

## Local Validation

Run the shared calculation and SwiftData tests on a Mac, without a simulator:

```bash
swift test
```

Generate the Xcode project and compile the app and widget without signing:

```bash
xcodegen generate
xcodebuild -project BigBeautifulMoneyTracker.xcodeproj -scheme BigBeautifulMoneyTracker -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Compile the complete iOS test target without launching a simulator:

```bash
xcodebuild -project BigBeautifulMoneyTracker.xcodeproj -scheme BigBeautifulMoneyTracker -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build-for-testing
```

The Mac suite excludes the ActivityKit and UIKit/PDF tests. Those tests remain in the iOS test target. Generic builds check compilation; they do not verify rendered UI or device behavior.

## Archive

```bash
xcodebuild -project BigBeautifulMoneyTracker.xcodeproj -scheme BigBeautifulMoneyTracker -destination 'generic/platform=iOS' -archivePath build/BigBeautifulMoneyTrackerApp.xcarchive archive
```

If Xcode reports missing profiles or account access, open the project in Xcode, confirm the Apple account/team, and let Xcode refresh signing for:

- `com.davis.BigBeautifulMoneyTracker`
- `com.davis.BigBeautifulMoneyTracker.Widgets`

## App Store Connect Next Steps

1. Verify the bundle IDs and capabilities in the Apple Developer portal.
2. Confirm App Group capability for app/widget data sharing on device.
3. Export an App Store-signed archive or upload directly from Organizer.
4. Finish App Store Connect metadata, screenshots, privacy nutrition labels, and review notes.

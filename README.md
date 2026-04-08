# Big Beautiful Money Tracker App

Local-first iPhone earnings tracker built with SwiftUI, SwiftData, WidgetKit, ActivityKit, App Intents, and reminders.

## Current Status

- Greenfield iOS project scaffolded with app target, widget/Live Activity extension, and unit tests.
- Main flow implemented: onboarding, one-tap start/end shift, live ticker, history, settings, templates, reminders, Siri shortcuts, widgets, and Live Activity.
- Earnings engine supports exact time-based gross calculation, night differential splitting, rate changes, and optional overtime thresholds.
- Tax engine estimates federal + Colorado + FICA take-home using current settings and year-to-date context.
- App Store preflight scan is `GREENLIT` with no critical findings.
- iOS archive has succeeded locally at least once from this machine, but current archive attempts depend on local Xcode account/provisioning state.

## Build

```bash
xcodegen generate
xcodebuild -project BigBeautifulMoneyTracker.xcodeproj -scheme BigBeautifulMoneyTracker -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.2' build
```

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

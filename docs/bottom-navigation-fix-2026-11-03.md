# Bottom navigation and shift controls

The custom menu previously used a bottom safe-area inset on `TabView`. Its UIKit
container did not consistently pass that inset to its child pages. On the
reproduction device, the Start Shift button occupied y=770–832 while the Home
menu button occupied y=772–828. The menu covered the primary action and the last
rows of pushed forms, including Archive Job.

The menu now sits in a sibling layout row below `TabView`. This gives every tab
and navigation destination a smaller viewport instead of covering their content.
Home keeps its shift action above that boundary. The page background continues
behind the menu and home indicator, the opaque action-bar background and duplicate
menu outline are removed, and the off-shift page has less unused vertical space.
The Archive row also exposes a full rectangular tap target.

`BottomNavigationTests` runs the complete app with a DEBUG-only in-memory store.
It checks an hourly job starting and ending above the menu, the last job-settings
row opening Archive confirmation, navigation after dismissing a search keyboard,
salary-only Home without a clock button, and accessibility text sizes. Fixtures
never open or change personal records and are absent from Release builds.

Verification on the running iPhone 17 Pro simulator with iOS 26.5:

- Before the change, the Start Shift visibility/tap test failed and a screenshot
  reproduced the covered button.
- After the change, all five UI tests passed, including the Archive confirmation
  being opened and dismissed without archiving the fixture job.
- All 110 iOS calculation, persistence, and export tests passed.
- Greenlight reported zero critical findings.

The UI target is included in the normal Xcode scheme and GitHub Actions iOS run.

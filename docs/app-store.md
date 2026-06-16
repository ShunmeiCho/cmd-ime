# Mac App Store Distribution

CmdIME currently targets direct distribution through GitHub Releases, the
one-line installer, and Homebrew cask. Mac App Store distribution is possible
only as a separate App Store build path.

## Current Status

The current public package is not a Mac App Store upload artifact.

It is built as a Swift Package executable bundle, signed for local or direct
distribution, and packaged as a zip. A Mac App Store submission needs an App
Store archive with App Sandbox enabled, App Store signing, a provisioning
profile, App Store Connect metadata, and App Review notes.

## Requirements

1. Join the Apple Developer Program.
2. Create an explicit Bundle ID for CmdIME in Certificates, Identifiers &
   Profiles.
3. Create a macOS app record in App Store Connect.
4. Add an Xcode app target or Xcode project wrapper for the current Swift
   Package sources.
5. Enable App Sandbox for the App Store build.
6. Add only the entitlements the app truly needs.
7. Archive the app in Xcode with Apple Distribution signing.
8. Upload the build to App Store Connect using Xcode Organizer or Transporter.
9. Test with TestFlight before App Review.
10. Fill App Store metadata, privacy labels, screenshots, pricing, availability,
    and review notes.
11. Submit for App Review and respond to review feedback.

## CmdIME-Specific Review Risks

CmdIME listens for global keyboard events and requests Accessibility and Input
Monitoring permissions. For App Review, the app should clearly explain:

- why global keyboard listening is needed
- that the app switches input sources and does not record typed text
- how users grant and revoke permissions
- how the app continues running as a menu bar agent after the settings window
  closes

The App Store build must be tested under App Sandbox, not only with the direct
distribution package. If a required keyboard-monitoring behavior is rejected or
blocked by sandbox rules, keep App Store distribution separate from the
Developer ID/Homebrew release channel.

## Direct Distribution vs App Store

Direct distribution:

- sign with a Developer ID Application certificate
- enable hardened runtime
- notarize with Apple notary service
- publish the notarized zip or dmg through GitHub Releases and Homebrew

Mac App Store distribution:

- sign with Apple Distribution
- enable App Sandbox
- upload an archive to App Store Connect
- pass TestFlight and App Review

## Apple References

- Apple macOS distribution overview:
  https://developer.apple.com/macos/distribution/
- App Sandbox:
  https://developer.apple.com/documentation/security/app-sandbox
- Add a new app in App Store Connect:
  https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/
- Upload builds:
  https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/
- TestFlight overview:
  https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/
- Publishing overview:
  https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/overview-of-publishing-your-app-on-the-app-store/
- App Review Guidelines:
  https://developer.apple.com/app-store/review/guidelines/
- Notarizing direct-distribution software:
  https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution

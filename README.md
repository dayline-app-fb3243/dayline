# Dayline

A day planner and life timeline for iPhone (iOS 26+, built with the iOS 27 SDK).

- **Today**: a live 0-100 day score with a one-word label and what's driving it, a schedule that fills itself in from your routine (work hours, usual lunch out), and quick photo / voice-note capture.
- **Timeline**: map of everywhere you went by day, week, month or year, with photos pinned where they were taken, plus the day's timeline of places, photos and transcribed voice notes.
- **Insights**: day, month and year scores with gentle notes on rough days.
- **Journal**: all photos, voice notes (transcribed on device) and notes.
- **Widgets** (Home and Lock Screen), a Control Center voice-note button, and two notifications: a follow request and hitting 80.
- **Siri / Shortcuts**: "Add the latest picture I took to Dayline", "How's my day going in Dayline", "Record a voice note in Dayline", "Add to my schedule in Dayline".

## Battery
No continuous GPS and no timers. Dayline only uses iOS visit monitoring and significant-location changes (the lowest-power signals), plus the location stored in your photos. Check-ins closer than 5 minutes apart are dropped.

## Look
Content is on solid cards that follow light / dark mode. Liquid Glass is used for floating controls (tab bar, buttons, map controls) through the system glass APIs, so it follows the Clear / Tinted setting in Settings > Display & Brightness.

## Build
```
brew install xcodegen
xcodegen generate
open Dayline.xcodeproj
```
Run with the `-demo` launch argument to load sample data. `.github/workflows/preview.yml` builds on a GitHub macOS runner, runs a UI tour in the simulator and uploads screen recordings (light and dark).

Publishing to the App Store / TestFlight needs an Apple Developer Program membership and a team ID in `project.yml`.

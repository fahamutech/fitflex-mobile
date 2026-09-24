# Device integration: preparation notes

Status: **not built**. No health platform package, permission or
entitlement is in the app yet. This page is the checklist for when it is.

## Three kinds of activity data

Every `Activity` has a `source`. The app groups them into three
`DataOrigin`s and labels each row with one of them:

| Origin | `source` values | Who creates it |
|---|---|---|
| **Device** | `device` + `devicePlatform` + `externalId` | Only a device provider, from a platform reading |
| **FitFlex** | `fitflex` | FitFlex itself, e.g. the server when a workout is completed |
| **Manual** | `manual`, `trainer`, `gym` | A person: the member, their trainer or gym |

Sample data (debug builds, `ACTIVITY_SAMPLE_DATA`) is marked `isSample`
and is always labelled **Sample**, never Device.

## Never fabricate device data

These rules are already enforced:

- `POST /me/activities` accepts only `source: manual`. Device and FitFlex
  records can't be typed in (`source_not_loggable`), and a manual entry
  can't carry `devicePlatform`, `externalId` or `deviceName`.
- A `device` record without a `devicePlatform` is shown as manual, not as
  measured.
- `genuineDeviceRecords()` drops anything a device provider returns that
  isn't `source: device` with that provider's platform and a record id.
- Health platform packages may only be imported under
  `lib/shared/activity/providers/` (see
  `test/device_data_architecture_test.dart`).

A provider must never estimate, interpolate or pad: no reading means no
record. Missing days stay at zero.

Device data is still reported by the member's phone, so the server can't
prove it came from a sensor. The sync endpoint should keep the plausibility
limits the log endpoint uses.

## Android: Health Connect

- [ ] Pick the package (e.g. `health` on pub.dev, or a small platform
      channel to `androidx.health.connect:connect-client`).
- [ ] Raise `minSdk` to 26 (currently `max(flutter.minSdkVersion, 23)`).
- [ ] Declare only the permissions we read:
      `android.permission.health.READ_STEPS`, `READ_DISTANCE`,
      `READ_EXERCISE`. Add `READ_HEALTH_DATA_HISTORY` only if we import more
      than 30 days back.
- [ ] Add the permissions-rationale activity
      (`androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE`, and the
      Android 14 `VIEW_PERMISSION_USAGE` / `HEALTH_PERMISSIONS` alias)
      linking to our privacy policy.
- [ ] Complete the Play Console health apps declaration, and update the
      privacy policy.
- [ ] Daily steps: use the aggregate API, which removes duplicates across
      apps. Don't sum records.
- [ ] Active minutes: Health Connect has no direct type, so derive them
      from exercise sessions and say so in the UI.

## iOS: Apple Health (HealthKit)

- [ ] Enable the HealthKit capability (adds `Runner.entitlements` with
      `com.apple.developer.healthkit`).
- [ ] Add `NSHealthShareUsageDescription` to `Info.plist`. Add
      `NSHealthUpdateUsageDescription` only if we ever write to Health.
- [ ] Read `stepCount`, `distanceWalkingRunning`, `appleExerciseTime` and
      workouts.
- [ ] Daily steps: use `HKStatisticsCollectionQuery`, which removes
      duplicates between iPhone and Watch.
- [ ] Check `HKHealthStore.isHealthDataAvailable()` first; some iPads don't
      have it.
- [ ] App Store: health data can't be used for advertising or stored in
      iCloud. The review notes should explain the feature.

## Fitbit, Garmin and other wearables

These connect server to server: OAuth, then the vendor pushes data to our
webhook. Garmin's Health API also needs partner approval. The server
would write `source: device` records with `devicePlatform: fitbit | garmin`
and the vendor's record id. Most watches already write to Apple Health or
Health Connect, so start there.

## Server work when a provider is built

- [ ] A sync endpoint (e.g. `POST /me/device-activities`) that upserts a
      batch by `(userId, devicePlatform, externalId)`. The unique index
      already exists.
- [ ] It requires `devicePlatform` and `externalId`, and applies the same
      plausibility limits as manual logging.
- [ ] Decide what disconnecting a platform does to records already synced.

## Why nothing is declared yet

Both stores review health permissions. Play requires a declaration and
expects every declared health permission to be used, and App Review
questions a HealthKit entitlement the app doesn't use. So the permissions,
entitlement and usage strings get added in the same change as the provider
that needs them.

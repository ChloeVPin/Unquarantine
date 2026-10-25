# Use Unquarantine

## Prepare an app

1. Drop one `.app`, `.dmg`, or `.iso` into the main window, or choose a file.
2. Check the app name and read the trust prompt.
3. Choose **Trust & Prepare** only if you trust where the app came from. If it
   is not quarantined, the prompt explains that no quarantine flag will be
   removed.
4. Approve the macOS administrator prompt if one appears. It is needed when
   Unquarantine has to copy the app into `/Applications`.
5. Choose **Open App** or **Done** on the result screen.

Unquarantine does not scan an app for malware or verify its developer. Removing
the quarantine flag changes how macOS treats that app; it is not a safety
check.

## Disk images

Disk images are mounted read-only and kept out of Finder while Unquarantine
looks for an app. The image must contain exactly one app. It is ejected when
you finish or cancel the flow.

## Settings

- **Open apps when finished** launches the prepared app as soon as preparation
  completes.
- **Quit on finish** quits Unquarantine when you open the prepared app or
  choose **Done**.
- **Look for new quarantined apps** installs a LaunchAgent for your account. It
  watches `/Applications` and opens Unquarantine when it finds a newly added
  quarantined app. Keep Unquarantine in `/Applications` for relaunch while it
  is closed. Turning the setting off removes the agent.
- **Liquid Glass appearance** adds a translucent window background and glass
  to interactive surfaces. macOS adapts these surfaces to your transparency
  and contrast settings.
- **Check for updates automatically** checks the latest public GitHub release
  once a day while Unquarantine is open. Checks do not install anything. When
  an update is available, a small pill appears at the top right of the main
  window. Choose it to install and relaunch. The download is checked against
  GitHub’s published SHA-256 digest, and macOS requests administrator approval
  only if replacing the app requires it.

Use **Check for Updates…** from the app menu to check immediately. Turn off
automatic checks in Settings to stop the daily checks.

## If preparation cannot continue

An app with the same name already in `/Applications` is left untouched. Move
or rename the existing app yourself if you want to prepare a different copy.
Unsupported files and disk images with no app, or more than one app, are shown
as errors without changing the source file.

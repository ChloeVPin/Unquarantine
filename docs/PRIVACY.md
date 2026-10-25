# Privacy

Unquarantine processes selected apps and disk images on your Mac. It does not
send app contents, file names, or usage data to a server, and it has no
analytics or update service.

When background monitoring is enabled, a LaunchAgent runs under your account
and watches `/Applications` for newly added quarantined apps. It stores paths
of apps it has already seen so it does not repeatedly open the same item. A
small local handoff file passes a newly found app path to Unquarantine.

The app stores its preferences in macOS defaults. It contacts the network only
if you choose the optional Buy Me a Coffee link in the About window.

When an app needs to be copied into `/Applications`, macOS may ask for
administrator approval. The authorization is used for that copy and quarantine
change; Unquarantine itself does not run as a background root process.

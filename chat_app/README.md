# tinkerpro_chat

TinkerPro Chat — a chat-only build of the TinkerPro Support companion app.

Everything the full app carries outside of messaging (dashboard, BIR/customers,
leads, tickets, files, tasks, licenses, blog, pricing, offers, activity logs,
release notes, user admin, the in-app updater) is gone. What ships:

- Server config + login (password or native Google sign-in)
- Chat inbox, threads, attachments, group conversations, participants
- Realtime over Soketi, presence, unread counts, chat-head bubbles
- FCM push, foreground banners, CallKit incoming-call wakeups
- WebRTC voice + video calls
- Settings: profile/avatar, appearance (light/dark), chat bubble toggle,
  change server, sign out

## Identity

Same `com.tinkerpro.support` application id, Firebase project
(`android/app/google-services.json`) and release keystore
(`android/app/upload-keystore.jks` via `android/key.properties`) as
`flutter_app`, so an install upgrades the full app in place and keeps the
existing FCM registration. Change `applicationId`/`namespace` in
`android/app/build.gradle.kts` (and add a matching Firebase app + fresh
`google-services.json`) if it should live side by side instead.

## Build

Realtime is dead without the Soketi defines — the WebSocket falls back to
port 6001 with no path, which production does not expose. Use the same set
the CI Android/iOS workflows pass:

    DEFINES="--dart-define=TPS_BASE_URL=https://support.tinkerpro.io \
      --dart-define=CHAT_SOKETI_HOST=support.tinkerpro.io \
      --dart-define=CHAT_SOKETI_PORT=443 \
      --dart-define=CHAT_SOKETI_TLS=true \
      --dart-define=CHAT_SOKETI_PATH=/soketi \
      --dart-define=CHAT_SOKETI_KEY=tinkerpro-chat-key"

    flutter pub get
    flutter run $DEFINES
    flutter build apk --release $DEFINES

`TPS_BASE_URL` defaults to `https://support.tinkerpro.io`; whatever the user
types on the connect screen wins over it.

# Inkus

> The AI journal that stays put.

A private, on-device AI journaling app for **iPhone and Mac**. Apple Intelligence prompts each morning, a gentle reflection each Sunday — generated entirely on your device. No account, no cloud, no subscription.

This repository is the source code for the shipped App Store app, made publicly readable so you can see exactly what runs on your phone. See **[Licence](#licence)** below for what you can and cannot do with it.

— Made by [Giant Mushroom Studio](https://giantmushroom.studio).

---

## Try it

The shipped app: [giantmushroom.studio/inkling](https://giantmushroom.studio/inkling/) · App Store (link added at launch).

## What's inside

- **iOS 26+ / macOS 26+** universal app, written in **Swift 6** with strict concurrency
- **SwiftUI** throughout, **SwiftData** for persistence, **CloudKit** private database for optional sync
- **Foundation Models** framework for on-device AI (daily prompt, mood/tag suggestions, weekly reflection) with a curated 80-prompt fallback bank
- **WidgetKit** small + medium "Today's Prompt" widgets (iOS only)
- **App Intents** for Shortcuts, Spotlight, and the medium widget's *Start writing* button
- **Mac Catalyst** (Optimised for Mac) — same binary, native Mac chrome, keyboard shortcuts (⌘N, ⌘F, ⌘,, ⇧⌘R)
- **Markdown + PDF export** via the system share sheet
- Local notifications for the Sunday weekly reflection
- Crisis-resources card with international helpline links

## Architecture (high-level)

```
Inkus/
├── App/                         # @main entry, RootView, scene commands
├── Features/                    # SwiftUI views, one folder per feature
│   ├── EntryList/               # main list, daily-prompt card, calendar view
│   ├── EntryDetail/             # detail view + editor + mood pill
│   ├── Journals/                # switcher / editor / list
│   ├── Reflections/             # weekly reflection view + banner
│   ├── Search/                  # search + filter chips
│   ├── Settings/                # settings, privacy, crisis, export
│   └── Onboarding/              # 3-page paged TabView
├── Models/                      # @Model SwiftData types (4)
├── AI/                          # FoundationModels generators + services
├── Persistence/                 # ModelContainer wiring, CloudKit + App Group
├── Services/                    # AttachmentStore, Notification*, Export, etc.
├── DesignSystem/                # colours, typography, spacing tokens
├── AppIntents/                  # NewEntryIntent + AppShortcutsProvider
└── Resources/                   # bundled FallbackPrompts.json

InklingWidgets/                  # widget extension target (iOS only)
```

## Building

You'll need Xcode 17+ and an Apple Developer account.

1. Clone and open `Inkling.xcodeproj`
2. Set your **Development Team** under target Inkling → Signing & Capabilities (this repo ships with the team blanked)
3. Update the **CloudKit container** identifier under iCloud capability (default is `iCloud.com.giantmushroom.Inkling` — change to your reverse-domain)
4. Update the **App Group** identifier under App Groups capability (default is `group.com.giantmushroom.Inkling`)
5. Bundle ID: defaults to `com.giantmushroom.Inkling` — change to yours
6. Build for **iPhone 17 Pro** simulator, **My Mac (Mac Catalyst)**, or your real device

Apple Intelligence features require iOS 26 / macOS 26 with Apple Intelligence enabled (iPhone 15 Pro and later, Apple Silicon Macs). On other devices the app falls back to the bundled 80-prompt bank.

### Optional: Dropbox + Google Drive sync

Both providers use PKCE OAuth — no client secret in the app. You only need to drop in the public client identifiers.

**Dropbox**

1. Sign in to <https://www.dropbox.com/developers/apps> → **Create app** → "Scoped access" → "Full Dropbox" → name "Inkus"
2. On the **Settings** tab, copy the **App key** and add an OAuth 2 redirect URI: `inkling://oauth-callback/dropbox`
3. On the **Permissions** tab, enable: `files.content.write`, `files.content.read`, `files.metadata.read`, `files.metadata.write`, `account_info.read`
4. In Xcode, select the Inkling target (named Inkus on the home screen) → Build Settings → search for `INKLING_DROPBOX_APP_KEY` → paste the app key
5. Rebuild

**Google Drive**

1. Sign in to <https://console.cloud.google.com/apis/credentials> → **Create Credentials** → **OAuth client ID** → application type **iOS**
2. Bundle ID: `com.giantmushroom.Inkling` (or whatever you changed it to)
3. Copy the **Client ID** (looks like `123456789-abc.apps.googleusercontent.com`)
4. In Xcode, Inkling target (named Inkus on the home screen) → Build Settings:
   - `INKLING_GOOGLE_CLIENT_ID` = the full client ID
   - `INKLING_GOOGLE_REVERSE_CLIENT_ID` = the same value reversed, e.g. `com.googleusercontent.apps.123456789-abc`
5. Enable the Google Drive API for your project at <https://console.cloud.google.com/apis/library/drive.googleapis.com>
6. Rebuild

When the OAuth identifiers are blank the corresponding Settings section explains what to set; the rest of the app works as normal.

## Privacy posture

This is the entire point of the app. From the in-app privacy page:

> Every entry, every prompt, every reflection is generated and stored on your device. Nothing goes to OpenAI, Google, or our servers — because we don't have any. Optional iCloud sync uses your private CloudKit database; Apple controls it, we cannot read it.

You can verify this. There are zero outbound network calls in the writing or AI paths. Search for `URLSession` in this repo and you will find no hits in those code paths.

The full, plain-English policy lives at [giantmushroom.studio/inkling/privacy](https://giantmushroom.studio/inkling/privacy.html).

## Contributing

This repo is published primarily as a transparency artefact. We're not actively soliciting pull requests, but bug reports and security-disclosure issues are welcome — open a GitHub issue or email **contact@giantmushroom.studio**.

## Licence

**Source-available, all rights reserved.** See [`COPYING.md`](COPYING.md).

You may read this code, learn from it, and reference small snippets with attribution. You may not redistribute, repackage, fork-and-publish, or ship a derivative product, in whole or in part, without prior written permission from Giant Mushroom Studio.

If you'd like to use a substantive part of this code in your own work, please email **contact@giantmushroom.studio** — we're usually happy to say yes.

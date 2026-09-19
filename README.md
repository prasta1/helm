# Helm

> [!WARNING]
> **This project is no longer maintained and is archived.**
>
> Development moved to a ground-up rewrite in a separate, private repository,
> `the-helm`. It keeps the same idea — a personal CRM built around a Job Search
> pipeline and Peregrine Design Werx business development — but shares no code
> or git history with this one.
>
> Last commit here: **2026-07-18**. The code below still builds and runs as
> described, but nothing further will be added and issues will not be addressed.
> Everything that follows is kept for reference.

**How the successor differs:**

| | This repo (`helm`) | Successor (`the-helm`, private) |
|---|---|---|
| Persistence | SwiftData | GRDB / SQLite |
| Platforms | macOS, iPadOS, iOS | macOS only |
| AI | Anthropic / OpenAI / OpenAI-compatible | Apple Intelligence (on-device) or Ollama |
| Integrations | Google Calendar, Granola | none (local-only) |

---

A personal, customizable CRM for macOS, iPad and iPhone — built in SwiftUI +
SwiftData. Track deals across pipelines (Job Search and Peregrine Prospects to
start), manage contacts and meetings, pull in Google Calendar events and Granola
summaries, and use an LLM for AI-assisted follow-ups, next steps and briefs.

> Status: **Foundation.** The full local CRM works end-to-end today. The
> Calendar, Granola and LLM integrations are implemented but need *your*
> credentials/paths to go live (see setup below). This foundation was written
> outside Xcode, so build it once in Xcode and address any environment-specific
> tweaks Xcode flags.

## Features

- **Pipelines & boards** — a kanban board per pipeline with drag-and-drop across
  stages. Ships with **Job Search** and **Peregrine Prospects**; both fully
  editable (stages, colors, won/lost terminals).
- **Deals** — value, status, notes, linked contacts, an activity timeline
  (notes/tasks/calls/emails), and custom fields.
- **Contacts** — searchable directory with linked deals, notes and custom fields.
- **Custom fields** — add your own fields to deals/contacts (text, number,
  currency, date, toggle, link, single-select), globally or scoped to a pipeline.
  This is how the CRM grows with you.
- **Meetings** — import summaries from the **Granola** desktop app (macOS) or add
  them manually; link to contacts and deals.
- **Calendar** — connect **Google Calendar** (read-only) to see upcoming events
  and pull them in as meeting notes.
- **AI assistant** — provider-agnostic (Anthropic Claude or OpenAI, or any
  OpenAI-compatible/local endpoint). Suggests next steps, drafts follow-ups,
  extracts action items, writes contact prep briefs, and free-form chat with
  optional pipeline context.
- **One codebase, three devices** — an adaptive `NavigationSplitView` that feels
  native on Mac, iPad and iPhone.

## Requirements

- Xcode 16 or later (the project uses Xcode 16 synchronized file groups).
- iOS/iPadOS 17+ and macOS 14+ (SwiftData + the modern Observation model).

## Getting started

The repo ships a pre-generated `Helm.xcodeproj`, so:

```bash
open Helm.xcodeproj
```

Select the **Helm** scheme, pick a Mac or an iOS destination, and run.
For device/App Store builds set your **Team** under *Signing & Capabilities*
(the bundle id is `com.helm.app` — change it to your own).

### Regenerating the project (optional)

The project is also described by `project.yml` for
[XcodeGen](https://github.com/yonovoy/XcodeGen). If you change top-level build
settings or add targets, regenerate:

```bash
brew install xcodegen
xcodegen generate
```

Because sources use Xcode's *synchronized folder* feature, simply adding a `.swift`
file under `Helm/` includes it in the build — no project edits needed.

## Configuration

All configuration lives in **Settings** (⌘, on Mac, or the Settings tab on iOS).
Secrets are stored in the **Keychain**, never in source or `UserDefaults`.

### AI (LLM)

1. Settings → **AI Provider**.
2. Choose Anthropic, OpenAI, or Custom/Local.
3. Enter the model and API key (for Custom, enter the base URL of any
   OpenAI-compatible endpoint, e.g. Ollama at `http://localhost:11434/v1`).
4. Tap **Test Connection**.

### Google Calendar

1. In [Google Cloud Console](https://console.cloud.google.com/): create a
   project, enable the **Google Calendar API**, and create an **OAuth client ID**
   of type **iOS** for bundle id `com.helm.app`.
2. Paste the **Client ID** into Settings → Google Calendar.
3. Open the **Calendar** tab and **Connect Google Calendar**. Auth uses OAuth 2.0
   with PKCE via `ASWebAuthenticationSession`; the redirect is the reversed client
   id and is handled automatically. Tokens are refreshed and stored in the
   Keychain. Scope requested: `calendar.readonly`.

### Granola

Granola keeps a local cache on macOS at
`~/Library/Application Support/Granola/cache-v3.json`.

- **macOS:** Meetings → **Import from Granola**. The app asks you to grant read
  access to the cache once (a security-scoped bookmark is saved). It then parses
  meeting documents and lets you choose which to import; re-imports are
  de-duplicated by Granola's id.
- The cache is an undocumented, evolving format, so the parser is defensive. If
  Granola changes its schema and auto-import comes up empty, use **Add Manually**
  (paste the summary), which is always reliable.
- **iOS/iPadOS:** automatic import isn't available (no access to the Mac's files).
  Add manually, or turn on iCloud sync (below) to see Mac-imported meetings.

## Architecture

```
Helm/
  App/            App entry, root navigation, Info.plist, entitlements
  DesignSystem/   Theme tokens + reusable SwiftUI components
  Models/         SwiftData @Model types (Pipeline, Stage, Deal, Contact, …)
  Persistence/    ModelContainer setup + seed data (the two starter pipelines)
  Services/
    Keychain/     KeychainStore
    LLM/          Provider-agnostic LLMService + Anthropic/OpenAI + AIAssistant
    Calendar/     GoogleAuth (OAuth PKCE) + GoogleCalendarService
    Granola/      GranolaService (cache parser)
    AppSettings   Observable settings (UserDefaults + Keychain)
  Features/       SwiftUI screens (Pipelines, Contacts, Meetings, Calendar,
                  AI, Settings) + shared views
  Resources/      Assets (accent color, app icon slots)
```

- **Persistence:** SwiftData. All models are registered in
  `PersistenceController.schema`.
- **AI:** `LLMService` protocol with `AnthropicService` and `OpenAIService`
  implementations, resolved by `LLMManager` from the active `LLMConfig`.
  `AIAssistant` turns CRM context into prompts.

### Enabling iCloud sync (optional)

To sync between your Mac and iOS devices:

1. Add the **iCloud** capability with **CloudKit** to the target and create a
   container (e.g. `iCloud.com.helm.app`).
2. In `PersistenceController.makeSharedContainer()`, change `cloudKitDatabase:
   .none` to `.automatic`.

It's local-only by default so the project builds and runs with no provisioning.

## Notes & next steps

- The app icon uses placeholder slots — drop in artwork in
  `Resources/Assets.xcassets/AppIcon.appiconset`.
- Ideas to grow into: reminders/notifications for tasks, email logging, richer
  reporting, per-pipeline automations, and CSV import/export.

# Reminder Buddy

A shared reminders app for two people (you and your partner). Both of you see and edit
the same list of tasks, organized into lists/categories, with notes/comments on each task.
You get a notification when the other person **adds a task, updates a task, completes a task,
or adds a note** — plus local reminders for tasks with due dates.

Built with **SwiftUI**, **CloudKit** (shared database), **Sign in with Apple**, and
**push + local notifications**.

---

## Features

- **Shared, real-time data** via CloudKit. One person creates the shared list and invites
  the other; after that you both read/write the same tasks.
- **Sign in with Apple** for identity (so activity is attributed to the right person).
- **Tasks** with title, notes/description, due date, list/category, and assignee.
- **Lists / categories** with colors (e.g. Groceries, Bills, Errands).
- **Notes / comments** on each task — a running thread you both can add to.
- **Complete tasks** and see *who* completed them.
- **Assign** a task to either person.
- **Recurring tasks** (daily / weekly / monthly / yearly) — completing one automatically
  creates its next occurrence with the due date advanced.
- **Upcoming view** that groups incomplete tasks by due date (Overdue, Today, Tomorrow,
  This Week, Later, No Due Date), with a tab badge for items overdue or due today.
- **Calendar view** — a month grid with a dot on every day that has tasks due; swipe or tap
  the chevrons to change months, and tap a day to see and manage that day's reminders.
- **Daily summary notification** — an optional morning rundown of everything due that day,
  at a time you choose.
- **Home Screen widget** — small / medium / large widget showing today's and overdue
  reminders, updated automatically as the shared list changes.
- **Notifications**
  - Activity alerts when your partner adds/updates/completes a task or adds a note.
  - Local due-date reminders for tasks with a due date.

---

## Project structure

```
ReminderBuddy/
├─ ReminderBuddy.xcodeproj/         # Xcode project
└─ ReminderBuddy/
   ├─ ReminderBuddyApp.swift        # App entry + AppDelegate (push & share handling)
   ├─ Info.plist                    # remote-notification background mode, CKSharingSupported
   ├─ ReminderBuddy.entitlements    # iCloud/CloudKit, Push, Sign in with Apple
   ├─ Assets.xcassets/              # App icon + accent color
   ├─ Models/
   │  ├─ Models.swift               # ReminderTask, TaskNote, TaskCategory, AppUser, Recurrence
   │  ├─ DueGroup.swift             # due-date buckets for the Upcoming view
   │  ├─ MonthGrid.swift            # month-grid computation for the Calendar view
   │  └─ CloudKitMapping.swift      # model <-> CKRecord conversion
   ├─ Services/
   │  ├─ CloudKitService.swift          # container/zone/account bootstrap
   │  ├─ CloudKitService+CRUD.swift     # fetch/save/delete + conflict merge
   │  ├─ CloudKitService+Sharing.swift  # CKShare creation/accept + push subscriptions
   │  ├─ AuthManager.swift              # Sign in with Apple
   │  ├─ NotificationManager.swift      # due reminders + activity + daily summary
   │  ├─ SummaryPreferences.swift       # daily-summary on/off + time (persisted)
   │  └─ TaskStore.swift                # app state, notifications, widget snapshot writer
   └─ Views/                         # SwiftUI screens (UpcomingView, CalendarView, …)
Shared/
└─ WidgetSharedData.swift           # snapshot model + App Group store (app + widget)
ReminderBuddyWidget/                # Widget extension target
├─ ReminderBuddyWidgetBundle.swift  # @main widget bundle
├─ ReminderBuddyWidget.swift        # TimelineProvider + widget configuration
├─ ReminderBuddyWidgetViews.swift   # small / medium / large layouts
├─ Info.plist
└─ ReminderBuddyWidget.entitlements # App Group
```

---

## Requirements

- **Xcode 16 or later** (this project was created with Xcode 26.5 and uses the
  synchronized-folder project format).
- A **paid Apple Developer account** ($99/yr). This is required to enable the
  **iCloud/CloudKit**, **Push Notifications**, and **Sign in with Apple** capabilities, and
  to test cross-user push on real devices.
- **Two physical iPhones** signed in to **two different iCloud accounts** (yours and your
  partner's) to actually test sharing + push. CloudKit push does **not** fire on the iOS
  Simulator.

---

## One-time setup in Xcode

1. **Open the project**

   Open `ReminderBuddy/ReminderBuddy.xcodeproj` in Xcode.

2. **Set your Team and bundle identifier**

   - Select the **ReminderBuddy** target → **Signing & Capabilities**.
   - Choose your **Team**.
   - The bundle ID is `com.reminderbuddyjp.app`. If you change it again, also update:
     - The iCloud container in `ReminderBuddy.entitlements` (`iCloud.<your.bundle.id>`),
     - `CloudKitService.containerIdentifier` in `Services/CloudKitService.swift`,
     - The App Group in both `.entitlements` files and `WidgetSharedConstants.appGroup`
       in `Shared/WidgetSharedData.swift`, and
     - The widget bundle ID (`<your.bundle.id>.ReminderBuddyWidget`) in the project settings.

3. **Confirm capabilities** (they're pre-wired in the entitlements file, but verify in
   *Signing & Capabilities*; add any that are missing with the **+ Capability** button):

   - **iCloud** → check **CloudKit**, and make sure the container
     `iCloud.com.reminderbuddyjp.app` (or your renamed one) is selected/created.
   - **Push Notifications**.
   - **Background Modes** → **Remote notifications** (already set in `Info.plist`).
   - **Sign in with Apple**.
   - **App Groups** → `group.com.reminderbuddyjp.app`, enabled on **both** the app target and
     the **ReminderBuddyWidgetExtension** target (this is how the widget reads the data the
     app publishes). If you rename it, update `WidgetSharedConstants.appGroup` in
     `Shared/WidgetSharedData.swift` and both `.entitlements` files to match.

4. **Create the CloudKit schema (record types)**

   The app creates records at runtime, but CloudKit needs the record types and the fields
   to exist in the schema. The simplest path:

   - **Run the app once on a real device** (the development environment auto-creates record
     types from the first saved records), **or**
   - Define them manually in the **CloudKit Console** (https://icloud.developer.apple.com)
     under your container's **Development** environment.

   Record types and fields used by the app:

   | Record Type   | Fields |
   |---------------|--------|
   | `ReminderTask`| `title` (String), `details` (String), `isComplete` (Int64), `dueDate` (Date/Time), `categoryID` (String), `assignedTo` (String), `recurrence` (String), `createdByName` (String), `createdByID` (String), `lastModifiedByName` (String), `completedByName` (String), `createdAt` (Date/Time), `updatedAt` (Date/Time) |
   | `TaskNote`    | `taskID` (String), `body` (String), `authorName` (String), `authorID` (String), `createdAt` (Date/Time) |
   | `Category`    | `name` (String), `colorHex` (String), `sortIndex` (Int64) |

   Sharing uses a **zone-wide `CKShare`** on the `ReminderBuddyZone` custom zone, so the
   entire dataset (categories, tasks, notes) is shared with the partner at once.

   > After testing in Development, use **Deploy Schema to Production** in the CloudKit
   > Console before you ship to the App Store / TestFlight. TestFlight builds use the
   > **Production** CloudKit environment, so the schema must be deployed there first.

5. **Build & run on your iPhone.**

---

## How sharing works (you + your partner)

1. **You** (the list owner) open the app, sign in with Apple, then go to
   **Settings → Invite Your Partner**. This creates a CloudKit share and opens the system
   share sheet. Send the invite via Messages/Mail/etc.
2. **Your partner** taps the invite link on their iPhone (with the app installed). iOS hands
   the share to the app, which accepts it. They now see the **same** tasks, lists, and notes.
3. From then on, any change either of you makes syncs through CloudKit, and the other person
   gets a push that the app turns into a notification (e.g. *"Alex added \"Buy milk\""*).

> Both people must have the app installed. The partner installs it the same way (via
> TestFlight or the App Store once published; during development, install from Xcode).

---

## Notifications: what triggers what

| Event (done by the *other* person) | Notification |
|------------------------------------|--------------|
| Adds a new task                    | "New task added — *Name* added \"Title\"" |
| Updates a task (title/notes/due/list/assignee) | "Task updated — *Name* updated \"Title\"" |
| Completes a task                   | "Task completed — *Name* completed \"Title\"" |
| Adds a note to a task              | "New note — *Name* commented on \"Title\"" |
| A task's due date arrives          | Local reminder "Reminder: Title" (fires for whoever has the app) |

Mechanics: the app registers **CKDatabaseSubscription**s on both the private and shared
databases with silent (`content-available`) pushes. When a push arrives, the app refetches,
diffs against its previous snapshot, and raises a local notification describing the change
made by the *other* user (your own edits never notify you).

---

## Testing notes

- **Use two real devices / two iCloud accounts.** Push and sharing can't be exercised on the
  Simulator.
- If notifications don't appear, check **Settings → Notifications** on the phone and the
  in-app **Settings → Notifications** status row.
- If sync seems stale, pull-to-refresh on the Reminders tab.

---

## Troubleshooting

### `xcodebuild` fails with an `IDESimulatorFoundation` plugin error

If command-line `xcodebuild` prints
`Failed to load code for plug-in com.apple.dt.IDESimulatorFoundation`, your Xcode
command-line components need a repair. This does **not** affect building/running from the
Xcode GUI. To fix the CLI:

```bash
sudo xcodebuild -runFirstLaunch
# If that doesn't resolve it, point xcode-select at your Xcode and retry:
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

(You can always just open the project in Xcode and press Run — the GUI doesn't use that
command-line plugin.)

### "iCloud is not available"

Make sure the device is signed in to iCloud (Settings → your name) and that iCloud Drive is
enabled. The app checks `CKContainer.accountStatus()` on launch.

### Records don't sync / "Did not find record type"

Ensure the CloudKit schema exists (step 4 above) in the same environment (Development for
debug builds) and that both users target the **same** container identifier.

---

## Upcoming view

The **Upcoming** tab (first tab) is the at-a-glance home for what's due. It lists all
*incomplete* tasks grouped into time buckets:

- **Overdue** (red header) — past due, before today
- **Today**
- **Tomorrow**
- **This Week** — within the next 7 days
- **Later** — beyond a week out
- **No Due Date** — toggleable via the options menu

Within each bucket tasks are sorted by due date. Swipe to complete or delete, tap to open
the detail screen, and pull to refresh. The tab shows a **badge** with the number of tasks
that are overdue or due today.

## Calendar view

The **Calendar** tab shows a full month grid. Days with incomplete tasks due get an accent
dot, today is outlined, and the selected day is highlighted. Use the chevrons to move between
months or the **Today** button to jump back. Tapping a day lists that day's reminders below
the grid, where you can swipe to complete/delete or tap through to the detail screen.

## Home Screen widget

Add the **Reminder Buddy** widget from the Home Screen widget gallery. It comes in three
sizes:

- **Small** — a big count of how many reminders are due today, with an overdue tally.
- **Medium** — today's header plus the next few reminders with their times.
- **Large** — the full list of today's and overdue reminders.

How it works: the app writes a small JSON snapshot (overdue + today's incomplete reminders,
capped to 8) into the shared **App Group** container whenever the data changes, then calls
`WidgetCenter.reloadTimelines`. The widget extension reads that snapshot — it never touches
CloudKit directly, which keeps it fast and battery-friendly. The widget also self-refreshes
hourly so the overdue/today split stays current even if the app hasn't run.

Because it relies on the App Group, make sure that capability is enabled on both targets (see
setup step 3). The widget shows sample data in Xcode previews and "All caught up" when nothing
is due.

## Daily summary

In **Settings → Daily Summary**, turn on a once-a-day notification and pick the time (default
8:00 AM). Each morning that has reminders due, you'll get a single notification summarizing
the day ("Due Today — 3 reminders: …").

How it works (local-only, no server): the app pre-schedules individual one-shot
notifications for the next two weeks, each with content computed from the tasks actually due
that day, and rebuilds them whenever tasks change or the summary settings change. Days with
nothing due are skipped, so you only get pinged when there's something to do.

## Recurring tasks

Set a task's **Repeat** option (Daily / Weekly / Monthly / Yearly) in the editor — this is
only available once a due date is set. When that task is marked complete, the app
automatically creates a fresh, incomplete copy whose due date is advanced by one interval,
and schedules a new reminder for it. The completed instance stays as history. Changing the
cadence later notifies your partner as a "Task updated" activity.

## Roadmap ideas

- Custom intervals (e.g. every 2 weeks) and end dates / occurrence counts.
- Reordering / drag-and-drop within a list.
- Lock Screen / accessory widgets and Live Activities for upcoming tasks.
- Interactive widget buttons (tap to complete) via App Intents.
- Per-task push instead of refetch-on-any-change (using `CKQuerySubscription` with alert
  bodies) once record types are deployed to Production.

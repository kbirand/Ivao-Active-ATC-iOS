# Task: add "Contact Support" to this app

You are Claude Code working in the repository of one of Koray Birand's Apple apps (Verz-Apps). This
file is your brief. Read all of it before changing anything.

## The goal

Add a **Contact Support** command to the app. Choosing it opens the Verz-Apps support form in the
user's browser with the app, its version, the device and a support ID already filled in. The user
writes a message and presses Send on the web page. The website then checks the support ID with
Apple, so the developer can see whether the person really has the app.

Two apps already do this and are the reference: Color Lab Pro (Mac) and Color Lab Camera (iPhone).
Their code is in `/Users/koraybirand/Documents/GitHub/Untitled/Color-Science-Lab`:

- `ColorScienceCamera/CameraSubscription.swift` (search for `supportURL`, `supportID`)
- `ColorScienceLab/Store/SubscriptionStore.swift` (same names, the Mac version)

Read them if anything below is unclear. Do not change that repository.

## Where things are

| What | Where |
|---|---|
| Website repo, local (the one to edit) | `/Users/koraybirand/Documents/GitHub/Verz-Apps-Web` (GitHub `kbirand/Verz-Apps-Web`) |
| Production server | `ssh koraybirand@192.168.1.99` |
| Website checkout on the server | `/home/koraybirand/Documents/WebApps/Verz-Apps-Web` |
| Process on the server | pm2 app `verz-apps`, port 3050 |

The local clone can be behind GitHub: run `git pull --ff-only` in it before reading or editing
anything (the support server code in `server/` only exists in recent commits).

Never write the server password into any file, commit or memory. Ask the user for it when it is
needed, or use key-based SSH.

## How it works, and what must stay true

The app does one thing: it builds a link and opens it. Everything else happens on the website.

```
https://verzapps.com/support/?app=<slug>#p=<support-id>&v=<version>&d=<device>
```

| Part | Meaning | Example |
|---|---|---|
| `<slug>` | The app's page name on verzapps.com. Sent to the server as a normal query. | `color-lab-camera` |
| `p` | The support ID (see "The support ID"). Left out when there is none. | `2000000123456789` |
| `v` | App version and build. **Required.** The form is hidden unless `v` is present. | `1.2 (34)` |
| `d` | Device model and system version. | `iPhone17,2, iOS 26.1` |

Rules that are not negotiable:

1. **`p`, `v` and `d` go after the `#`, never in the query.** Browsers do not send the part after
   `#` to any server; the page's own script reads it into the form. This is deliberate.
2. **The app sends nothing by itself.** No network request, no email, no background upload. It only
   opens the link. The user sees every field on the page. The form shows whatever the app filled in
   (support ID, version, device) read-only, so it stays true to the install being asked about; everything else stays editable, and nothing leaves until they press Send.
3. **This is not a purchase link.** Do not add prices, plans or anything about buying to it.
4. **Do not collect anything else**: no name, no email, no logs, no screenshots, no analytics.
5. Percent-encode the part after `#` like a query string (`URLComponents` does this; see the code).
6. Languages: the site has English (no prefix) and `tr`, `es`, `fr`, `de`, `it`
   (`https://verzapps.com/tr/support/?app=…`). Any other language uses English.

## Before you write code: find these four facts

1. **The slug.** Open `content/site.mjs` in the website repo and find this app
   in `order`. That string is the slug. If the app is not there, it has no page on the website yet:
   stop and tell the user, because the form only accepts apps that have a page.
2. **The bundle identifier** of the app as it is on the App Store (`PRODUCT_BUNDLE_IDENTIFIER` of
   the main app target, not an extension or widget).
3. **The product IDs**, if the app sells anything: look for a `.storekit` file, for
   `Product.products(for:)`, or for a list of product identifiers. An app that sells nothing has
   none, and that is fine. A **paid app** (bought up front, no in-app purchases or subscription)
   also has none: its support ID is the app download ID, which proves the purchase.
4. **Where settings live** in this app: a Settings/Preferences screen, an About screen, a Help
   menu. Also how the app is built: SwiftUI, AppKit or UIKit, and its minimum OS version.

If the app is **not distributed through the App Store** (a direct download, a developer-ID build),
it has no App Store records. Still add the command; it will simply send no support ID.

If the target is **watchOS or tvOS only**, stop and tell the user: those cannot open a web page.
Put the command in the companion iPhone app instead if there is one.

## Step 1 — Add the link builder to the app

Add one new file to the main app target. Adjust `slug` and `productIDs`; leave `productIDs` empty
for an app that sells nothing. Follow the project's existing style for file headers and naming.

```swift
import Foundation
import StoreKit

/// The Verz-Apps support form, opened with this app's details filled in. The app sends nothing:
/// it opens the page, and the person sees and sends the form themselves.
enum SupportLink {
    /// The app's page name on verzapps.com.
    static let slug = "my-app"
    /// Every product the app sells; empty for an app with no purchases.
    static let productIDs: [String] = []

    /// The form in the app's language. Everything after the # stays in the browser.
    static func url() async -> URL {
        var items = [URLQueryItem(name: "v", value: appVersion), URLQueryItem(name: "d", value: deviceLine)]
        if let id = await supportID() { items.insert(URLQueryItem(name: "p", value: id), at: 0) }
        var details = URLComponents()
        details.queryItems = items
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        let prefix = ["tr", "es", "fr", "de", "it"].contains(language) ? "/\(language)" : ""
        var url = URLComponents(string: "https://verzapps.com\(prefix)/support/?app=\(slug)")!
        url.percentEncodedFragment = details.percentEncodedQuery
        return url.url!
    }

    /// e.g. "1.2 (34)".
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    /// e.g. "iPhone17,2, iOS 26.1" or "Mac15,9, macOS 26.1".
    static var deviceLine: String {
        #if os(macOS)
        let key = "hw.model", system = "macOS"
        #else
        let key = "hw.machine", system = "iOS"
        #endif
        var size = 0
        sysctlbyname(key, nil, &size, nil, 0)
        var chars = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname(key, &chars, &size, nil, 0)
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(String(cString: chars)), \(system) \(v.majorVersion).\(v.minorVersion)\(v.patchVersion > 0 ? ".\(v.patchVersion)" : "")"
    }

    /// What support checks with Apple; nil in a build run from Xcode, where Apple knows nothing.
    static func supportID() async -> String? {
        // 1. What the person owns now.
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, productIDs.contains(t.productID), t.revocationDate == nil,
               t.environment != .xcode { return String(t.originalID) }
        }
        // 2. Their last purchase, for a subscription that has ended.
        for id in productIDs {
            if case .verified(let last)? = await Transaction.latest(for: id), last.environment != .xcode {
                return String(last.originalID)
            }
        }
        // 3. The app download itself: Apple keeps one for every account that gets the app, free or
        //    paid. `shared` reads what the system already has; it never asks the person to sign in.
        if case .verified(let app)? = try? await AppTransaction.shared, app.environment != .xcode,
           app.appTransactionID.count > 5 { return app.appTransactionID }
        return nil
    }
}
```

Notes on this code:

- **Do not replace `AppTransaction.shared` with `AppTransaction.refresh()`.** `refresh` shows a
  sign-in sheet. `shared` does not.
- `AppTransaction`, `appTransactionID` and `Transaction.environment` each have a minimum system
  version. The two reference apps target recent systems only, so they use them without checks. If
  this app supports older systems, the compiler will report which call is unavailable: wrap that
  part in the `if #available(…)` it asks for and skip it otherwise (return `nil` when step 3 cannot
  run). Do not raise the app's minimum version for this.
- In a build run from Xcode the download ID is `"0"` and purchases come from the local `.storekit`
  file. Apple knows neither, which is why both are skipped. The form also ignores an ID shorter
  than six characters.
- If the app already has a StoreKit manager that keeps the current entitlement, you may read the
  original transaction ID from it for step 1 instead of walking `currentEntitlements` again. Keep
  steps 2 and 3.
- The iPad uses the same code as the iPhone. Mac Catalyst counts as iOS here (`hw.machine`).

## Step 2 — Add the command

Put it where a user looks for help:

- **Settings / Preferences screen**: next to Restore Purchases if the app has one, otherwise in an
  About or Help group.
- **On a Mac, also the Help menu**: "Contact Support…" (with the ellipsis there only).
- Do **not** put it on the purchase screen's row of links; it crowds out Terms and Privacy.

SwiftUI:

```swift
@Environment(\.openURL) private var openURL

Button("Contact Support") {
    Task { openURL(await SupportLink.url()) }
}
```

SwiftUI Help menu on a Mac:

```swift
.commands {
    CommandGroup(after: .help) {
        Button("Contact Support…") {
            Task { NSWorkspace.shared.open(await SupportLink.url()) }
        }
    }
}
```

AppKit: `Task { NSWorkspace.shared.open(await SupportLink.url()) }` from the menu item's action.
UIKit: `Task { await UIApplication.shared.open(await SupportLink.url()) }` from the row's action.

Translate the label if the app is localized. Use exactly these, so the app matches the website's
instructions:

| Language | Label |
|---|---|
| English | Contact Support |
| Turkish | Destekle İletişim |
| Spanish | Contactar con soporte |
| French | Contacter l’assistance |
| German | Support kontaktieren |
| Italian | Contatta l’assistenza |

Add them the way the project already localizes strings (`Localizable.xcstrings`, `.strings`). If
the app is English only, add nothing else.

## Step 3 — Tell the website about the app

This change is in a **different repository**: the website repo (see "Where things are").

In `server/appstore.mjs`, add the app to `BUNDLES` (slug → bundle identifier):

```js
export const BUNDLES = {
  'color-lab-pro': 'com.kbirand.ColorLabPro',
  'color-lab-camera': 'com.kbirand.ColorScienceCamera',
  'my-app': 'com.kbirand.MyApp',          // <- new
};
```

Nothing else changes there. No new key is needed: the App Store key on the server belongs to the
developer account and covers every app in it. Without this entry the form still works and tickets
arrive, but every support ID from the app shows "Not found at Apple".

Then, in that repository, run `npm run build` and `npm run check`; both must pass.

**Commit, push and deploy only when the user asks.** Deploying the website means pushing and then
updating the server; ask the user to do it or to confirm before you do. The server update is:

```bash
ssh koraybirand@192.168.1.99
cd /home/koraybirand/Documents/WebApps/Verz-Apps-Web
git pull && npm ci && npm run build && npm run check && pm2 restart verz-apps
```

The server checkout must never have local edits: change things locally, push, then pull there. Never put passwords, keys
or the server's `.env` values in any file or commit. You do not need them for this task.

## Step 4 — Verify

Do all of these and report what you saw. Do not say "done" on the strength of a successful build.

1. **Build** the app with no new warnings from your code.
2. **Run it** (simulator or Mac) and choose Contact Support. The browser must open the support
   page with the form visible, this app selected, and Version and Device filled in. From an Xcode
   run the Support ID field is empty; that is correct.
3. **Check the link itself**: log or print `await SupportLink.url()` once and confirm
   - `?app=<slug>` is before the `#`,
   - `v=` and `d=` are after the `#` and percent-encoded,
   - there is no `p=` in an Xcode run,
   - the language prefix matches the app's language.
   Remove the logging afterwards.
4. **The website side**: open by hand
   `https://verzapps.com/support/?app=<slug>#v=1.0%20(1)&d=Mac15,9,%20macOS%2026.1`
   and confirm the form appears with the app selected. If the app is missing from the menu, the
   slug is wrong or the app has no page.
5. If the app has tests, run them.

What you cannot verify yourself, say so plainly: a real support ID only appears in a TestFlight or
App Store build, and Apple only answers lookups for an app that has been released at least once
(before that, only TestFlight and sandbox installs can be confirmed).

## What not to do

- Do not send the details from the app with a network request, an email composer or a share sheet.
- Do not move `p`, `v` or `d` into the query string.
- Do not add an email field, a log upload or a screenshot attachment.
- Do not call `AppTransaction.refresh()` or `AppStore.sync()` for this.
- Do not change the app's minimum OS version, its entitlements or its privacy manifest for this.
- Do not edit the Color-Science-Lab repository, and do not change the website beyond the one line
  in `BUNDLES`.
- Do not submit anything to App Store Connect or press "Add for Review".

## App Store review and privacy (for your report, no action needed)

- The command opens a web page the user sends themselves, so nothing is collected by the app.
- The privacy page of every app on verzapps.com already has a "This website" section that says
  what the form stores and that the support ID is checked with Apple.
- For the App Privacy answers in App Store Connect the developer decides; the conservative choice
  is "Customer Support" and "Email Address", not used for tracking. Mention this, do not act on it.

## Report back

End with a short report for the user:

- the slug, bundle identifier and product IDs you used;
- the files you added or changed in the app, and where the command appears;
- the line you added to `BUNDLES`, and that it still needs to be committed and deployed;
- what you verified, with the link you saw, and what could not be verified;
- anything that did not fit this brief (no page on the website, an old minimum OS version, a
  non-App-Store app).

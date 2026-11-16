//
//  SupportLink.swift
//  Ivao Active ATC
//
//  Created by Koray Birand on 16.11.2026.
//

import Foundation
import StoreKit

/// The Verz-Apps support form, opened with this app's details filled in. The app sends nothing:
/// it opens the page, and the person sees and sends the form themselves.
enum SupportLink {
    /// The app's page name on verzapps.com.
    static let slug = "ivao-active-atc"
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

    /// e.g. "iPhone17,2, iOS 26.1".
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

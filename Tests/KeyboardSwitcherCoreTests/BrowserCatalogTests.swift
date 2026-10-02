import Testing
@testable import KeyboardSwitcherCore

struct BrowserCatalogTests {
    @Test("the 18 browsers Input Source Pro reads are listed with their engine", arguments: [
        ("com.apple.Safari", BrowserCatalog.Engine.webkit),
        ("com.apple.SafariTechnologyPreview", .webkit),
        ("com.google.Chrome", .chromium),
        ("org.chromium.Chromium", .chromium),
        ("company.thebrowser.Browser", .chromium),
        ("com.microsoft.edgemac", .chromium),
        ("com.brave.Browser", .chromium),
        ("com.brave.Browser.beta", .chromium),
        ("com.brave.Browser.nightly", .chromium),
        ("com.vivaldi.Vivaldi", .chromium),
        ("com.operasoftware.Opera", .chromium),
        ("org.chromium.Thorium", .chromium),
        ("org.mozilla.firefox", .gecko),
        ("org.mozilla.firefoxdeveloperedition", .gecko),
        ("org.mozilla.nightly", .gecko),
        ("app.zen-browser.zen", .gecko),
        ("company.thebrowser.dia", .chromium),
        ("net.imput.helium", .chromium),
    ])
    func listedBrowser(bundleID: String, engine: BrowserCatalog.Engine) {
        #expect(BrowserCatalog.engine(for: bundleID) == engine)
        #expect(BrowserCatalog.isBrowser(bundleID))
    }

    @Test("the catalog holds those 18 and Aside, and nothing else")
    func catalogSize() {
        #expect(BrowserCatalog.bundleIDs.count == 19)
        #expect(BrowserCatalog.engine(for: "at.studio.AsideBrowser") == .chromium)
    }

    @Test("an app that is not a listed browser is not one", arguments: [
        "com.apple.Terminal", "com.openai.atlas", "com.apple.safari", "",
    ])
    func otherApp(bundleID: String) {
        #expect(BrowserCatalog.engine(for: bundleID) == nil)
        #expect(!BrowserCatalog.isBrowser(bundleID))
        #expect(!BrowserCatalog.isMeasured(bundleID))
    }

    @Test("an app that registers for http or https counts as opening web pages")
    func declaredWebSchemes() {
        let browser: [[String: Any]] = [["CFBundleURLName": "Web", "CFBundleURLSchemes": ["HTTP", "https", "file"]]]
        let mailClient: [[String: Any]] = [["CFBundleURLSchemes": ["mailto"]], ["CFBundleURLName": "no schemes"]]

        #expect(BrowserCatalog.declaresWebSchemes(urlTypes: browser))
        #expect(!BrowserCatalog.declaresWebSchemes(urlTypes: mailClient))
        #expect(!BrowserCatalog.declaresWebSchemes(urlTypes: nil))
        #expect(!BrowserCatalog.declaresWebSchemes(urlTypes: "not an array"))
    }

    @Test("only Safari, Chrome and Aside are measured")
    func measuredBrowsers() {
        #expect(Set(BrowserCatalog.bundleIDs.filter(BrowserCatalog.isMeasured))
            == ["com.apple.Safari", "com.google.Chrome", "at.studio.AsideBrowser"])
    }
}

struct WebAreaPathTests {
    @Test("the outermost web area is picked, so focus in an iframe gives the top page")
    func outermostWebArea() {
        let roles = ["AXTextArea", "AXGroup", "AXWebArea", "AXGroup", "AXWebArea", "AXScrollArea", "AXGroup", "AXWindow"]

        #expect(WebAreaPath.outermostWebArea(rolesFromFocus: roles, reachedTop: true) == 4)
    }

    @Test("focus outside a page has no web area")
    func noWebArea() {
        #expect(WebAreaPath.outermostWebArea(rolesFromFocus: ["AXTextField", "AXToolbar", "AXWindow"], reachedTop: true) == nil)
        #expect(WebAreaPath.outermostWebArea(rolesFromFocus: [], reachedTop: true) == nil)
    }

    @Test("a walk that hit the cap before the window gives nothing, even with a web area seen")
    func capHit() {
        #expect(WebAreaPath.outermostWebArea(rolesFromFocus: ["AXTextArea", "AXWebArea", "AXGroup"], reachedTop: false) == nil)
    }
}

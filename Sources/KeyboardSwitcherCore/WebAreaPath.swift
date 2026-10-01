import Foundation

/// Where the page is on the way up from the focused element of a browser.
public enum WebAreaPath {
    public static let webAreaRole = "AXWebArea"
    /// How many elements the walk from the focused element reads before giving up.
    public static let maxSteps = 64

    /// `rolesFromFocus` starts at the focused element and goes up through its parents. The answer
    /// is the index of the outermost web area, so focus inside an iframe still gives the top page.
    /// Nil without a web area (focus is in the browser's own controls), and nil when the walk
    /// stopped at the cap before the window or the application (`reachedTop` false): the outermost
    /// area seen so far could be an iframe.
    public static func outermostWebArea(rolesFromFocus: [String], reachedTop: Bool) -> Int? {
        guard reachedTop else { return nil }
        return rolesFromFocus.lastIndex(of: webAreaRole)
    }
}

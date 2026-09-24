#if os(macOS)
import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation
import KeyboardSwitcherCore

/// Runs the reliability lab: for every slot, switch the way the user switches, then type into a
/// real third-party text client and read back what came out.
///
/// The text client is TextEdit rather than a window of our own. A freshly focused window inside
/// this process is the client least likely to reproduce a switch that reports success and types
/// latin, which is the whole failure this exists to catch.
struct LabRunner {
    struct SlotResult {
        let slotID: String
        let slotName: String
        let sourceID: String
        let sourceName: String
        let trigger: String
        var verdicts: [LabVerdict] = []
        /// What the system reported after each switch, and what the client received. Context for
        /// a failure: it separates a trigger that was never recognised from one that switched and
        /// still typed latin.
        var notes: [String] = []

        var passed: Bool { !verdicts.isEmpty && verdicts.allSatisfy { $0 == .pass } }
        var isJudged: Bool {
            verdicts.contains { verdict in
                if case .unjudged = verdict { return false }
                return true
            }
        }
    }

    let config: SwitcherConfig
    let attempts: Int
    let settleMs: Int
    /// Empty runs every slot; otherwise only these slot ids, for narrowing a failure down.
    var onlySlots: Set<String> = []
    /// Pause between the baseline check and the trigger. Raising it tells a switch that needs
    /// time to settle apart from one that fails however long you wait.
    var restMs: Int = 0
    /// Ignores the slot's trigger and selects the source directly, which tells a fault in the
    /// event-tap path apart from one in the selection itself.
    var forcesDirect = false
    /// Skips the baseline letter. Only for diagnosing the lab itself: without it an attempt
    /// cannot tell a previous input method still attached to the client from a real failure.
    var skipsBaseline = false
    /// Selects the source once more this many milliseconds after the switch, to test whether a
    /// second selection makes an input method that did not attach the first time attach.
    var reselectMs: Int = 0
    /// Re-activates the client after the switch. macism reports that a selection can stay on the
    /// menu bar without reaching the focused client until something re-activates it.
    var refocuses = false
    /// Sends one key the input method is expected to ignore before the real keys, the way the
    /// Kana prelude does for Google Japanese Input, to see whether that makes it attach.
    var warmupKeyCode: Int = 0
    /// Taps a modifier instead of a plain key as the warm-up: a modifier carries no text and no
    /// meaning in a document, so it is the candidate a real recipe could ship.
    var warmupModifierKeyCode: Int = 0
    /// Leaves the input method under test in its own latin mode before each switch, so the switch
    /// has to bring it back to composing. Measured on a real machine 2026-09-24: azooKey selected
    /// while in alphanumeric mode typed latin, and a lab that never set that state missed it.
    var leavesLatinMode = false
    let service = MacInputSourceService()
    private let textEditID = "com.apple.TextEdit"
    private let baselineID = "com.apple.keylayout.ABC"
    private let eventSource = CGEventSource(stateID: .hidSystemState)

    func run(json: Bool) throws {
        guard AXIsProcessTrusted() else {
            fputs(
                "error: the lab types into TextEdit and reads the text back, which needs Accessibility.\n"
                    + "Grant it to the program running keyboardctl in System Settings > Privacy & Security > Accessibility.\n",
                stderr
            )
            exit(6)
        }
        let sources = try service.listInputSources()
        let originalSource = try? service.currentInputSource()
        defer { if let originalSource { _ = try? service.selectInputSource(id: originalSource.id) } }

        let document = try openScratchDocument()
        defer { try? FileManager.default.removeItem(at: document) }

        var results: [SlotResult] = []
        for slot in config.slots {
            guard onlySlots.isEmpty || onlySlots.contains(slot.id.rawValue) else { continue }
            guard let source = InputSourceMatcher.bestMatch(for: slot.id, sources: sources, config: config) else {
                continue
            }
            let trigger = forcesDirect ? nil : config.bindings.first {
                $0.enabled && $0.action.type == .switchInputSource && $0.action.role == slot.id
                    && $0.trigger.kind == .oneShotModifier
            }
            var result = SlotResult(
                slotID: slot.id.rawValue,
                slotName: slot.name,
                sourceID: source.id,
                sourceName: source.localizedName,
                trigger: trigger?.trigger.displayName ?? "direct selection"
            )
            let expectation = LabExpectation.forSource(id: source.id)
            for _ in 0..<attempts {
                // A void attempt says something about the run, not about the slot, so it is
                // repeated rather than counted.
                var verdict = LabVerdict.void(reason: "not run")
                var note = ""
                for _ in 0..<3 {
                    (verdict, note) = attempt(source: source, trigger: trigger?.trigger, expectation: expectation)
                    if case .void = verdict { continue }
                    break
                }
                result.verdicts.append(verdict)
                result.notes.append(note)
            }
            results.append(result)
        }
        report(results, json: json)
    }

    // MARK: - One attempt

    private func attempt(
        source: InputSourceInfo,
        trigger: KeyTrigger?,
        expectation: LabExpectation?
    ) -> (LabVerdict, String) {
        clearDocument()
        let textBefore = readText()

        // The previous input method can stay attached to the client after a switch; typing one
        // letter in a plain layout first tells that apart from a failure of the slot under test.
        var baseline = "n"
        if leavesLatinMode, let mode = LabLatinMode.forSource(id: source.id) {
            if let refusal = enterLatinMode(mode, of: source) { return (.void(reason: refusal), refusal) }
        }
        // The switch away happens either way: without it the next attempt would select a source
        // that is already current and pass without ever switching.
        if skipsBaseline {
            key(53)
            selectFromAnotherProcess(baselineID)
            settle(max(settleMs, 400))
        }
        if !skipsBaseline {
            // Escape first: a composition left pending by the previous attempt would otherwise
            // take the baseline keystroke, and the input method it belongs to would still be
            // attached when we typed. That looked exactly like the failure this lab hunts.
            key(53)
            selectFromAnotherProcess(baselineID)
            settle(max(settleMs, 400))
            key(45)
            baseline = readStableText()
            clearDocument()
        }
        // Let the client finish with the keys just sent before switching. Measured 2026-09-20:
        // switching 80 ms after clearing the document made WeType take the replayed letters as
        // latin in 8 of 10 attempts, while 200 ms passed 10 of 10. Without this wait the lab
        // manufactures the failure it is looking for and blames the input method for it.
        settle(Self.quietBeforeSwitchMs)

        if restMs > 0 { settle(restMs) }
        if let trigger {
            fire(trigger)
        } else {
            selectDirectly(source)
        }
        settle(settleMs)
        if warmupModifierKeyCode > 0 {
            tapModifier(CGKeyCode(warmupModifierKeyCode), flag: Self.modifierFlag(forKeyCode: warmupModifierKeyCode))
            settle(200)
        }
        if warmupKeyCode > 0 {
            key(CGKeyCode(warmupKeyCode))
            settle(200)
        }
        if refocuses, let app = NSRunningApplication.runningApplications(withBundleIdentifier: textEditID).first {
            app.activate(options: [])
            settle(200)
        }
        if reselectMs > 0 {
            selectFromAnotherProcess(source.id)
            settle(reselectMs)
        }
        let reported = try? service.currentInputSource()

        guard let expectation else {
            let observation = LabObservation(
                textBefore: textBefore, baselineText: baseline, text: "", reportedSourceID: reported?.id
            )
            return (LabJudge.judge(observation, expectation: nil), "reported \(reported?.id ?? "nothing")")
        }
        for code in expectation.keyCodes {
            key(CGKeyCode(code))
            settle(110)
        }
        if let commit = expectation.commitKeyCode {
            settle(450)
            key(CGKeyCode(commit))
        }
        let text = readStableText()
        clearDocument()
        let observation = LabObservation(
            textBefore: textBefore,
            baselineText: baseline,
            text: text,
            reportedSourceID: reported?.id
        )
        let note = "reported \(reported?.id ?? "nothing"), typed \(text.trimmingCharacters(in: .whitespacesAndNewlines))"
        return (LabJudge.judge(observation, expectation: expectation), note)
    }

    /// Selects `source`, sends its latin-mode key and checks with a probe that the mode took.
    /// Returns why not when it did not, which voids the attempt rather than failing the switch.
    private func enterLatinMode(_ mode: LabLatinMode, of source: InputSourceInfo) -> String? {
        key(53)
        selectFromAnotherProcess(source.id)
        settle(max(settleMs, 400))
        if mode.isModifier {
            tapModifier(CGKeyCode(mode.keyCode), flag: Self.modifierFlag(forKeyCode: mode.keyCode))
        } else {
            key(CGKeyCode(mode.keyCode))
        }
        settle(200)
        clearDocument()
        for code in LabLatinMode.probeKeyCodes {
            key(CGKeyCode(code))
            settle(110)
        }
        let probe = readStableText()
        clearDocument()
        guard LabLatinMode.holds(probeText: probe) else {
            return "could not leave \(source.localizedName) in latin mode first (probe typed \"\(probe)\"); "
                + "if its latin-mode key is switched off in its own settings, this case cannot happen to you"
        }
        return nil
    }

    /// Selects from a short-lived child process rather than this one.
    ///
    /// Measured 2026-09-20: when the process that then synthesises the keystrokes is also the one
    /// that called TISSelectInputSource, WeType took every letter as committed latin (3 of 3),
    /// while the same selection made by a separate process composed every time (3 of 3). A lab
    /// that selected in-process would therefore report a failure of its own making.
    private func selectFromAnotherProcess(_ id: String) {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["source", id, "--quiet"]
        try? child.run()
        child.waitUntilExit()
    }

    private func selectDirectly(_ source: InputSourceInfo) {
        SwitchActivationPolicy.selectWithKanaPrelude(
            target: source,
            current: { try? service.currentInputSource() },
            userRecipes: ActivationRecipeStore().load().recipes,
            postKana: EventTapMonitor.postKanaKeyEvent,
            wait: { delay, then in
                RunLoop.current.run(until: Date(timeIntervalSinceNow: delay))
                then()
            },
            select: {}
        )
        selectFromAnotherProcess(source.id)
    }

    /// Fires the user's own trigger, unmarked, so CmdIME's event tap treats it as a real key press.
    private func fire(_ trigger: KeyTrigger) {
        let code = CGKeyCode(trigger.keyCode)
        let flag = Self.modifierFlag(forKeyCode: trigger.keyCode)
        tapModifier(code, flag: flag)
        if trigger.gesture == .doubleTap {
            // Inside the double-tap window, or the second tap reads as another single tap.
            settle(80)
            tapModifier(code, flag: flag)
        }
    }

    private static func modifierFlag(forKeyCode keyCode: Int) -> CGEventFlags {
        switch keyCode {
        case 54, 55: .maskCommand
        case 56, 60: .maskShift
        case 58, 61: .maskAlternate
        case 59, 62: .maskControl
        default: []
        }
    }

    // MARK: - Driving TextEdit

    private func openScratchDocument() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cmd-ime-lab.txt")
        try "".write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(url)
        for _ in 0..<40 {
            settle(100)
            if frontmostBundleID() == textEditID { return url }
        }
        fputs("error: TextEdit did not come to the front, so nothing was typed.\n", stderr)
        exit(7)
    }

    private func frontmostBundleID() -> String? {
        // NSWorkspace refreshes through the run loop; a CLI that never pumps it reads a stale value.
        CFRunLoopRunInMode(.defaultMode, 0.02, false)
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    /// Every key is guarded: the user can click away at any moment, and this must never type
    /// into whatever they clicked on.
    private func guardFront() {
        guard frontmostBundleID() == textEditID else {
            fputs("error: TextEdit lost focus, so the run stopped.\n", stderr)
            exit(8)
        }
    }

    private func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
        guardFront()
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: eventSource, virtualKey: code, keyDown: down)!
            event.flags = flags
            event.post(tap: .cghidEventTap)
            settle(30)
        }
    }

    private func tapModifier(_ code: CGKeyCode, flag: CGEventFlags) {
        guardFront()
        let down = CGEvent(keyboardEventSource: eventSource, virtualKey: code, keyDown: true)!
        down.type = .flagsChanged
        down.flags = flag
        down.post(tap: .cghidEventTap)
        settle(60)
        let up = CGEvent(keyboardEventSource: eventSource, virtualKey: code, keyDown: false)!
        up.type = .flagsChanged
        up.flags = []
        up.post(tap: .cghidEventTap)
    }

    /// How long the client is left alone between the last keystroke and the switch.
    static let quietBeforeSwitchMs = 200

    private func clearDocument() {
        key(0, flags: .maskCommand)  // Command+A
        settle(80)
        key(51)                      // Delete
        settle(80)
    }

    /// Reads until the text stops changing. An input method with inline preedit, Squirrel for one,
    /// shows the pinyin in the client while it composes; reading once, too early, catches that raw
    /// latin and looks exactly like the failure this lab is meant to catch.
    private func readStableText(timeoutMs: Int = 2000) -> String {
        var previous = readText()
        var stableFor = 0
        var waited = 0
        while waited < timeoutMs {
            settle(120)
            waited += 120
            let current = readText()
            if current == previous {
                stableFor += 120
                if stableFor >= 360, !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return current
                }
            } else {
                stableFor = 0
                previous = current
            }
        }
        return previous
    }

    private func readText() -> String {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: textEditID).first else {
            return ""
        }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { return "" }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXValueAttribute as CFString, &value) == .success
        else { return "" }
        return value as? String ?? ""
    }

    private func settle(_ milliseconds: Int) {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: Double(milliseconds) / 1000))
    }

    // MARK: - Report

    private func report(_ results: [SlotResult], json: Bool) {
        let judged = results.filter(\.isJudged)
        let passed = judged.filter(\.passed)
        if json {
            let payload: [String: Any] = [
                "client": "TextEdit",
                "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
                "attemptsPerSlot": attempts,
                "passed": passed.count,
                "judged": judged.count,
                "slots": results.map { result in
                    [
                        "slot": result.slotID,
                        "name": result.slotName,
                        "sourceID": result.sourceID,
                        "trigger": result.trigger,
                        "verdicts": result.verdicts.map(Self.describe),
                        "run": result.verdicts.map(Self.mark).joined(),
                        "attempts": LabRunShape(verdicts: result.verdicts).attempts,
                        "failures": LabRunShape(verdicts: result.verdicts).failures,
                        "longestFailureStreak": LabRunShape(verdicts: result.verdicts).longestFailureStreak,
                        "longestPassStreak": LabRunShape(verdicts: result.verdicts).longestPassStreak,
                        "shape": LabRunShape(verdicts: result.verdicts).clustering.summary,
                        "notes": result.notes,
                    ]
                },
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
                print(String(decoding: data, as: UTF8.self))
            }
            return
        }
        // The client is part of the claim: a number without it is not one we could defend.
        print("\(passed.count) of \(judged.count) slots produce the right language in TextEdit")
        print("macOS \(ProcessInfo.processInfo.operatingSystemVersionString), \(attempts) attempts per slot\n")
        for result in results {
            let shape = LabRunShape(verdicts: result.verdicts)
            print("  \(result.slotName)  [\(result.sourceName)]  via \(result.trigger)")
            // The run as a picture: where the failures sit matters as much as how many there are.
            print("    \(result.verdicts.map(Self.mark).joined())")
            print("    \(shape.summary)")
            for (index, note) in result.notes.enumerated() where result.verdicts[index] != .pass {
                print("      attempt \(index + 1): \(note)")
            }
            if case let .fail(failure) = result.verdicts.first(where: { if case .fail = $0 { return true } else { return false } }),
               let known = LabKnownIssue.note(sourceID: result.sourceID, failure: failure) {
                print("      \(known)")
            }
        }
    }

    /// One character per attempt, so a thirty-attempt run reads at a glance.
    private static func mark(_ verdict: LabVerdict) -> String {
        switch verdict {
        case .pass: "."
        case .fail: "x"
        case .unjudged: "?"
        case .void: "-"
        }
    }

    private static func describe(_ verdict: LabVerdict) -> String {
        switch verdict {
        case .pass: "pass"
        case let .fail(failure): "FAIL: \(failure.message)"
        case let .unjudged(reason): "not judged: \(reason)"
        case let .void(reason): "void: \(reason)"
        }
    }
}
#endif

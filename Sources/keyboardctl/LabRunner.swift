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
            guard let source = InputSourceMatcher.bestMatch(for: slot.id, sources: sources, config: config) else {
                continue
            }
            let trigger = config.bindings.first {
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
                result.verdicts.append(attempt(source: source, trigger: trigger?.trigger, expectation: expectation))
            }
            results.append(result)
        }
        report(results, json: json)
    }

    // MARK: - One attempt

    private func attempt(source: InputSourceInfo, trigger: KeyTrigger?, expectation: LabExpectation?) -> LabVerdict {
        clearDocument()
        let textBefore = readText()

        // The previous input method can stay attached to the client after a switch; typing one
        // letter in a plain layout first tells that apart from a failure of the slot under test.
        _ = try? service.selectInputSource(id: baselineID)
        settle(300)
        key(45)
        settle(200)
        let baseline = readText()
        clearDocument()

        if let trigger {
            fire(trigger)
        } else {
            selectDirectly(source)
        }
        settle(settleMs)
        let reported = try? service.currentInputSource()

        guard let expectation else {
            return LabJudge.judge(
                LabObservation(textBefore: textBefore, baselineText: baseline, text: "", reportedSourceID: reported?.id),
                expectation: nil
            )
        }
        for code in expectation.keyCodes {
            key(CGKeyCode(code))
            settle(110)
        }
        if let commit = expectation.commitKeyCode {
            settle(450)
            key(CGKeyCode(commit))
        }
        settle(400)
        let text = readText()
        clearDocument()
        return LabJudge.judge(
            LabObservation(
                textBefore: textBefore,
                baselineText: baseline,
                text: text,
                reportedSourceID: reported?.id
            ),
            expectation: expectation
        )
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
        _ = try? service.selectInputSource(id: source.id)
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

    private func clearDocument() {
        key(0, flags: .maskCommand)  // Command+A
        settle(80)
        key(51)                      // Delete
        settle(80)
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
            let detail = result.verdicts.map(Self.describe).joined(separator: ", ")
            print("  \(result.slotName)  [\(result.sourceName)]  via \(result.trigger)")
            print("    \(detail)")
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

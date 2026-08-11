import AppKit
import ApplicationServices
import Foundation

private let stopKeyCode: Int64 = 53 // Escape on Apple keyboards.

private struct Configuration {
    var repetitions: Int?
    var countdown = 3
    var pauseBetweenRepetitions = 0.5

    static func parse(_ arguments: [String]) throws -> Configuration {
        var result = Configuration()
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "-n", "--count":
                index += 1
                guard index < arguments.count,
                      let value = Int(arguments[index]),
                      (1...10_000).contains(value) else {
                    throw CLIError("--count must be an integer from 1 through 10000")
                }
                result.repetitions = value

            case "--countdown":
                index += 1
                guard index < arguments.count,
                      let value = Int(arguments[index]),
                      (0...30).contains(value) else {
                    throw CLIError("--countdown must be an integer from 0 through 30")
                }
                result.countdown = value

            case "--pause":
                index += 1
                guard index < arguments.count,
                      let value = Double(arguments[index]),
                      (0...60).contains(value) else {
                    throw CLIError("--pause must be a number from 0 through 60")
                }
                result.pauseBetweenRepetitions = value

            case "-h", "--help":
                printUsage()
                exit(EXIT_SUCCESS)

            default:
                throw CLIError("unknown option: \(arguments[index])")
            }
            index += 1
        }

        return result
    }
}

private struct CLIError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private struct RecordedEvent {
    let offset: TimeInterval
    let event: CGEvent
}

private final class EventRecorder {
    private enum Mode {
        case idle
        case recording
        case replaying
    }

    private var mode = Mode.idle
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var recordingStart: TimeInterval = 0
    private(set) var events: [RecordedEvent] = []
    private(set) var stopRequested = false

    init() throws {
        let types: [CGEventType] = [
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .keyDown, .keyUp, .flagsChanged, .scrollWheel
        ]
        let mask = types.reduce(CGEventMask(0)) { mask, type in
            mask | (CGEventMask(1) << CGEventMask(type.rawValue))
        }

        let opaqueSelf = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let recorder = Unmanaged<EventRecorder>
                    .fromOpaque(userInfo)
                    .takeUnretainedValue()
                return recorder.receive(type: type, event: event)
            },
            userInfo: opaqueSelf
        ) else {
            throw CLIError(
                "macOS refused to create an input event tap. Grant Accessibility " +
                "permission to Terminal (or the app that launched this tool), then run it again."
            )
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    deinit {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
        }
    }

    func record() {
        events.removeAll(keepingCapacity: true)
        stopRequested = false
        recordingStart = ProcessInfo.processInfo.systemUptime
        mode = .recording
        CFRunLoopRun()
        mode = .idle
    }

    func replay(repetitions: Int, pause: TimeInterval) {
        stopRequested = false
        mode = .replaying
        var pressedKeys = Set<CGKeyCode>()
        var leftMouseDown = false
        var rightMouseDown = false
        var lastMouseLocation = CGEvent(source: nil)?.location ?? .zero

        defer {
            releaseHeldInputs(
                keys: pressedKeys,
                leftMouseDown: leftMouseDown,
                rightMouseDown: rightMouseDown,
                mouseLocation: lastMouseLocation
            )
            mode = .idle
        }

        for repetition in 1...repetitions {
            if stopRequested { break }
            print("Replaying \(repetition)/\(repetitions)…")
            let start = ProcessInfo.processInfo.systemUptime

            for item in events {
                waitUntil(start + item.offset)
                if stopRequested { break }

                guard let eventCopy = item.event.copy() else { continue }
                let keyCode = CGKeyCode(
                    eventCopy.getIntegerValueField(.keyboardEventKeycode)
                )
                switch eventCopy.type {
                case .keyDown:
                    pressedKeys.insert(keyCode)
                case .keyUp:
                    pressedKeys.remove(keyCode)
                case .leftMouseDown:
                    leftMouseDown = true
                    lastMouseLocation = eventCopy.location
                case .leftMouseUp:
                    leftMouseDown = false
                    lastMouseLocation = eventCopy.location
                case .rightMouseDown:
                    rightMouseDown = true
                    lastMouseLocation = eventCopy.location
                case .rightMouseUp:
                    rightMouseDown = false
                    lastMouseLocation = eventCopy.location
                case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
                    lastMouseLocation = eventCopy.location
                default:
                    break
                }
                eventCopy.timestamp = CGEventTimestamp(mach_absolute_time())
                eventCopy.post(tap: .cghidEventTap)
            }

            if repetition < repetitions && !stopRequested {
                waitFor(pause)
            }
        }

    }

    private func releaseHeldInputs(
        keys: Set<CGKeyCode>,
        leftMouseDown: Bool,
        rightMouseDown: Bool,
        mouseLocation: CGPoint
    ) {
        for key in keys {
            CGEvent(
                keyboardEventSource: nil,
                virtualKey: key,
                keyDown: false
            )?.post(tap: .cghidEventTap)
        }

        if leftMouseDown {
            CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseUp,
                mouseCursorPosition: mouseLocation,
                mouseButton: .left
            )?.post(tap: .cghidEventTap)
        }
        if rightMouseDown {
            CGEvent(
                mouseEventSource: nil,
                mouseType: .rightMouseUp,
                mouseCursorPosition: mouseLocation,
                mouseButton: .right
            )?.post(tap: .cghidEventTap)
        }
    }

    private func receive(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let isStopKey = type == .keyDown &&
            event.getIntegerValueField(.keyboardEventKeycode) == stopKeyCode

        if isStopKey && mode != .idle {
            stopRequested = true
            CFRunLoopStop(CFRunLoopGetMain())
            return nil // Do not send the control key to Roblox.
        }

        if mode == .recording, let eventCopy = event.copy() {
            let offset = ProcessInfo.processInfo.systemUptime - recordingStart
            events.append(RecordedEvent(offset: offset, event: eventCopy))
        }

        return Unmanaged.passUnretained(event)
    }

    private func waitUntil(_ deadline: TimeInterval) {
        while !stopRequested {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            if remaining <= 0 { return }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: min(remaining, 0.01)))
        }
    }

    private func waitFor(_ duration: TimeInterval) {
        waitUntil(ProcessInfo.processInfo.systemUptime + duration)
    }
}

private func printUsage() {
    print(
        """
        Usage: roblox-replay [options]

          -n, --count NUMBER   Number of times to replay (prompted if omitted)
              --countdown SEC  Seconds before recording begins (default: 3)
              --pause SEC      Pause between repetitions (default: 0.5)
          -h, --help            Show this help

        Roblox is activated before recording. Perform the mouse/keyboard movement,
        then press Escape to stop recording. Press Escape again for an emergency stop while
        the replay is running.
        """
    )
}

private func repetitions(from configuredValue: Int?) throws -> Int {
    if let configuredValue { return configuredValue }

    print("How many times should the recording repeat? ", terminator: "")
    guard let line = readLine(),
          let value = Int(line.trimmingCharacters(in: .whitespacesAndNewlines)),
          (1...10_000).contains(value) else {
        throw CLIError("repeat count must be an integer from 1 through 10000")
    }
    return value
}

private func ensureAccessibilityPermission() throws {
    let options = [
        kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
    ] as CFDictionary

    guard AXIsProcessTrustedWithOptions(options) else {
        throw CLIError(
            "Accessibility permission is required. In System Settings, open " +
            "Privacy & Security > Accessibility, enable Terminal (or your launcher), " +
            "then quit and rerun this tool."
        )
    }
}

@discardableResult
private func activateRoblox() -> Bool {
    let bundleIdentifiers = ["com.roblox.Roblox", "com.roblox.RobloxPlayer"]

    func runningRoblox() -> NSRunningApplication? {
        for identifier in bundleIdentifiers {
            if let app = NSRunningApplication
                .runningApplications(withBundleIdentifier: identifier)
                .first {
                return app
            }
        }

        return NSWorkspace.shared.runningApplications.first { application in
            guard application.activationPolicy == .regular else { return false }
            return application.localizedName?.localizedCaseInsensitiveContains("roblox") == true
        }
    }

    if let app = runningRoblox() {
        return app.activate(options: [.activateAllWindows])
    }

    let candidatePaths = [
        "/Applications/Roblox.app",
        NSString(string: "~/Applications/Roblox.app").expandingTildeInPath
    ]

    if let path = candidatePaths.first(where: FileManager.default.fileExists(atPath:)),
       NSWorkspace.shared.open(URL(fileURLWithPath: path)) {
        let deadline = Date(timeIntervalSinceNow: 15)
        while Date() < deadline {
            if let app = runningRoblox() {
                return app.activate(options: [.activateAllWindows])
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        }
    }

    return false
}

private func countdown(seconds: Int) {
    guard seconds > 0 else { return }
    for remaining in stride(from: seconds, through: 1, by: -1) {
        print("Recording starts in \(remaining)…")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1))
    }
}

do {
    let configuration = try Configuration.parse(Array(CommandLine.arguments.dropFirst()))
    let count = try repetitions(from: configuration.repetitions)
    try ensureAccessibilityPermission()

    guard activateRoblox() else {
        throw CLIError(
            "Roblox is not running and Roblox.app could not be opened from /Applications. " +
            "Start Roblox, then try again."
        )
    }

    let recorder = try EventRecorder()
    countdown(seconds: configuration.countdown)
    print("RECORDING — perform the movement now. Press Escape when finished.")
    recorder.record()

    guard !recorder.events.isEmpty else {
        throw CLIError("nothing was recorded")
    }

    print("Captured \(recorder.events.count) input events.")
    guard activateRoblox() else {
        throw CLIError("Roblox closed before replay could begin")
    }
    print("Replay begins in 2 seconds. Press Escape at any time to stop.")
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 2))
    recorder.replay(
        repetitions: count,
        pause: configuration.pauseBetweenRepetitions
    )

    print(recorder.stopRequested ? "Stopped." : "Finished.")
} catch {
    fputs("Error: \(error)\n", stderr)
    fputs("Run with --help for usage.\n", stderr)
    exit(EXIT_FAILURE)
}

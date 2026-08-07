#!/usr/bin/env swift
// HID-level key injector for the Dolphin chassis (Quartz keyboard backend polls
// CGEventSourceKeyState(HIDSystemState), which AppleScript keystrokes don't hit).
//
// Usage: swift scripts/hidkey.swift <key-code> [hold-ms] [repeat]
//   key-code: macOS virtual key code (49=space, 36=return, 123/124/125/126=arrows)
//   hold-ms : default 120
//   repeat  : default 1
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 2, let code = CGKeyCode(args[1]) else {
    FileHandle.standardError.write("usage: hidkey.swift <key-code> [hold-ms] [repeat]\n".data(using: .utf8)!)
    exit(2)
}
let holdMs = args.count > 2 ? Int(args[2]) ?? 120 : 120
let reps = args.count > 3 ? Int(args[3]) ?? 1 : 1

for _ in 0..<reps {
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else {
        exit(3)
    }
    down.post(tap: .cghidEventTap)
    usleep(useconds_t(holdMs) * 1000)
    up.post(tap: .cghidEventTap)
    if reps > 1 { usleep(60_000) }
}

# Split Container Sidebar Redesign — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Redesign the sidebar split-session container to match Figma node 2133:8955 — dual stone-colored inset cells with no divider.

**Architecture:** Single function edit in ContentView.swift. Replace the inner HStack layout of `splitSessionContainer()` (lines 1893-1920) with two background-filled cells separated by a 4px gap. Remove WavyDividerVertical usage. Keep outer container, shadow, button logic, and context menu untouched.

**Tech Stack:** SwiftUI, forced-appearance colors (no asset catalog — this container is theme-independent by design)

---

### Task 1: Redesign splitSessionContainer inner layout

**Files:**
- Modify: `Jot/App/ContentView.swift:1893-1921` (inner HStack only)

**Step 1: Replace the inner HStack layout**

Replace lines 1893-1920 (the `HStack(spacing: 8) { ... }` block inside the button label) with:

```swift
HStack(spacing: 4) {
    Text(primaryTitle)
        .font(.system(size: 15, weight: .medium))
        .tracking(-0.5)
        .foregroundColor(.black)
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 231/255, green: 229/255, blue: 228/255))
        )

    Text(secondaryTitle)
        .font(.system(size: 15, weight: .medium))
        .tracking(-0.5)
        .foregroundColor(.black)
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 231/255, green: 229/255, blue: 228/255))
        )
}
```

**Step 2: Build and verify**

Run: `xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Launch and visually verify**

Run:
```bash
pkill -x Jot 2>/dev/null
touch ~/Library/Developer/Xcode/DerivedData/Jot-cphhgkbodyxgypfrmhzapcjwyeot/Build/Products/Debug/Jot.app
killall iconservicesagent 2>/dev/null || true
sleep 1 && open ~/Library/Developer/Xcode/DerivedData/Jot-cphhgkbodyxgypfrmhzapcjwyeot/Build/Products/Debug/Jot.app
```

Verify: Split session containers in sidebar show two stone-colored rounded cells with 4px gap, no wavy divider, outer shadow preserved.

**Step 4: Commit**

```bash
git add Jot/App/ContentView.swift
git commit -m "refactor: redesign split-container sidebar to dual inset cells"
```

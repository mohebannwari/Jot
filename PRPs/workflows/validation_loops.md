# Validation Loops Workflow

This workflow describes how AI assistants use self-correcting validation loops to ensure implementations work correctly without human intervention.

## Overview

Validation loops are the key to autonomous AI coding:
- AI implements a feature
- AI validates implementation
- If validation fails, AI fixes issues
- Loop continues until validation succeeds

This enables AI to deliver working code on the first try.

## Core Concept

```
┌─────────────────────────────────────┐
│  Implement Feature                  │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  Run Validation                     │
│  - Build                            │
│  - Tests                            │
│  - Linting                          │
└──────────────┬──────────────────────┘
               │
               ▼
         ┌─────┴─────┐
         │  Success? │
         └─────┬─────┘
               │
        ┌──────┴──────┐
        │             │
       YES            NO
        │             │
        ▼             ▼
    ┌───────┐   ┌─────────────┐
    │ Done  │   │ Analyze     │
    └───────┘   │ Error       │
                └──────┬──────┘
                       │
                       ▼
                ┌────────────────┐
                │ Fix Issues     │
                └────────┬───────┘
                         │
                         │ Loop back
                         └────────────┐
                                      │
                                      ▼
                            (Return to Validation)
```

## Validation Types

### 1. Build Validation

**Purpose:** Ensure code compiles without errors

**Command:**
```bash
xcodebuild -project Noty.xcodeproj -scheme Noty -configuration Debug build
```

**Success Criteria:**
- Exit code 0
- No compilation errors
- No fatal warnings

**Common Failures:**
- Missing imports
- Type mismatches
- Undefined symbols
- Syntax errors
- Missing files in project

**Fix Strategy:**
1. Read build output carefully
2. Identify first error (others may cascade)
3. Locate file and line number
4. Understand error message
5. Fix root cause
6. Re-run build

### 2. Test Validation

**Purpose:** Ensure functionality works correctly

**Commands:**
```bash
# Run all tests
xcodebuild -project Noty.xcodeproj -scheme Noty \
  -destination 'platform=macOS' test

# Run specific test class
xcodebuild -project Noty.xcodeproj -scheme Noty \
  -destination 'platform=macOS' \
  -only-testing:NotyTests/FeatureTests test

# Run specific test method
xcodebuild -project Noty.xcodeproj -scheme Noty \
  -destination 'platform=macOS' \
  -only-testing:NotyTests/FeatureTests/testSpecificBehavior test
```

**Success Criteria:**
- All tests pass
- No test failures
- No unexpected exceptions

**Common Failures:**
- Logic bugs in implementation
- Incorrect test expectations
- Missing test setup
- Resource cleanup issues
- Race conditions

**Fix Strategy:**
1. Identify which test failed
2. Read failure message and expected vs actual
3. Locate bug in implementation
4. Fix implementation
5. Verify test passes
6. Check for regressions in other tests

### 3. Lint Validation

**Purpose:** Ensure code follows style guidelines

**Command:**
```swift
// In Cursor, use:
read_lints([file_path])
```

**Success Criteria:**
- No linter errors
- No linter warnings
- Code follows conventions

**Common Failures:**
- Style violations
- Unused variables
- Missing documentation
- Code complexity
- Formatting issues

**Fix Strategy:**
1. Read linter output
2. Address errors first, then warnings
3. Follow project style guide
4. Re-check linting
5. Iterate until clean

### 4. Manual Validation

**Purpose:** Verify user-facing behavior

**Process:**
1. Run the app
2. Navigate to feature
3. Interact with UI
4. Verify expected behavior
5. Test edge cases

**Success Criteria:**
- Feature works as specified
- UI appears correct
- Interactions feel smooth
- Edge cases handled

**Common Issues:**
- Visual glitches
- Missing animations
- Incorrect state updates
- Poor performance

**Fix Strategy:**
1. Document specific issue
2. Locate relevant code
3. Fix problem
4. Re-test manually
5. Verify fix works

## Validation Loop Patterns

### Pattern 1: Single Validation

For simple implementations:

```
Implement → Validate → Done
```

**Example:**
- Add simple computed property
- Run build
- Success → Done

### Pattern 2: Iterative Validation

For implementations with issues:

```
Implement → Validate → Fix → Validate → Fix → Validate → Done
```

**Example:**
- Create new component
- Run build → Type error
- Fix type error
- Run build → Import missing
- Add import
- Run build → Success
- Run tests → Success
- Done

### Pattern 3: Multi-Stage Validation

For complex features:

```
Implement Step 1 → Validate → 
Implement Step 2 → Validate →
Implement Step 3 → Validate →
Integration → Validate → Done
```

**Example:**
- Create manager → Build + Tests pass
- Create UI component → Build + Preview works
- Integrate → Build + Tests + Manual test
- All succeed → Done

### Pattern 4: Parallel Validation

For independent components:

```
        Implement A → Validate A
Implement B → Validate B    } In parallel
        Implement C → Validate C
                ↓
        Integrate ABC → Validate → Done
```

## Error Analysis Strategies

### Strategy 1: Read Carefully

Most errors have clear messages:

```
error: cannot find 'NotesManager' in scope
```

**Analysis:**
- Missing import: `import Noty` or `@testable import Noty`
- Typo in name
- File not in target

**Fix:**
Add correct import or fix typo

### Strategy 2: Locate Context

Find where the error occurs:

```
/path/to/file.swift:42:18: error: type 'String' has no member 'unknown'
```

**Analysis:**
- File: file.swift
- Line: 42
- Column: 18
- Error: unknown method on String

**Fix:**
Read line 42, understand what was intended, use correct method

### Strategy 3: Understand Dependencies

Some errors cascade:

```
error: cannot build module 'Noty' because module 'Noty' failed to build
```

**Analysis:**
- First error caused others
- Need to find root cause
- Look earlier in output

**Fix:**
Scroll up, find first error, fix that

### Strategy 4: Check Test Output

Test failures show expected vs actual:

```
XCTAssertEqual failed: ("Expected") is not equal to ("Actual")
```

**Analysis:**
- Expected: "Expected"
- Actual: "Actual"
- Implementation returns wrong value

**Fix:**
Check implementation logic, fix to return correct value

## Common Validation Failures

### Build Failures

**Missing Import**
```swift
// Error: cannot find 'NotesManager' in scope
// Fix: Add import
import Noty
```

**Type Mismatch**
```swift
// Error: cannot convert value of type 'String' to expected argument type 'Int'
// Fix: Convert type or use correct type
let value = Int(stringValue) ?? 0
```

**Undefined Symbol**
```swift
// Error: use of unresolved identifier 'unknownVariable'
// Fix: Define variable or fix typo
let unknownVariable = "value"
```

**Missing File**
```swift
// Error: no such module 'MissingFile'
// Fix: Add file to project target
```

### Test Failures

**Assertion Failure**
```swift
// XCTAssertEqual failed: (0) is not equal to (1)
// Fix: Check implementation logic
func addItem() {
    items.append(newItem)  // Was missing this line
    save()
}
```

**Test Timeout**
```swift
// Asynchronous wait failed
// Fix: Ensure async operation completes
await manager.load()  // Was missing await
```

**Missing Setup**
```swift
// Test failed: Optional unwrapping error
// Fix: Initialize in setUp()
override func setUp() {
    super.setUp()
    manager = TestManager()
}
```

### Lint Failures

**Unused Variable**
```swift
// warning: variable 'unused' was never used
// Fix: Remove or use it
let value = compute()  // Removed 'unused'
```

**Line Length**
```swift
// warning: line length exceeds 120 characters
// Fix: Break into multiple lines
let result = someVeryLongFunctionName(
    parameter1: value1,
    parameter2: value2
)
```

**Missing Documentation**
```swift
// warning: public function should be documented
// Fix: Add documentation comment
/// Adds a new item to the collection
func addItem() { }
```

## Best Practices

### DO

✅ Run validation after every change  
✅ Read error messages carefully  
✅ Fix one error at a time  
✅ Re-validate after each fix  
✅ Check for regressions  
✅ Start with build, then tests, then lint  
✅ Understand root cause before fixing  
✅ Test edge cases manually  
✅ Keep validation fast  
✅ Automate validations in PRPs  

### DON'T

❌ Skip validation to "save time"  
❌ Ignore warnings  
❌ Fix multiple issues simultaneously  
❌ Proceed with failing tests  
❌ Assume error is in test, not code  
❌ Make changes without re-validating  
❌ Skip manual testing for UI changes  
❌ Leave commented-out failed attempts  
❌ Commit code that doesn't validate  
❌ Forget to check build on clean state  

## Example: Audio Recorder Implementation

### Initial Implementation

```swift
class AudioRecorder: ObservableObject {
    @Published var isRecording = false
    
    func startRecording() {
        isRecording = true
        // Start recording logic
    }
}
```

### Validation 1: Build

```bash
xcodebuild -project Noty.xcodeproj -scheme Noty -configuration Debug build
```

**Result:** ❌ Failed

**Error:**
```
error: cannot find type 'ObservableObject' in scope
```

### Fix 1: Add Import

```swift
import Foundation
import Combine  // Added

class AudioRecorder: ObservableObject {
    @Published var isRecording = false
    
    func startRecording() {
        isRecording = true
    }
}
```

### Validation 2: Build

```bash
xcodebuild -project Noty.xcodeproj -scheme Noty -configuration Debug build
```

**Result:** ❌ Failed

**Error:**
```
warning: class 'AudioRecorder' should be marked with @MainActor
```

### Fix 2: Add @MainActor

```swift
import Foundation
import Combine

@MainActor  // Added
final class AudioRecorder: ObservableObject {
    @Published var isRecording = false
    
    func startRecording() {
        isRecording = true
    }
}
```

### Validation 3: Build

```bash
xcodebuild -project Noty.xcodeproj -scheme Noty -configuration Debug build
```

**Result:** ✅ Success

### Validation 4: Tests

```bash
xcodebuild -project Noty.xcodeproj -scheme Noty \
  -destination 'platform=macOS' \
  -only-testing:NotyTests/AudioRecorderTests test
```

**Result:** ✅ All tests pass

### Validation 5: Manual

1. Run app
2. Tap record button
3. Verify `isRecording` state updates
4. Verify UI shows recording state

**Result:** ✅ Works as expected

### Final Result

All validations passed. Feature complete.

## Conclusion

Validation loops enable AI assistants to:
- Deliver working code autonomously
- Self-correct when issues arise
- Ensure quality without human review
- Build confidence in implementations
- Follow best practices consistently

The key is making validation:
- Automatic (run after every change)
- Fast (quick feedback loops)
- Comprehensive (build + test + lint)
- Actionable (clear error messages)
- Repeatable (same results every time)

By following validation loops systematically, AI assistants can implement complex features with confidence.


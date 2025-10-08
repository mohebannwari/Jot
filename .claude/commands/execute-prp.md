---
description: Execute a Product Requirements Prompt (PRP) to implement a feature
arguments:
  - name: prp_file
    description: Path to the PRP file to execute
    required: true
---

# Execute Product Requirements Prompt (PRP)

You are tasked with implementing a feature by executing the provided Product Requirements Prompt (PRP).

## Input File
The PRP file is provided as: `$ARGUMENTS`

## Process

### 1. Load Complete Context
- Read the entire PRP file
- Note all context, patterns, and requirements
- Review all referenced example files
- Load any mentioned documentation
- Understand success criteria and validation gates

### 2. Create Implementation Plan
Use the `todo_write` tool to create a structured task list:

**Extract from PRP:**
- Each implementation step becomes a todo item
- Mark dependencies between tasks
- Set first task as "in_progress"
- Include validation steps

**Task Structure:**
- Clear, actionable descriptions
- One task per logical unit of work
- Validation checkpoints included
- Test writing as separate tasks

### 3. Execute Implementation
Work through each task systematically:

**For Each Implementation Step:**
- Review relevant code patterns from PRP
- Create or modify files as specified
- Follow established architectural patterns
- Apply Liquid Glass design system rules
- Add comprehensive comments explaining logic
- Update todo status to "completed" when done

**Code Quality Standards:**
- Follow SwiftUI best practices for iOS 26+/macOS 26+
- Use proper state management (@StateObject, @EnvironmentObject)
- Apply Liquid Glass effects correctly (no glass-on-glass)
- Use design tokens from Assets.xcassets
- Implement proper error handling
- Add accessibility support

**Component Structure:**
Follow the established pattern:
```swift
struct ComponentName: View {
    // 1. Props and environment
    let prop: Type
    @EnvironmentObject var manager: Manager
    
    // 2. State
    @State private var localState = false
    
    // 3. Computed properties
    private var computedValue: Type {
        // Logic here
    }
    
    // 4. Body
    var body: some View {
        // View hierarchy
    }
}
```

### 4. Run Validation Gates
After implementation, verify each gate:

**Build Validation:**
```bash
xcodebuild -project Noty.xcodeproj -scheme Noty -configuration Debug build
```

**Test Validation:**
```bash
xcodebuild -project Noty.xcodeproj -scheme Noty -destination 'platform=macOS' test
```

**Clean Build (if needed):**
```bash
xcodebuild -project Noty.xcodeproj -scheme Noty clean
```

### 5. Handle Failures
If any validation gate fails:

**Build Failures:**
- Read the error output carefully
- Identify the root cause
- Fix syntax errors, missing imports, or type mismatches
- Re-run build validation

**Test Failures:**
- Review failed test output
- Fix implementation bugs
- Update tests if specifications changed
- Re-run test validation

**Linter Errors:**
- Read linter output with `read_lints` tool
- Fix style violations
- Ensure code follows conventions
- Re-check linting

### 6. Iterate Until Success
Continue fixing and validating until:
- All builds pass
- All tests pass
- No linter errors
- All success criteria met
- Design system compliance verified

### 7. Final Verification
Ensure completion:

**Functional Verification:**
- Review each success criterion from PRP
- Verify feature works as specified
- Check edge cases are handled

**Code Quality Verification:**
- Code follows project conventions
- Proper comments explain complex logic
- No hardcoded values (use design tokens)
- Accessibility implemented

**Documentation Verification:**
- Comments explain non-obvious logic
- Public APIs documented
- Any new patterns documented

## Output
Provide a comprehensive summary:

```
Implementation Complete: {Feature Name}

Files Created/Modified:
- List each file with brief description

Success Criteria Met:
- [x] Criterion 1
- [x] Criterion 2
- [x] Criterion 3

Validation Results:
- [x] Build passes
- [x] Tests pass
- [x] Linter clean
- [x] Design system compliant

To test the feature:
{Provide specific instructions for testing}
```

## Important Notes
- Work systematically through each implementation step
- Don't skip validation gates
- Fix all errors before proceeding
- Add comprehensive comments to your code
- Follow the established patterns from the PRP
- Ensure Liquid Glass design system compliance
- Use .bouncy animations with 0.3 duration
- Never stack glass effects
- Use semantic colors from Assets.xcassets
- Target iOS 26+/macOS 26+ features
- Update todos as you progress


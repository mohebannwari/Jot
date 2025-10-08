# Agentic Development Workflow

This workflow describes how to break down complex features into agent-friendly tasks that AI coding assistants can execute systematically.

## Overview

Agentic development treats the AI assistant as an autonomous agent that:
- Works through tasks systematically
- Validates each step before proceeding
- Self-corrects when validation fails
- Maintains context across the entire implementation

## When to Use This Workflow

Use agentic development for:
- **Complex features** requiring multiple steps
- **Cross-cutting changes** affecting many files
- **New subsystems** with multiple components
- **Refactoring projects** touching existing code
- **Features with dependencies** between components

## Core Principles

### 1. Task Decomposition

Break features into small, testable units:

**Good Task:**
> Create FloatingActionButton component with liquid glass styling and hover effect

**Bad Task:**
> Build the entire note creation flow

**Rules:**
- One logical unit per task
- Clear success criteria
- Testable in isolation
- Independent when possible

### 2. Validation Gates

Every task must have clear validation:

```bash
# Build validation
xcodebuild -project Noty.xcodeproj -scheme Noty -configuration Debug build

# Test validation
xcodebuild -project Noty.xcodeproj -scheme Noty -destination 'platform=macOS' test

# Specific test
xcodebuild -project Noty.xcodeproj -scheme Noty -destination 'platform=macOS' \
  -only-testing:NotyTests/FeatureTests test
```

**Validation Types:**
- Compilation (builds without errors)
- Tests (all tests pass)
- Linting (no style violations)
- Manual (specific behavior works)

### 3. Context Preservation

Maintain rich context throughout:

**Before each task:**
- Review relevant example files
- Check existing implementations
- Load related code patterns
- Understand dependencies

**During the task:**
- Follow established patterns
- Use design tokens
- Apply architecture conventions
- Add comprehensive comments

**After the task:**
- Run validations
- Update documentation
- Mark task complete
- Note any changes for next task

## Workflow Steps

### Step 1: Analysis

**Goal:** Understand what needs to be built

**Activities:**
1. Read the entire PRP or feature request
2. Identify all components needed
3. Map dependencies between components
4. Determine implementation order
5. Assess complexity and risks

**Output:** Clear mental model of the feature

### Step 2: Task Planning

**Goal:** Create actionable task list

**Activities:**
1. Decompose feature into tasks
2. Order tasks by dependencies
3. Define validation for each task
4. Estimate task sizes
5. Use `todo_write` to create task list

**Example Task List:**
```
1. Create AudioRecorder manager
   - Set up AVAudioSession
   - Implement recording lifecycle
   - Add file management
   Validation: Build passes, unit tests pass

2. Create RecordingButton component
   - Button with glass effect
   - Recording state animation
   - Hover interactions
   Validation: Build passes, preview renders

3. Create WaveformView component
   - Real-time waveform rendering
   - Gradient visualization
   - Performance optimization
   Validation: Build passes, smooth animation

4. Integrate recording into ContentView
   - Add button to toolbar
   - Handle recording state
   - Create note from recording
   Validation: Build passes, end-to-end test

5. Write comprehensive tests
   - AudioRecorder tests
   - Recording lifecycle tests
   - Note creation tests
   Validation: All tests pass
```

### Step 3: Systematic Execution

**Goal:** Complete each task with validation

**For each task:**

1. **Load Context**
   - Review relevant examples
   - Check similar implementations
   - Load required dependencies

2. **Implement**
   - Follow established patterns
   - Use design tokens
   - Add comprehensive comments
   - Handle edge cases

3. **Validate**
   - Run build validation
   - Run tests
   - Check linter
   - Manual verification

4. **Fix Issues**
   - If validation fails, analyze error
   - Fix root cause
   - Re-run validation
   - Iterate until success

5. **Complete**
   - Mark task done
   - Update documentation
   - Move to next task

### Step 4: Integration Validation

**Goal:** Ensure everything works together

**Activities:**
1. Run full test suite
2. Build release configuration
3. Manual end-to-end testing
4. Check design system compliance
5. Verify success criteria from PRP

### Step 5: Final Review

**Goal:** Ensure quality and completeness

**Checklist:**
- [ ] All tasks completed
- [ ] All tests passing
- [ ] No linter errors
- [ ] Design system compliant
- [ ] Documentation updated
- [ ] Comments explain complex logic
- [ ] Edge cases handled
- [ ] Performance acceptable

## Task Dependencies

### Sequential Tasks

Tasks that must run in order:

```
Task A → Task B → Task C
```

**Example:**
1. Create data model (Task A)
2. Create manager using model (Task B)
3. Create UI using manager (Task C)

### Parallel Tasks

Independent tasks that can run in any order:

```
Task A
Task B  } Can run in parallel
Task C
```

**Example:**
1. Create RecordingButton component
2. Create WaveformView component
3. Create AudioPlayer component

### Convergent Tasks

Multiple tasks leading to integration:

```
Task A →
Task B → Task D (Integration)
Task C →
```

**Example:**
1. AudioRecorder manager (A)
2. RecordingButton UI (B)
3. WaveformView UI (C)
4. Integrate all into ContentView (D)

## Handling Complexity

### High-Complexity Features

For very complex features:

1. **Break into phases**
   - Phase 1: Core functionality
   - Phase 2: Enhanced features
   - Phase 3: Polish and optimization

2. **Create sub-PRPs**
   - Main PRP for overall feature
   - Sub-PRPs for major subsystems
   - Execute sub-PRPs independently

3. **Use staging approach**
   - Build on feature branch
   - Merge when stable
   - Iterate in phases

### Unknown Requirements

When requirements are unclear:

1. **Spike task**
   - Research possible approaches
   - Prototype quickly
   - Document findings
   - Update PRP with learnings

2. **Iterative refinement**
   - Build minimal version first
   - Validate with stakeholders
   - Refine based on feedback
   - Repeat until satisfactory

## Error Recovery

### Build Failures

1. **Read error carefully**
   - Identify specific issue
   - Locate problem file/line
   - Understand root cause

2. **Fix systematically**
   - Fix one error at a time
   - Re-build to verify
   - Check for new errors
   - Iterate until clean

3. **Common issues**
   - Missing imports
   - Type mismatches
   - Undefined symbols
   - Syntax errors

### Test Failures

1. **Analyze failure**
   - Read test output
   - Identify failing assertion
   - Understand expected vs actual
   - Locate bug in implementation

2. **Fix and verify**
   - Fix implementation bug
   - Re-run test
   - Check other tests
   - Ensure no regressions

3. **Update tests if needed**
   - If requirements changed
   - If test was incorrect
   - Document why test changed

### Design Violations

1. **Check against standards**
   - Review LIQUID_GLASS_GUIDE.md
   - Check CLAUDE.md patterns
   - Verify design tokens used
   - Ensure animations correct

2. **Correct violations**
   - Replace hardcoded values
   - Apply correct glass effects
   - Fix animation timing
   - Update spacing/typography

## Best Practices

### DO

✅ Break features into small, testable tasks  
✅ Define clear success criteria  
✅ Validate after every task  
✅ Follow established patterns  
✅ Add comprehensive comments  
✅ Handle edge cases  
✅ Write tests alongside code  
✅ Keep tasks independent when possible  
✅ Update todos as you progress  
✅ Fix issues immediately  

### DON'T

❌ Skip validation gates  
❌ Move to next task with failures  
❌ Make assumptions without checking  
❌ Ignore established patterns  
❌ Hardcode values instead of using design tokens  
❌ Leave complex code uncommented  
❌ Write tests as an afterthought  
❌ Create tasks too large  
❌ Forget to update documentation  
❌ Ignore linter warnings  

## Example: Voice Recording Feature

### Analysis
- Needs AudioRecorder manager
- Needs recording UI components
- Needs waveform visualization
- Needs integration with notes
- Needs comprehensive testing

### Task Breakdown
1. AudioRecorder manager (high priority, foundation)
2. RecordingButton component (medium priority, parallel)
3. WaveformView component (medium priority, parallel)
4. Integration into ContentView (low priority, depends on 1-3)
5. AudioPlayer for playback (low priority, independent)
6. Comprehensive testing (low priority, depends on all)

### Execution Order
1. Task 1 (foundation for others)
2. Tasks 2, 3, 5 in parallel (independent components)
3. Task 4 (integration)
4. Task 6 (final validation)

### Validation Strategy
- After Task 1: Unit tests for recording logic
- After Tasks 2-3: Preview renders, hover works
- After Task 4: End-to-end recording flow works
- After Task 6: Full test suite passes

## Conclusion

Agentic development enables AI assistants to tackle complex features systematically. By breaking down features, defining clear validation gates, and maintaining rich context, you ensure successful implementations that follow project standards and work correctly.

The key is treating the AI as an autonomous agent that:
- Plans before coding
- Validates constantly
- Self-corrects when needed
- Follows established patterns
- Delivers working, tested code


# Context Gathering Workflow

This workflow describes how to systematically gather comprehensive context before implementing features, ensuring AI assistants have all the information needed for successful implementations.

## Overview

Context engineering is fundamentally about providing complete information:
- **What** to build (requirements)
- **How** to build it (patterns and conventions)
- **Why** decisions were made (rationale)
- **Where** similar code exists (examples)
- **When** to use specific approaches (guidelines)

Without proper context, AI assistants make assumptions that lead to:
- Code that doesn't match project style
- Violations of design system rules
- Reinventing existing solutions
- Missing edge cases
- Incorrect architectural decisions

## Context Categories

### 1. Feature Requirements

**What to gather:**
- User stories and goals
- Functional requirements
- Non-functional requirements (performance, accessibility)
- Edge cases and error scenarios
- Success criteria

**Sources:**
- INITIAL.md files
- Product requirements documents
- User feedback
- Design specifications
- Stakeholder discussions

**Example:**
```markdown
Feature: Voice Note Recording

User Story:
As a user, I want to record voice notes so that
I can capture thoughts hands-free.

Functional Requirements:
- Start/stop recording with button
- Real-time waveform visualization
- Automatic transcription
- Audio file attachment to notes
- Playback in note detail view

Non-Functional Requirements:
- Recording must start within 100ms
- Transcription accuracy > 95%
- Audio files < 10MB
- Works offline (transcription when online)

Edge Cases:
- Microphone permission denied
- Storage space full
- App backgrounded during recording
- Phone call interrupts recording
```

### 2. Architecture Patterns

**What to gather:**
- Project structure conventions
- File organization patterns
- Naming conventions
- Module boundaries
- Dependency management

**Sources:**
- `CLAUDE.md` - Project guidelines
- `AGENTS.md` - Repository rules
- Existing codebase structure
- Architecture decision records

**Example:**
```
Jot Architecture:

Entry Point:
- Jot/App/JotApp.swift - App lifecycle
- Jot/App/ContentView.swift - Root view

State Management:
- @StateObject for screen-level managers
- @EnvironmentObject for app-level managers
- @Published for observable properties
- @MainActor for UI thread safety

File Organization:
- Models/ - Business logic and state
- Views/Components/ - Reusable UI
- Views/Screens/ - Full-screen views
- Utils/ - Helpers and extensions
- One type per file, file name matches type
```

### 3. Code Patterns

**What to gather:**
- Component structure patterns
- State management approaches
- Error handling patterns
- Testing patterns
- Documentation patterns

**Sources:**
- `examples/` directory
- Similar existing implementations
- Team coding standards
- Best practices documentation

**Example:**
```swift
Component Pattern (from examples/component_pattern.swift):

struct ComponentName: View {
    // MARK: - Properties
    let prop: Type
    @EnvironmentObject private var manager: Manager
    
    // MARK: - State
    @State private var localState = false
    
    // MARK: - Computed Properties
    private var computed: Type { }
    
    // MARK: - Body
    var body: some View { }
    
    // MARK: - Helper Methods
    private func helper() { }
}
```

### 4. Design System

**What to gather:**
- Visual design specifications
- Component library
- Design tokens (colors, typography, spacing)
- Animation guidelines
- Accessibility requirements

**Sources:**
- Figma design files
- `LIQUID_GLASS_GUIDE.md`
- Design system documentation
- `Assets.xcassets` color definitions
- Style guides

**Example:**
```
Liquid Glass Design System:

Glass Effects:
- .liquidGlass(in: shape) - Standard glass
- .tintedLiquidGlass(...) - Tinted glass
- Apply to floating elements only
- Never stack glass on glass

Colors (from Assets.xcassets):
- BackgroundColor - Main background
- CardBackgroundColor - Card surfaces
- PrimaryTextColor - Primary text
- SecondaryTextColor - Secondary text
- Never hardcode colors

Typography:
- Title: .system(size: 17, weight: .semibold)
- Body: .system(size: 14, weight: .regular)
- Caption: .system(size: 12, weight: .medium)

Animations:
- .bouncy(duration: 0.3) - Glass effects
- .smooth - Transitions
- .spring(...) - Interactive elements
```

### 5. Technical Constraints

**What to gather:**
- Platform requirements (iOS 26+/macOS 26+)
- Performance requirements
- Security requirements
- Privacy considerations
- API limitations

**Sources:**
- Project README
- Platform documentation
- Architecture decisions
- Performance monitoring data
- Security audit reports

**Example:**
```
Technical Constraints:

Platform:
- Target: iOS 26+ / macOS 26+
- Use native .glassEffect() API
- No iOS 18 or macOS 15 APIs
- SwiftUI only (no UIKit)

Performance:
- Main thread: < 16ms per frame (60fps)
- Launch time: < 2 seconds
- Memory: < 100MB typical usage
- Glass effects: Respect Reduce Transparency

Security:
- Encrypt sensitive notes
- Secure keychain for credentials
- No secrets in code/config
- Request permissions appropriately

Privacy:
- Microphone permission for recording
- Location permission if needed
- Clear data usage disclosure
- User control over data
```

### 6. Existing Implementations

**What to gather:**
- Similar features in codebase
- Reusable components
- Utility functions
- Integration patterns

**Sources:**
- Codebase search
- Component catalog
- Utility directories
- Integration tests

**Example:**
```
Existing Audio Code:

Related Components:
- Models/AudioRecorder.swift - Basic recording
- Models/Transcriber.swift - Speech-to-text
- Views/Components/WaveformView.swift - Visualization
- Utils/HapticManager.swift - Feedback patterns

Reusable Patterns:
- Permission handling in AudioRecorder
- File management in NotesManager
- Glass effects in GlassEffects.swift
- Animations in NoteCard hover state

Integration Points:
- NotesManager.addNote() - Create notes
- Note model - Add audio metadata
- NoteDetailView - Add playback UI
```

### 7. Testing Requirements

**What to gather:**
- Testing patterns
- Coverage requirements
- Test utilities
- Mock/stub approaches

**Sources:**
- `JotTests/` directory
- `examples/testing_pattern.swift`
- Test configuration
- CI/CD pipeline

**Example:**
```
Testing Standards:

Unit Tests:
- Location: JotTests/{FeatureName}Tests.swift
- Pattern: Arrange-Act-Assert
- Use @MainActor for async code
- Temporary storage for isolation
- Clean up in tearDown()

Test Coverage:
- All manager methods
- Business logic functions
- Edge cases and errors
- Data persistence

Mock Strategy:
- Inject dependencies
- Use temporary storage URLs
- Mock external APIs
- Disable seeding in tests

Validation Commands:
xcodebuild -project Jot.xcodeproj -scheme Jot \
  -destination 'platform=macOS' test
```

### 8. Domain Knowledge

**What to gather:**
- Business logic rules
- Domain terminology
- User workflows
- Feature interactions

**Sources:**
- Domain experts
- User research
- Existing features
- Product documentation

**Example:**
```
Note Management Domain:

Terminology:
- Note: Text content with metadata
- Card: Visual representation of note
- Pinned: Note fixed at top
- Tag: Category or label
- Archive: Hidden but not deleted

Business Rules:
- Notes can't have empty title and content
- Pinned notes always show first
- Deleted notes can be recovered (30 days)
- Tags are case-insensitive
- Search includes title, content, and tags

User Workflows:
1. Quick capture: Tap + → Type → Save
2. Voice note: Tap mic → Record → Auto-save
3. Organization: Select notes → Tag → Organize
4. Search: Type query → Filter results → Open
```

## Context Gathering Process

### Step 1: Read Requirements

**Goal:** Understand what to build

**Activities:**
1. Read INITIAL.md or PRP thoroughly
2. Identify core functionality
3. Note edge cases
4. Understand success criteria
5. List questions or unclear areas

**Output:** Clear understanding of the feature

### Step 2: Search Codebase

**Goal:** Find relevant existing code

**Activities:**
1. Search for similar features
2. Find related components
3. Locate utility functions
4. Identify integration points
5. Review existing tests

**Tools:**
```swift
// Semantic search
codebase_search("How do we handle audio recording?", ["Jot/Models"])

// Text search
grep("AudioRecorder", path: "Jot/")

// File search
glob_file_search("*Recorder*.swift")
```

**Output:** List of relevant files and patterns

### Step 3: Review Examples

**Goal:** Understand established patterns

**Activities:**
1. Read relevant files from `examples/`
2. Study similar implementations
3. Note architectural decisions
4. Understand conventions
5. Identify reusable patterns

**Examples to check:**
- `examples/component_pattern.swift` - UI structure
- `examples/manager_pattern.swift` - State management
- `examples/glass_effects_pattern.swift` - Styling
- `examples/view_architecture.swift` - Composition
- `examples/testing_pattern.swift` - Testing

**Output:** Clear patterns to follow

### Step 4: Check Documentation

**Goal:** Understand guidelines and constraints

**Activities:**
1. Review `CLAUDE.md` for architecture
2. Check `LIQUID_GLASS_GUIDE.md` for design
3. Read `AGENTS.md` for repository rules
4. Review platform documentation
5. Check design specifications

**Output:** List of requirements and constraints

### Step 5: Examine Design System

**Goal:** Understand visual requirements

**Activities:**
1. Review Figma designs
2. Identify design tokens
3. Check `Assets.xcassets` for colors
4. Note animation requirements
5. Verify accessibility needs

**Output:** Visual specification and token list

### Step 6: Map Dependencies

**Goal:** Understand what depends on what

**Activities:**
1. Identify required components
2. Map data flow
3. Note integration points
4. Check for circular dependencies
5. Plan implementation order

**Output:** Dependency graph and task order

### Step 7: Document Context

**Goal:** Consolidate all gathered context

**Activities:**
1. Write context summary
2. List all relevant files
3. Document patterns to follow
4. Note constraints and gotchas
5. Create implementation checklist

**Output:** Comprehensive context document (PRP)

## Context Quality Checklist

Use this checklist to ensure comprehensive context:

### Requirements
- [ ] User story clear
- [ ] Functional requirements listed
- [ ] Non-functional requirements specified
- [ ] Edge cases identified
- [ ] Success criteria defined

### Architecture
- [ ] File structure determined
- [ ] Component hierarchy planned
- [ ] State management approach chosen
- [ ] Integration points identified
- [ ] Dependencies mapped

### Patterns
- [ ] Similar implementations reviewed
- [ ] Code patterns identified
- [ ] Example files referenced
- [ ] Naming conventions noted
- [ ] Error handling approach defined

### Design System
- [ ] Visual design specified
- [ ] Design tokens identified
- [ ] Glass effects planned
- [ ] Colors from Assets.xcassets
- [ ] Animations defined
- [ ] Accessibility considered

### Technical
- [ ] Platform requirements clear
- [ ] Performance requirements specified
- [ ] Security considerations noted
- [ ] Privacy requirements listed
- [ ] API limitations documented

### Testing
- [ ] Test strategy defined
- [ ] Test patterns identified
- [ ] Coverage requirements set
- [ ] Edge cases for testing listed
- [ ] Validation commands provided

### Domain
- [ ] Business rules documented
- [ ] Terminology defined
- [ ] User workflows understood
- [ ] Feature interactions mapped
- [ ] Constraints documented

## Context Confidence Scoring

Rate context completeness (1-10 scale):

**10 - Perfect Context:**
- All requirements crystal clear
- All patterns identified
- All examples available
- Complete design specification
- Comprehensive technical docs

**7-9 - Good Context:**
- Most requirements clear
- Key patterns identified
- Relevant examples available
- Design mostly specified
- Technical constraints known

**4-6 - Moderate Context:**
- Core requirements clear
- Some patterns identified
- Few examples available
- Design partially specified
- Some technical unknowns

**1-3 - Poor Context:**
- Requirements vague
- Patterns unclear
- No examples
- Design not specified
- Many technical unknowns

**Threshold:** Aim for 7+ before implementation. Below 7, gather more context or ask clarifying questions.

## Common Context Gaps

### Missing Requirements
**Symptom:** Unclear what to build

**Solution:**
- Ask specific questions
- Request user stories
- Review existing features
- Check product roadmap

### Unknown Patterns
**Symptom:** Don't know how to structure code

**Solution:**
- Search for similar features
- Review example files
- Check architecture docs
- Study existing implementations

### Design Ambiguity
**Symptom:** Visual appearance unclear

**Solution:**
- Request Figma links
- Reference design system
- Check existing components
- Ask for mockups

### Technical Unknowns
**Symptom:** Unsure about constraints

**Solution:**
- Read platform docs
- Check project requirements
- Review architecture decisions
- Test on target platform

## Best Practices

### DO

✅ Gather context before coding  
✅ Search codebase for patterns  
✅ Review all example files  
✅ Check design specifications  
✅ Document unknowns  
✅ Ask clarifying questions  
✅ Reference existing implementations  
✅ Verify platform requirements  
✅ Check accessibility needs  
✅ Rate confidence level  

### DON'T

❌ Start coding without context  
❌ Assume patterns without checking  
❌ Ignore example files  
❌ Hardcode without checking tokens  
❌ Make up requirements  
❌ Skip design review  
❌ Forget platform constraints  
❌ Ignore similar implementations  
❌ Overlook edge cases  
❌ Proceed with low confidence  

## Conclusion

Context gathering is the foundation of successful AI-assisted development. By systematically collecting information about requirements, patterns, design, and constraints, you ensure AI assistants have everything needed to:

- Build features that match project style
- Follow established conventions
- Apply design system correctly
- Handle edge cases
- Write appropriate tests
- Deliver working code first try

The investment in context gathering pays off with:
- Fewer iterations
- Better code quality
- Consistent implementations
- Reduced technical debt
- Faster development overall

Remember: **Context engineering is 10x better than prompt engineering and 100x better than vibe coding.**


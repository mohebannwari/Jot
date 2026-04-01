# Context Engineering Guide for Jot

Welcome to context engineering with Jot! This guide explains how to use the context engineering framework to build features systematically with AI assistance.

## What is Context Engineering?

Context engineering is the discipline of providing comprehensive context to AI coding assistants so they have all the information needed to implement features correctly. It's fundamentally different from prompt engineering:

**Prompt Engineering:**
- Focuses on clever wording
- Limited to how you phrase a request
- Like giving someone a sticky note

**Context Engineering:**
- Complete system of information
- Includes documentation, examples, patterns, validation
- Like writing a full screenplay with all details

### Why It Matters

Most AI failures aren't model failures - they're context failures. Without proper context, AI assistants:
- Violate design system rules
- Don't follow project patterns
- Miss edge cases
- Create inconsistent code
- Require many iterations

With comprehensive context, AI assistants:
- Follow project conventions automatically
- Apply design system correctly
- Handle edge cases
- Deliver working code first try
- Self-correct when validation fails

## Quick Start

### 1. Describe Your Feature

Create an `INITIAL.md` file describing what you want to build:

```bash
cp INITIAL.md my-feature.md
# Edit my-feature.md with your requirements
```

See `INITIAL_EXAMPLE.md` for a complete example.

### 2. Generate a PRP

Use the `/generate-prp` command to create a Product Requirements Prompt:

```
/generate-prp my-feature.md
```

This will:
- Analyze your feature request
- Search the codebase for patterns
- Gather documentation
- Create a comprehensive PRP at `PRPs/my-feature-name.md`

### 3. Execute the PRP

Use the `/execute-prp` command to implement the feature:

```
/execute-prp PRPs/my-feature-name.md
```

This will:
- Load all context from the PRP
- Create an implementation plan
- Execute each step systematically
- Validate at every stage
- Fix issues automatically
- Deliver working, tested code

## The PRP Workflow

### What is a PRP?

A Product Requirements Prompt (PRP) is a comprehensive document that includes:

**Context Section:**
- Feature overview and goals
- How it fits into existing architecture
- Related components and dependencies

**Architecture & Patterns:**
- File structure to follow
- Component hierarchy
- State management approach
- Code patterns to use

**Design System Compliance:**
- Liquid Glass requirements
- Color usage
- Typography specifications
- Animation requirements

**Implementation Steps:**
- Step-by-step tasks
- Code patterns for each step
- Validation commands
- Expected outcomes

**Success Criteria:**
- Functional requirements
- Build/test commands
- Design compliance checks
- Quality standards

**Testing Requirements:**
- Unit tests to write
- Test patterns to follow
- Coverage expectations

**Validation Gates:**
- Build commands that must pass
- Test commands that must succeed
- Linting checks

### PRP Structure

PRPs follow a standard template (`PRPs/templates/prp_base.md`):

1. **Metadata** - Created date, target OS, confidence level
2. **Feature Overview** - What and why
3. **Context & Background** - Existing architecture
4. **Architecture & Design Patterns** - How to structure code
5. **Design System Compliance** - Visual requirements
6. **Implementation Steps** - Detailed tasks with validation
7. **Success Criteria** - Requirements checklist
8. **Validation Gates** - Commands to verify success
9. **Testing Requirements** - Tests to write
10. **Gotchas & Considerations** - Common pitfalls
11. **Documentation & References** - Links and examples
12. **Implementation Checklist** - Step-by-step checklist
13. **Confidence Assessment** - What's clear, what's not

See `PRPs/EXAMPLE_liquid_glass_feature.md` for a complete example.

## Writing Effective INITIAL.md Files

The quality of your INITIAL.md directly impacts the PRP quality. Follow this structure:

### FEATURE Section

Be specific and comprehensive:

**Bad:**
> Build a web scraper

**Good:**
> Build an async web scraper using URLSession that extracts article metadata (title, description, image) from URLs, handles rate limiting with exponential backoff, caches results for 24 hours, and displays preview cards with Liquid Glass styling.

**Include:**
- Exactly what the feature does
- Why it's needed
- How users interact with it
- Specific technical requirements
- Expected behavior in edge cases

### EXAMPLES Section

Reference relevant code patterns:

```markdown
## EXAMPLES

**Example files to reference:**
- `examples/component_pattern.swift` - For UI component structure
- `examples/manager_pattern.swift` - For state management
- `examples/glass_effects_pattern.swift` - For glass styling

**Existing implementations:**
- `Jot/Views/Components/NoteCard.swift` - Similar card layout
- `Jot/Models/NotesManager.swift` - Similar CRUD pattern
```

### DOCUMENTATION Section

Include all relevant resources:

```markdown
## DOCUMENTATION

**External resources:**
- Apple URLSession: https://developer.apple.com/documentation/foundation/urlsession
- SwiftUI async/await patterns: (link)

**Figma designs:**
- https://www.figma.com/design/BhVLOWG63LckTVCuO3q0Tv/Jot
- Component: Web Preview Card

**Related docs:**
- See `LIQUID_GLASS_GUIDE.md` for glass effects
- See `CLAUDE.md` for architecture patterns
```

### OTHER CONSIDERATIONS Section

Capture important details:

```markdown
## OTHER CONSIDERATIONS

**Design System:**
- Use `.tintedLiquidGlass()` for preview card
- Colors from Assets.xcassets only
- Standard corner radius: 24pt
- `.bouncy(duration: 0.3)` animations

**iOS 26+ Features:**
- Use native `.glassEffect()` API
- Leverage improved async/await
- New URLSession enhancements

**Gotchas:**
- Request URL metadata permission
- Handle HTTP errors gracefully
- Cache invalidation strategy
- Rate limiting per domain
- Timeout for slow sites (5 seconds)

**Testing:**
- Mock URLSession for tests
- Test rate limiting logic
- Test cache hit/miss scenarios
- Test malformed HTML handling
```

## Using Examples Effectively

The `examples/` directory is critical for success. It contains representative patterns from Jot:

### Available Examples

**`examples/component_pattern.swift`**
- SwiftUI component structure
- State management
- Glass effects
- Hover interactions
- Use for: Building UI components

**`examples/manager_pattern.swift`**
- ObservableObject pattern
- @Published properties
- CRUD operations
- JSON persistence
- Use for: State management

**`examples/glass_effects_pattern.swift`**
- Liquid Glass modifiers
- OS version handling
- Fallback strategies
- Different glass types
- Use for: Applying glass effects

**`examples/view_architecture.swift`**
- Screen composition
- Environment objects
- Navigation patterns
- Layout strategies
- Use for: Building screens

**`examples/testing_pattern.swift`**
- XCTest structure
- @MainActor testing
- Temporary storage
- Arrange-Act-Assert
- Use for: Writing tests

### How to Reference Examples

In your INITIAL.md:

```markdown
Follow the component pattern from `examples/component_pattern.swift`:
- Props → State → Computed → Body structure
- Use `@EnvironmentObject` for shared state
- Apply glass effects with `.liquidGlass()`
- Add hover animations with `.bouncy(duration: 0.3)`
```

## Understanding Workflows

The `PRPs/workflows/` directory contains detailed workflows:

### Agentic Development (`agentic_development.md`)

Learn how to:
- Break features into agent-friendly tasks
- Order tasks by dependencies
- Define clear success criteria
- Handle complex features systematically

**Use for:** Planning complex multi-step implementations

### Validation Loops (`validation_loops.md`)

Learn how to:
- Validate implementations automatically
- Self-correct when validation fails
- Interpret error messages
- Fix issues systematically

**Use for:** Ensuring code works first try

### Context Gathering (`context_gathering.md`)

Learn how to:
- Collect comprehensive context
- Search codebase for patterns
- Review design specifications
- Document technical constraints

**Use for:** Preparing thorough PRPs

## Custom Commands

The `.claude/commands/` directory defines custom commands:

### `/generate-prp`

**Purpose:** Create comprehensive PRP from INITIAL.md

**Usage:**
```
/generate-prp path/to/feature-request.md
```

**What it does:**
1. Reads your feature request
2. Searches codebase for patterns
3. Reviews example files
4. Gathers documentation
5. Creates detailed PRP

**Output:** `PRPs/{feature-name}.md`

### `/execute-prp`

**Purpose:** Implement feature from PRP

**Usage:**
```
/execute-prp PRPs/feature-name.md
```

**What it does:**
1. Loads complete context
2. Creates task plan
3. Implements systematically
4. Validates at each step
5. Fixes issues automatically
6. Delivers working code

**Output:** Implemented feature with tests

## Design System Integration

Jot uses Apple's Liquid Glass design system (iOS 26+/macOS 26+).

### Glass Effects

**Priority order:**
1. Native `.glassEffect()` (iOS 26+/macOS 26+)
2. `.ultraThinMaterial` (fallback)

**Available modifiers:**
```swift
// Standard glass
.liquidGlass(in: RoundedRectangle(cornerRadius: 24))

// Tinted glass
.tintedLiquidGlass(in: Capsule(), tint: Color("SurfaceTranslucentColor"))

// Thin glass
.thinLiquidGlass(in: Circle())
```

**Rules:**
- Apply to floating elements only (toolbars, cards, overlays)
- Never stack glass on glass
- Use `.bouncy(duration: 0.3)` for glass animations
- Interactive elements need `.interactive(true)`

See `LIQUID_GLASS_GUIDE.md` for complete guidelines.

### Design Tokens

**Colors (from Assets.xcassets):**
- `BackgroundColor` - Main background
- `CardBackgroundColor` - Card surfaces
- `PrimaryTextColor` - Primary text
- `SecondaryTextColor` - Secondary text
- `TertiaryTextColor` - Tertiary text
- `SurfaceTranslucentColor` - Glass tints
- Never hardcode colors

**Typography:**
```swift
// Title
.font(.system(size: 17, weight: .semibold))

// Body
.font(.system(size: 14, weight: .regular))

// Caption
.font(.system(size: 12, weight: .medium))

// Small
.font(.system(size: 10, weight: .medium))
```

**Spacing:**
Standard values: 4, 6, 8, 12, 16, 18, 24, 60

**Corner Radius:**
Standard values: 4, 20, 24, or Capsule

**Animations:**
```swift
// Glass effects
.bouncy(duration: 0.3)

// Smooth transitions
.smooth

// Spring animations
.spring(response: 0.35, dampingFraction: 0.82)
```

## Validation Gates

Every PRP includes validation commands that must pass:

### Build Validation
```bash
xcodebuild -project Jot.xcodeproj -scheme Jot -configuration Debug build
```

### Test Validation
```bash
xcodebuild -project Jot.xcodeproj -scheme Jot -destination 'platform=macOS' test
```

### Specific Test
```bash
xcodebuild -project Jot.xcodeproj -scheme Jot -destination 'platform=macOS' \
  -only-testing:JotTests/FeatureTests test
```

### Clean Build
```bash
xcodebuild -project Jot.xcodeproj -scheme Jot clean
```

AI assistants run these automatically and fix issues until all pass.

## Best Practices

### DO

✅ **Write detailed INITIAL.md files** - More detail = better PRP  
✅ **Reference example files** - Show patterns to follow  
✅ **Include Figma links** - Specify visual design  
✅ **Note gotchas** - Things commonly missed  
✅ **Specify testing** - Edge cases to handle  
✅ **Review generated PRPs** - Verify completeness  
✅ **Trust validation loops** - AI will fix issues  
✅ **Use design tokens** - Never hardcode  
✅ **Follow examples** - Consistency matters  
✅ **Document decisions** - Add comments  

### DON'T

❌ **Write vague requirements** - AI will make assumptions  
❌ **Skip examples** - Context is critical  
❌ **Ignore design system** - Follow Liquid Glass rules  
❌ **Hardcode values** - Use Assets.xcassets  
❌ **Skip validation** - Always test  
❌ **Override patterns** - Follow established conventions  
❌ **Forget edge cases** - List them explicitly  
❌ **Assume AI knows** - Provide complete context  
❌ **Skip documentation** - Keep docs updated  
❌ **Rush the process** - Context gathering pays off  

## Troubleshooting

### "Generated PRP is incomplete"

**Cause:** INITIAL.md lacked detail

**Solution:**
- Add more specific requirements
- Reference similar implementations
- Include design specifications
- List technical constraints
- Regenerate PRP

### "Implementation doesn't match style"

**Cause:** Examples not referenced

**Solution:**
- Point to specific example files
- Reference existing implementations
- Include style guidelines in INITIAL.md
- Regenerate PRP with examples

### "Validation keeps failing"

**Cause:** Technical constraint not specified

**Solution:**
- Check error messages carefully
- Add constraint to PRP
- Regenerate if needed
- AI will iterate until success

### "Design doesn't match Figma"

**Cause:** Design specs not included

**Solution:**
- Link to Figma artboards
- Specify exact tokens to use
- Reference design guide sections
- Include screenshots if needed

## Advanced Usage

### Multiple PRPs

For very large features:

1. Create main PRP for overall feature
2. Create sub-PRPs for major subsystems
3. Execute sub-PRPs independently
4. Integrate with main PRP

### Iterative Refinement

For unclear requirements:

1. Create initial minimal PRP
2. Implement basic version
3. Gather feedback
4. Refine PRP with learnings
5. Iterate until satisfactory

### Custom Templates

Create feature-specific templates:

1. Copy `PRPs/templates/prp_base.md`
2. Customize for feature type
3. Add domain-specific sections
4. Use for similar features

## Resources

### Documentation
- `CLAUDE.md` - Project architecture and patterns
- `LIQUID_GLASS_GUIDE.md` - Design system guidelines
- `AGENTS.md` - Repository rules
- `.claude/rules/figma.md` - Design specifications

### Examples
- `examples/` - Code patterns
- `PRPs/EXAMPLE_liquid_glass_feature.md` - Complete PRP example
- `INITIAL_EXAMPLE.md` - Feature request example

### Workflows
- `PRPs/workflows/agentic_development.md` - Task decomposition
- `PRPs/workflows/validation_loops.md` - Self-correction
- `PRPs/workflows/context_gathering.md` - Context collection

### Templates
- `INITIAL.md` - Feature request template
- `PRPs/templates/prp_base.md` - PRP template

## Getting Help

### Common Questions

**Q: How detailed should INITIAL.md be?**
A: Very detailed. Include everything you can think of. More context = better results.

**Q: Do I need to understand the codebase first?**
A: No. The `/generate-prp` command researches the codebase for you.

**Q: What if I don't know the exact implementation?**
A: That's fine. Describe what you want, reference similar features, and let AI figure out how.

**Q: Can I modify generated PRPs?**
A: Yes. Edit PRPs before executing if needed.

**Q: What if validation fails repeatedly?**
A: AI will iterate automatically. If stuck, check error messages and add constraints to PRP.

## Conclusion

Context engineering transforms AI coding assistance from "hit or miss" to reliable, systematic development. By providing comprehensive context through PRPs, you enable AI assistants to:

- Deliver working code first try
- Follow project conventions automatically
- Apply design system correctly
- Handle edge cases
- Write appropriate tests
- Self-correct when issues arise

The investment in writing detailed INITIAL.md files and generating comprehensive PRPs pays off with faster development, higher quality code, and fewer iterations.

**Remember:** Context engineering is 10x better than prompt engineering and 100x better than vibe coding.

---

## Next Steps

1. **Read** `INITIAL_EXAMPLE.md` to see a complete feature request
2. **Review** `PRPs/EXAMPLE_liquid_glass_feature.md` to see a complete PRP
3. **Study** `examples/` directory to understand code patterns
4. **Create** your first INITIAL.md for a feature you want to build
5. **Generate** your first PRP with `/generate-prp`
6. **Execute** the PRP with `/execute-prp` and watch AI build your feature

Happy context engineering!


---
description: Generate a comprehensive Product Requirements Prompt (PRP) from an INITIAL.md file
arguments:
  - name: initial_file
    description: Path to the INITIAL.md file containing the feature request
    required: true
---

# Generate Product Requirements Prompt (PRP)

You are tasked with generating a comprehensive Product Requirements Prompt (PRP) from the provided INITIAL.md file.

## Input File
The INITIAL.md file is provided as: `$ARGUMENTS`

## Process

### 1. Read and Analyze the INITIAL.md File
- Read the entire content of the INITIAL.md file
- Extract the FEATURE description
- Note all EXAMPLES referenced
- Collect DOCUMENTATION links
- Identify OTHER CONSIDERATIONS

### 2. Research the Codebase
Conduct a systematic investigation:

**Architecture Patterns:**
- Search for similar implementations in the codebase
- Identify architectural patterns used (MVVM, state management)
- Find established component structures to follow
- Review existing managers and utilities

**Code Patterns:**
- Examine example files mentioned in INITIAL.md
- Review component structure patterns (props → computed properties → body)
- Identify state management patterns (@StateObject, @EnvironmentObject, @Published)
- Find testing patterns from existing tests

**Design System:**
- Review Liquid Glass implementation patterns
- Check design token usage from Assets.xcassets
- Identify spacing, typography, and color conventions
- Review animation patterns (.bouncy, .smooth)

### 3. Gather Documentation
- Fetch relevant API documentation if URLs provided
- Include SwiftUI best practices for iOS 26+/macOS 26+
- Reference Figma design file if applicable: https://www.figma.com/design/BhVLOWG63LckTVCuO3q0Tv/Noty
- Note any MCP server resources or tools needed

### 4. Generate the PRP
Create a comprehensive PRP file at `PRPs/{feature-name}.md` using the template from `PRPs/templates/prp_base.md`.

The PRP must include:

**Context Section:**
- Feature overview and goals
- Why this feature is needed
- How it fits into the existing architecture
- Related components and dependencies

**Architecture & Patterns:**
- Specific file structure to follow
- Component hierarchy
- State management approach
- Data flow patterns

**Design System Compliance:**
- Liquid Glass effect requirements
- Color usage from Assets.xcassets
- Typography specifications
- Spacing and layout standards
- Animation requirements

**Implementation Steps:**
Each step should include:
- Specific task description
- Files to create or modify
- Code patterns to follow
- Expected behavior
- Validation command

**Success Criteria:**
- Functional requirements checklist
- Build passes: `xcodebuild -project Noty.xcodeproj -scheme Noty -configuration Debug build`
- Tests pass: `xcodebuild -project Noty.xcodeproj -scheme Noty -destination 'platform=macOS' test`
- Design system compliance verified
- No linter errors

**Testing Requirements:**
- Unit tests to write
- Test file location and naming
- Test patterns to follow
- Expected test coverage

**Validation Gates:**
- Build commands that must succeed
- Test commands that must pass
- Linting checks
- Manual verification steps

### 5. Quality Assessment
Rate your confidence in the PRP (1-10 scale):
- 10: Complete context, all patterns identified, comprehensive implementation plan
- 7-9: Good context, most patterns found, clear implementation path
- 4-6: Moderate context, some patterns unclear, implementation needs iteration
- 1-3: Incomplete context, many unknowns, research needed

If confidence is below 7, note what additional information would help.

## Output
Create a comprehensive PRP file at `PRPs/{descriptive-feature-name}.md` and inform the user:

```
Created PRP: PRPs/{feature-name}.md

Confidence: {X}/10

To implement this feature, run:
/execute-prp PRPs/{feature-name}.md
```

## Important Notes
- Always search the codebase before making assumptions
- Reference specific files and line numbers when citing patterns
- Include actual code snippets from the codebase as examples
- Be explicit about iOS 26+/macOS 26+ requirements
- Note any gotchas or common pitfalls
- Follow the project's coding style and conventions
- Ensure Liquid Glass design system compliance


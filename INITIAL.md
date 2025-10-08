# Feature Request

Use this template to request new features for the Noty app. Fill in each section with as much detail as possible to help generate a comprehensive Product Requirements Prompt (PRP).

---

## FEATURE

**What do you want to build?**

{Provide a clear, detailed description of the feature you want to implement. Include:
- What the feature does
- Why it's needed
- How users will interact with it
- Any specific requirements or constraints
- Expected behavior in different scenarios}

**User Story (optional but recommended):**

As a {type of user}, I want to {goal} so that {benefit}.

---

## EXAMPLES

**Which example files should be referenced?**

{List relevant examples from the `examples/` directory that demonstrate patterns to follow:
- `examples/component_pattern.swift` - For UI components
- `examples/manager_pattern.swift` - For state management
- `examples/glass_effects_pattern.swift` - For Liquid Glass effects
- `examples/view_architecture.swift` - For screen composition
- `examples/testing_pattern.swift` - For test structure}

**Existing code to reference:**

{List any existing files in the codebase that implement similar features or patterns:
- `Path/To/SimilarComponent.swift` - {What to learn from it}
- `Path/To/RelatedManager.swift` - {What patterns to follow}}

---

## DOCUMENTATION

**External resources:**

{Include links to relevant documentation:
- Apple Developer Documentation (iOS 26+/macOS 26+)
- WWDC session videos
- SwiftUI tutorials
- Third-party library docs}

**Figma designs:**

{Reference specific artboards or components from the Figma file:
- https://www.figma.com/design/BhVLOWG63LckTVCuO3q0Tv/Noty
- Specific component: {name and location}}

**Related features:**

{List related features or documentation in this repo:
- See `LIQUID_GLASS_GUIDE.md` for glass effect guidelines
- See `CLAUDE.md` for architecture patterns
- See `TODO` for planned features}

---

## OTHER CONSIDERATIONS

**Design System Requirements:**

{Specify any Liquid Glass or design system requirements:
- Glass effect type (standard, tinted, thin)
- Colors from Assets.xcassets to use
- Typography specifications
- Spacing and layout requirements
- Animation requirements}

**iOS 26+ / macOS 26+ Features:**

{Note any specific iOS 26+/macOS 26+ APIs to use:
- Native .glassEffect() API
- Rich text support in TextEditor
- New toolbar APIs
- Enhanced @Observable macro
- Other SwiftUI enhancements}

**Technical Constraints:**

{List any technical constraints or gotchas:
- Performance requirements
- Memory considerations
- Compatibility requirements
- Known limitations
- Things AI assistants commonly miss}

**Testing Requirements:**

{Specify testing needs:
- Unit tests required?
- Integration tests needed?
- Specific scenarios to test
- Edge cases to handle}

---

## NEXT STEPS

Once you've filled out this template:

1. **Generate a PRP:**
   ```
   /generate-prp INITIAL.md
   ```

2. **Review the generated PRP** at `PRPs/{feature-name}.md`

3. **Execute the PRP** to implement the feature:
   ```
   /execute-prp PRPs/{feature-name}.md
   ```

---

## Tips for Better Results

- **Be specific**: The more detail you provide, the better the PRP will be
- **Reference examples**: Point to similar implementations in the codebase
- **Include constraints**: Note any gotchas or things that commonly go wrong
- **Specify design**: Link to Figma designs or describe the visual appearance
- **Think about testing**: Consider edge cases and testing scenarios upfront


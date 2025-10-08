<!-- 2141cc3f-863d-4c33-8576-11919c36d6eb 27555852-2b1d-473f-98eb-519f7fd4f172 -->
# Context Engineering Template Setup for Noty

## Overview

Setting up a comprehensive context engineering framework that enables systematic AI-assisted development through Product Requirements Prompts (PRPs), custom commands, and structured examples while preserving all existing project documentation.

## Implementation Steps

### 1. Create .claude Directory Structure

Create `.claude/` directory with custom commands and settings:

**Files to create:**

- `.claude/commands/generate-prp.md` - Custom command to analyze INITIAL.md files and generate comprehensive PRPs with project context
- `.claude/commands/execute-prp.md` - Custom command to implement features from generated PRPs with validation loops
- `.claude/settings.local.json` - Claude Code permissions configuration for autonomous operation

These commands will enable `/generate-prp INITIAL.md` and `/execute-prp PRPs/feature-name.md` workflows.

### 2. Create PRPs Directory and Templates

Establish the Product Requirements Prompts infrastructure:

**Structure:**

- `PRPs/` - Main directory for all PRPs
- `PRPs/templates/prp_base.md` - Base template with sections for Context, Implementation Steps, Success Criteria, Testing Requirements, and Validation Gates
- `PRPs/EXAMPLE_liquid_glass_feature.md` - Complete example PRP demonstrating the structure for a SwiftUI/Liquid Glass feature

The base template will include:

- Project context references
- Architecture patterns from existing code
- Design system compliance (Liquid Glass)
- Testing requirements
- Success criteria with validation commands

### 3. Create Examples Directory

Set up `examples/` directory with representative code patterns from the Noty project:

**Examples to create:**

- `examples/README.md` - Index explaining what each example demonstrates
- `examples/component_pattern.swift` - Extract pattern from `NoteCard.swift` showing SwiftUI component structure
- `examples/manager_pattern.swift` - Extract pattern from `NotesManager.swift` showing state management with @Published properties
- `examples/glass_effects_pattern.swift` - Extract patterns from `GlassEffects.swift` showing Liquid Glass implementation
- `examples/view_architecture.swift` - Extract pattern from `ContentView.swift` showing view composition and state flow

These examples demonstrate:

- Component structure (props → computed properties → body)
- State management with @StateObject/@EnvironmentObject
- Liquid Glass effect application
- Testing patterns from existing tests

### 4. Create INITIAL Template Files

Create templates for feature requests:

**Files:**

- `INITIAL.md` - Blank template with sections for FEATURE, EXAMPLES, DOCUMENTATION, and OTHER CONSIDERATIONS
- `INITIAL_EXAMPLE.md` - Complete example showing how to request a new feature (e.g., "Add voice note recording with Liquid Glass UI")

The template guides users to:

- Describe features with specific requirements
- Reference relevant example files
- Include documentation links (Figma, Apple docs)
- Note project-specific considerations (iOS 26+, Liquid Glass compliance)

### 5. Integrate PRPs-Agentic-Eng Workflows

Based on the PRPs-agentic-eng repository structure, create:

**Files:**

- `PRPs/workflows/agentic_development.md` - Workflow for multi-agent development patterns
- `PRPs/workflows/validation_loops.md` - Self-correcting validation patterns
- `PRPs/workflows/context_gathering.md` - Systematic context collection before implementation

These workflows enable:

- Breaking complex features into agent-friendly tasks
- Automated validation and self-correction
- Comprehensive context gathering from codebase

### 6. Create Context Engineering Guide

Document the system:

**File:**

- `CONTEXT_ENGINEERING.md` - Complete guide explaining:
- How to use the `/generate-prp` and `/execute-prp` commands
- Writing effective INITIAL.md files
- Understanding the PRP workflow
- Best practices for context engineering
- How examples improve AI output quality
- Integration with existing CLAUDE.md rules

### 7. Update Project Documentation

Minimal updates to connect the system:

- Add reference to `CONTEXT_ENGINEERING.md` at the top of `CLAUDE.md`
- Add note in `AGENTS.md` about the new PRP workflow
- Update `README.md` to mention the context engineering framework

## Key Design Decisions

1. **Preserve Existing CLAUDE.md**: All current project guidelines remain intact; context engineering adds a structured workflow on top
2. **SwiftUI-Specific Examples**: Examples focus on SwiftUI patterns, Liquid Glass effects, and state management specific to Noty
3. **iOS 26+ Focus**: All templates reference the project's target of iOS 26+ and macOS 26+
4. **Validation-First**: PRPs include automatic validation gates (build commands, tests) to ensure working implementations
5. **Design System Compliance**: Every PRP template includes Liquid Glass design system requirements

## Success Criteria

- Custom commands `/generate-prp` and `/execute-prp` are functional
- Example files accurately represent Noty's architecture patterns
- INITIAL template guides users to provide comprehensive feature requirements
- Generated PRPs include all necessary context for autonomous implementation
- Integration with existing documentation is seamless
- Agentic workflows enable complex multi-step implementations

## File Count Summary

Creating approximately 15-18 new files:

- 3 files in `.claude/`
- 5 files in `PRPs/templates/` and examples
- 5 files in `examples/`
- 3 workflow files
- 2 template files (INITIAL.md, INITIAL_EXAMPLE.md)
- 1 guide (CONTEXT_ENGINEERING.md)
- Minor updates to 3 existing files

### To-dos

- [ ] Create .claude/ directory with commands and settings for PRP generation and execution
- [ ] Create PRPs/ directory with base template and example PRP for Liquid Glass features
- [ ] Create examples/ directory with representative patterns from existing Noty codebase
- [ ] Create INITIAL.md template and INITIAL_EXAMPLE.md with feature request guidance
- [ ] Add PRPs-agentic-eng workflow files for multi-agent development patterns
- [ ] Write CONTEXT_ENGINEERING.md comprehensive guide for using the system
- [ ] Update CLAUDE.md, AGENTS.md, and README.md with references to context engineering framework
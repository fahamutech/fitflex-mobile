---
name: Generate Flutter Language Selection Screen
description: Mandates the exact layout, shared component hierarchy, core token discovery, and acceptance criteria for building the Language Choice UI.
---

# 1. System Scope & Boundaries
- **Target Framework:** Flutter (Dart) with strict null-safety.
- **Languages Supported:** English (EN) and Swahili (SW).
- **Core Strategy:** Prioritize discovery of existing core tokens and shared UI widgets over creating new ones.

# 2. Acceptance Criteria (Strict Enforcement)

### Visuals & Wording
The AI agent must verify that the generated screen complies with the following conditions:
- [ ] **Exact Copy:** Contains the exact title `"Choose language"`.
- [ ] **Exact Copy:** Contains the exact slogan `"Chagua lugha unayoipenda"`.
- [ ] **Radio Infrastructure:** Displays exactly two language choice radio buttons (English and Swahili).
- [ ] **Action Footprint:** Features a confirmation action button strictly anchored or arranged at the bottom of the viewport to finalize the language selection and proceed.
- [ ] **Token Compliance:** Zero hardcoded colors, padding, alignment configurations, or font weights. All layout variables must trace directly back to a core design system token file.

### Interactions & Animations
- [ ] **Motion Design:** The entire screen/components must feature a smooth entrance transition (e.g., FadeIn/SlideIn) when initializing, and an exit transition when leaving.

### Logic & State Management
- [ ] **Button State:** The "Continue" action button must be disabled by default if no language is selected. It activates immediately upon selection.
- [ ] **Mutual Exclusion:** Selecting a new language option must automatically unselect the previous choice.

# 3. Step-by-Step Execution Workflow

## Step 1: Core Analysis & Discovery
Before generating any screen views, scan the codebase (`lib/core/`, `package:core/`, or global design directories) for:
1. **Design Tokens:** Class implementations mapping out `AppColors`, `AppTheme`, `AppSpacing`, or `AppTextStyles`.
2. **Shared Components:** An existing customized Radio Button / Selection ListTile package, and a standard global action button (e.g., `PrimaryButton`, `CustomElevatedButton`).

*If found, log their paths. If missing, proceed to Step 2 to establish the fallbacks.*

## Step 2: Design Token & Shared Component Fallback (If Core is Missing)
If the project does not have a centralized design configuration, you must first create it before building the view:
- **Design Tokens:** Generate a structural theme config based on an 8-point scale (`8.0`, `16.0`, `24.0`) and high-contrast, modern WCAG AA-accessible color variables.
- **Shared Components:** Build highly flexible, modular versions of the **Custom Radio Button** and **Primary Action Button** inside a reusable directory so they are available for other screens.

## Step 3: Screen Composition & Layout Architecture
Implement the view matching this structural mockup, wrapped in a `SafeArea` and a scroll-safe layout (`SingleChildScrollView` or layout builders) to safeguard against screen overflows:


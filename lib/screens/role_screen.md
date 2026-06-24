# Component Blueprint: Role Selection Screen

## 1. Meta & Status
- **File Name:** role_selection_screen.dart
- **Target Path:** lib/features/auth/presentation/screens/
- **Status:** Approved for Implementation
- **Dependencies:** Core Design Tokens, Core Shared Components, State Management (Bloc/Riverpod/Provider)

## 2. Component Purpose & User Story
> "As a new or returning user, I want to select my specific role (Gym Member, Gym Owner, Personal Trainer, or Fitness Vendor) so that FitFlex can customize my onboarding experience and dashboard."

## 3. UI Layout & Visual Structure
The screen must feature an animated entrance. The body must be independently scrollable, while the primary action button remains statically pinned to the bottom of the viewport.

+-------------------------------------------------------------+

| [ <- Back Button ]                                          |
|                                                             |
| [Title] "Welcome to FitFlex"                                |
| [Slogan] "To get started, please tell us who you are"       |
|                                                             |
| +---------------------------------------------------------+ |
| | ( ) [Icon] Gym Member                                   | |
| | ( ) [Icon] Gym Owner                                    | |
| | ( ) [Icon] Personal Trainer                             | |
| | ( ) [Icon] Fitness Vendor                               | |
| +---------------------------------------------------------+ |
|                                                             |
| [Flexible Spacer / Scrollable Area Content]                 |
|                                                             |
| ----------------------------------------------------------- |
| [ CONTINUE BUTTON (Disabled until selection is made)      ] |
+-------------------------------------------------------------+

## 4. Acceptance Criteria (Strict Enforcement)

### Visuals & Wording
- [ ] Exact Copy: Displays the title "Welcome to FitFlex" using the design system's headline typography.
- [ ] Exact Copy: Displays the slogan "To get started, please tell us who you are" using secondary body typography. All wording must remain completely visible.
- [ ] Icons: Each radio choice must display a distinct visual icon that emphasizes and represents the specific role type.
- [ ] Scroll Behavior: The body must be fully scrollable to avoid layout overflows, but the "Continue" button must remain statically fixed at the bottom of the screen.

### Interactions & Animations
- [ ] Motion Design: The entire screen/components must feature a smooth entrance transition (e.g., FadeIn/SlideIn) when initializing, and an exit transition when leaving.
- [ ] Navigation: Includes a functional top-left Back Button that pops the navigation stack back to the language selection screen.

### Logic & State Management
- [ ] Mutual Exclusion: Exactly one radio choice can be selected at any given time. Selecting a new option must automatically unselect the previous choice.
- [ ] Button State: The "Continue" button must be disabled if no role is selected. It activates immediately upon selection.
- [ ] State Publishing: Clicking the active "Continue" button must publish the chosen role configuration to the application's global state provider so it can drive the subsequent onboarding stages.

## 5. Architectural Strategy & Token Enforcement

### 1. Token Discovery
- Extract all padding, layout gaps, sizing scales, colors, and font styles from your pre-established core design system files.
- If design tokens do not exist yet, build a base configuration file (lib/core/theme/design_tokens.dart) enforcing an 8-point spacing rule and WCAG AA high-contrast readable colors.

### 2. Component Extraction Loop
- Scan Core First: Check if CustomRadioButton (or SelectionTile) and PrimaryButton exist in lib/core/shared_widgets/.
- Refactor / Upgrade: If they exist but lack support for role icons or disabled states, refactor the existing core widgets safely. Do not write a localized custom layout duplicate just for this screen.
- Fallbacks: If missing entirely, construct them inside the global core directory so they become immediately available for other application scopes.

## 6. Verification Pipeline
1. Linting Check: Run flutter analyze to ensure strict compliance with project rules.
2. Layout Integrity: Test across small screen viewports (e.g., SE size) to verify that the static bottom button does not cause layout or yellow-and-black stripe errors.

# Component Blueprint: Login / Authentication Screen

## 1. Meta & Status
- **File Name:** auth_screen.dart
- **Target Path:** lib/features/auth/presentation/screens/
- **Status:** Approved for Implementation
- **Dependencies:** Core Design Tokens, Core Shared Components, Form Validation Helpers, Auth State Management, Navigation Service

## 2. Component Purpose & User Story
> "As a user, I want to authenticate securely using my Google account or my email / mobile number so that I can securely log into my tailored FitFlex environment."

## 3. UI Layout & Visual Structure
The view initializes with a smooth entrance animation. The layout isolates the main input fields within an easily scrollable container, keeping all text inputs visible and clear from virtual keyboard overlap.

+-------------------------------------------------------------+

| [ <- Back Button ]                                          |
|                                                             |
| [Title] "Sign In"                                           |
|                                                             |
| [ GOOGLE SIGN-IN BUTTON ]                                   |
|                                                             |
| -------------- OR --------------                            |
|                                                             |
| [Input Field: Email / Mobile Number]                       |
|                                                             |
| [ CONTINUE BUTTON (Disabled until input is valid)         ] |
|                                                             |
| [ Action Link: "Don't have an account? Create Account" ]    |
+-------------------------------------------------------------+

## 4. Acceptance Criteria (Strict Enforcement)

### Visuals & Layout
- [ ] Exact Copy: Displays the prominent title "Sign In". No slogan or subtitle is allowed on this screen.
- [ ] Input Infrastructure: Features a single, clean input field accepting both valid email addresses and mobile numbers.
- [ ] Action Points: Visibly displays the dedicated "Google Sign-In" button, the primary "Continue" button, and the "Create Account" navigational option.

### Interactions & Motion
- [ ] Motion Design: The entire screen transitions into view with a smooth entrance motion when loading, and an exit animation when popped or processing structural route changes.
- [ ] Navigation Backtrack: Includes a top-left Back Button that cleanly pops the navigation stack back to the Role Selection screen.

### Validation & Button Logic
- [ ] Reactive Field Validation: Evaluates input dynamically. It must instantly identify a valid email structure (e.g., user@domain.com) or a complete, valid mobile sequence.
- [ ] Reactive Button State: The "Continue" button must remain strictly disabled and grayed out by default. It activates instantly once a valid email / mobile pattern is entered.

### Network Operations & Loading States
- [ ] Interaction Freezing: Clicking either "Continue" or "Google Sign-In" triggers a loading indicator (e.g., inline button spinner or blocking overlay). It must disable all input fields and alternative buttons to prevent duplicate submission requests.
- [ ] Service Routing: Triggering Google Sign-In executes the third-party provider integration service. Triggering the primary Continue button dispatches the payload to the respective REST/GraphQL backend authentication endpoint.
- [ ] Error Handling Dialog: If the backend service returns any error payload (e.g., 401 Unauthorized, 404 User Not Found, or Timeout issues), the system must map it to a clean UI alert dialog with an explicit close option.

## 5. Architectural Strategy & Token Enforcement

### 1. Token Discovery & Internationalization
- Look for typography, colors, padding parameters, and text scaling limits inside the pre-existing `lib/core/shared/` design engine.
- If these keys are not established, you must register them in your global core theme setup before formatting the screen.
- Ensure all static UI text keys are prepared for future translations via localization keys.

### 2. Component Reuse Loop
- Scan Core First: Locate existing implementations of custom input containers (`CustomTextField`), social login variants (`GoogleButton`), loading mechanisms, or modal dialog builders (`CustomDialog`).
- Refactor Strategy: Update existing core components to cleanly adapt to disabled or loading parameters if they do not support them. Do not create isolated layout copies for this specific screen.
- Fallback Framework: If any component is absent from your workspace, create it globally inside the shared core features directory so it stands ready for other views.

## 6. Verification & Automated Test Cases
Your unit/widget tests must successfully assert the following:
1. Smoke View Test: Verify visibility of the title "Sign In", input controls, social button, main action button, and the registration link.
2. Form Input Check: Verify that inputting faulty email configurations or incomplete mobile sequences keeps the Continue button safely disabled.
3. Edge Case Error Verification: Mock a backend error code to confirm that an alert dialog presents the error details to the user without breaking screen state or rendering overflow stripes.

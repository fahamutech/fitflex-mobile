# Component Blueprint: Email/Mobile OTP Verification Screen

## 1. Meta & Status
- **File Name:** email_auth_screen.dart
- **Target Path:** lib/features/auth/presentation/screens/
- **Status:** Approved for Implementation
- **Dependencies:** Core Design Tokens, Core Shared Components, Security PIN Utilities, Navigation Service

## 2. Component Purpose & User Story
> "As a user validating my authentication, I want to view my entered email/mobile identifier and input a secure 4 or 6-digit verification PIN using a custom on-screen keypad so that my entry is secure and accurate."

## 3. UI Layout & Visual Structure
The view initializes with a smooth entry motion. The design layers the user's previously entered credentials at the top, a clean visual row indicating the PIN length, a custom grid keypad in the middle, and an auxiliary rescue link anchored at the bottom.

+-------------------------------------------------------------+

| [ <- Back Button ]                                          |
|                                                             |
| [Display Only: User Email or Mobile Number from Auth Screen]|
|                                                             |
|    _   _   _   _   (_   _) <--- (Dynamic 4 or 6 Slot Line)  |
|                                                             |
|                      [ CUSTOM KEYPAD ]                      |
|                        1      2      3                      |
|                        4      5      6                      |
|                        7      8      9                      |
|                     [Delete]  0     [OK (Active >=4 digits)]|
|                                                             |
| [ Action Link: "Forgot Password? Reset" ]                   |
+-------------------------------------------------------------+

## 4. Acceptance Criteria (Strict Enforcement)

### Visuals & Layout
- [ ] Contextual Echo: Visibly renders the exact email or mobile phone string passed directly from the parent `auth_screen` at the top of the interface.
- [ ] Input Indicators: Features clean, separate placeholder lines representing each slot for the user's PIN digits (supports dynamic configurations of either a 4 or 6-digit matrix).
- [ ] System Restraints: Explicitly disables the default device operating system keyboard. The focus node must not invoke the system keyboard layout.

### Custom On-Screen Keypad
- [ ] Number Matrix: Displays a readable layout containing digit selectors from 0 through 9.
- [ ] Left Anchor Action: Features a structural "Delete" button positioned on the bottom-left grid coordinate to cleanly discard the trailing digit entry.
- [ ] Right Anchor Action: Features an "OK" confirmation button positioned on the bottom-right grid coordinate.

### Keypad & Action Logic
- [ ] Gated Button State: The custom "OK" action button must stay strictly disabled and grayed out when the current string buffer is under 4 digits long. It must automatically illuminate and become active as soon as the 4th digit is input.
- [ ] Navigation Backtrack: Includes a functional top-left Back Button that cleanly pops the current stack route back to the primary authentication page.
- [ ] Rescue Pathway: Displays an accessible navigation text link at the absolute bottom of the container layout reading exactly "Forgot Password? Reset" or equivalent token variable to trigger recovery.

## 5. Architectural Strategy & Token Enforcement

### 1. Token Discovery & Theming
- Extract the sizing gaps, grid row padding, responsive alignments, colors, and typography settings entirely from your pre-established `core/shared` module design keys.
- If these specifications are absent, declare them in the global theme space before mapping out the keypad aspect ratios.

### 2. Component Reuse Loop
- Scan Core First: Look for reusable custom numeric pad components (`CustomKeypad`) or visual input segment rows (`PinInputRow`) inside `lib/core/shared_widgets/`.
- Refactor Flow: Enhance the pre-existing widget nodes safely if they lack modular support for handling custom bottom-corner layout configurations (like changing disabled states on the right button dynamically).
- Fallback Framework: If absent from the current codebase, build the custom keypad block directly within the global core directories to maximize reusability across future verification workflows.

## 6. Verification & Automated Test Cases
Your unit/widget tests must successfully assert the following:
1. Visibility Check: Confirm the user's injected email/mobile details, empty slot lines, the complete custom keypad, and the bottom reset link display flawlessly on start.
2. System Keyboard Prevention: Validate that clicking the PIN input lines does not invoke the native OS keyboard or system virtual pads.
3. Keypad Interactivity Gate: Assert that typing 1, 2, or 3 digits leaves the "OK" button completely disabled. Confirm that entering a 4th digit changes the button state to active. Confirm that pressing "Delete" immediately reverts its state back to disabled.

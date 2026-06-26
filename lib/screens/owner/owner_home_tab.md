Implement the Gym Owner Dashboard screen using the current implementation as the base. Do not rebuild from scratch unless necessary. Refactor the dashboard into a clean, enterprise-style, minimal UI using the app’s shared components and design tokens.

## Goal
Create a polished gym-owner homepage that feels professional, spacious, and easy to scan. Reduce visual clutter and avoid showing too much information at once.

## Required layout

### 1. Header
- Keep the top profile/avatar action in the header.
- Show selected gym name, e.g. `Vik100 Gym`.
- Show subtitle: `Owner Dashboard`.
- Include notification icon if already supported.
- Do not place Profile in the bottom navigation.

### 2. Greeting / Overview
- Add simple greeting section:
    - `Good morning, John`
    - Small subtitle: `Here’s your gym snapshot`
- Add a period filter chip/dropdown on the right:
    - Default: `This month`

### 3. Summary cards
Show only two main metric cards:
- `Total Members`
- `Check-ins`

Each card should include:
- Label
- Main number
- Small trend text if data exists, e.g. `12% vs last month`
- Icon on the right
- Use rounded cards, subtle border, and clean spacing.

### 4. Quick actions
Show exactly 4 action buttons in one card/row:
- `Check-in`
    - helper: `Scan member`
- `Earnings`
    - helper: `View payouts`
- `Shop`
    - helper: `Buy merchandise`
- `Members`
    - helper: `Manage members`

Important:
- Replace any `Promotions` action with `Shop`.
- Do not duplicate Members elsewhere as an action list.
- Use icons from the existing icon system.
- The row should be responsive and should not overflow on small screens.

### 5. Grow your gym card
Add a wide CTA card:
- Title: `Grow your gym`
- Subtitle: `Track performance and insights to grow your business.`
- Button: `View Reports`
- Use a soft green background/accent.

### 6. Membership insight graph
Immediately below the Grow your gym card, add a simple chart card.

Title:
- `Membership Overview`

Chart:
- Compare:
    - `Direct Members`
    - `FitFlex Roaming`
- Use either a simple line chart or bar chart.
- Show this month by default.
- Add a small useful insight below the graph:
    - `Direct Members: 82`
    - `FitFlex Roaming: 24`
    - Optional trend chips if data exists.

Empty state:
- If there is no chart data, show a clean empty state:
    - `No membership data yet`
    - `Member trends will appear after check-ins start.`

### 7. Bottom navigation
Bottom bar must contain exactly:
- `Home`
- `Gyms`
- `Members`
- `Trainers`

Remove:
- `Profile`

Profile must remain accessible only from the top header/avatar.

## UI style
- Enterprise, minimal, premium.
- Use white/light background.
- Use green as primary accent.
- Use consistent rounded corners.
- Use subtle borders instead of heavy shadows.
- Keep plenty of vertical spacing.
- Avoid large blocks of text.
- Avoid crowded grids with many cards.

## Technical requirements
- Use existing shared components where available:
    - shared app scaffold
    - shared cards
    - shared buttons
    - shared bottom navigation
    - shared icon widgets
    - shared typography
    - shared spacing
    - shared color/theme tokens
- Do not hardcode colors, font sizes, spacing, or radii if design tokens already exist.
- Make the screen responsive for common mobile sizes.
- Ensure no text overflow; use max lines and ellipsis where needed.
- Keep dark mode compatibility if the app supports it.
- Preserve existing navigation routes and connect the new quick actions to the correct pages.
- Keep existing state management pattern; do not introduce a new one.

## Acceptance criteria
- Dashboard looks cleaner and more enterprise than the current version.
- Bottom navigation is exactly: Home, Gyms, Members, Trainers.
- Profile is only in the top header.
- Quick actions are exactly: Check-in, Earnings, Shop, Members.
- Promotions is removed/replaced by Shop.
- Membership graph appears below Grow your gym card.
- No duplicate Members action list.
- No layout overflow on small screens.
- Uses shared components and design tokens.
# 白话 AI Design System

## Design Principles

Follow macOS conventions first: semantic type, system controls, materials, and
system focus feedback. The design layer stays deliberately thin so product views
keep their own content and behavior while repeated visual decisions remain
consistent.

The brand palette is provisional. Final brand color requires full-product visual
review; the current product accent remains the brand interface until then.

## Typography

Panels and settings use semantic system fonts so they respond naturally to macOS.
Compact bubbles use a 13pt medium title and 12pt regular body because their window
geometry is pixel-sensitive. User-visible body and action text must not be below
12pt. Smaller monospaced metadata is permitted only in `DEBUG` UI.

## Spacing

Shared layout rhythm uses a 4pt base: 4, 8, 12, 16, 24, and 32pt. Tokens apply to
container padding and repeated view spacing, not image geometry, fixed control
sizes, offsets, or other component-specific measurements.

## Radius

Controls use 8pt, bubbles and rows use 12pt, and large containers use 16pt. A
special geometry may keep a private radius when its shape—not its design role—
requires one.

## Color Roles

Colors describe meaning rather than a literal hue: brand, idle, watching, active,
attention, success, and error. Listening uses the solid error/attention role so
white control text maintains stable contrast independent of the material behind
the bubble.

## Pet State Colors

Idle uses neutral gray; watching uses blue; thinking and speaking share active
purple; needs-input and warning share attention brown; success uses green; error
uses deep red. This mapping is centralized without changing the existing
`PetState` contract.

Pause is a runtime mode, not an activity state. A future design should compose
`PetActivityState + PetRuntimeMode -> Pet Visual Presentation`, with `active` and
`paused` modes, instead of adding `paused` to `PetState`.

## Bubble Chrome

Pet, Tutor, and Voice bubbles share material, 12pt radius, padding, subtle border,
shadow, and transition through `BubbleChrome`. Each content view continues to own
its message, state, controls, and business callbacks.

## Motion / Reduce Motion

Micro feedback is approximately 150ms and bubble transitions approximately
300ms. Motion favors opacity and transform. With Reduce Motion enabled, bubbles
use an immediate, opacity-only change and no explicit animation.

## Accessibility Rules

Interactive icon-only controls require an accessibility label; hover help is
supplementary. Custom controls must expose a keyboard path, VoiceOver label/hint/
state and default action, plus visible system focus feedback. Text contrast targets
WCAG AA (4.5:1 for normal text), and important colors must not rely on translucent
background compositing to pass.

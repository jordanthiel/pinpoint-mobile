# Pinpoint design system

The supplied DashBite references establish the visual direction: warm white canvas, softly elevated white cards, near-black primary buttons, coral highlights, and floating dark navigation. The golf interface uses the same brand language with high-contrast controls over imagery.

## Canonical tokens

`Shared/BrandPalette.swift` owns colors for both iPhone and Watch. `Pinpoint/Theme.swift` maps them to semantic roles and defines spacing, radii, and typography. Do not introduce new one-off brand colors in screens.

- Canvas: warm off-white, approximately #F9F8F7.
- Surface: white. Inset fields: approximately #F1F0EE.
- Ink / primary actions: approximately #1D1D1C.
- Secondary text: approximately #666561.
- Coral: approximately #FF7D5E, for selected controls and graphics.
- Coral text: approximately #A83D26, for links on light backgrounds.
- Coral wash: approximately #FFE9E0, for selected score tiles and subtle emphasis.
- White is used for text on dark controls, photographs, and video. Use ink, not white, on coral-filled selection controls.

Green, red, and yellow remain semantic colors for golf outcomes, warnings, penalties, and flag visibility; they are not alternate brand accents. Course tee colors and annotation drawing colors retain their meaning.

## Components

`Pinpoint/DesignSystem.swift` provides:

- `PrimaryButtonStyle`: near-black capsule, white semibold label, minimum 52-point height, subtle shadow, explicit disabled and pressed states.
- `SecondaryButtonStyle`: neutral inset capsule, ink label, hairline edge.
- `PinpointIconButtonStyle`: 46-point circular icon control; neutral and dark variants.
- `pinpointCard()`: white, 24-point corners, subtle edge and soft shadow. Use `PlayUI.card` for padded stacks.
- `pinpointField()`: inset fill, 16-point corners, 14-point padding.
- `PinpointPageHeading`: system semibold large title and subdued subtitle.
- `PinpointNavigationRow`: leading line icon, title/subtitle, trailing chevron in a soft white card.
- `StatTile`: neutral inset metric, monospaced number, secondary labels.
- Floating navigation: black capsule, coral selected icon, visible text labels, safe-area spacing. Immersive map/video screens suppress it through `PinpointImmersiveKey`.

An Xcode preview in `DesignSystem.swift` displays the shared components together. Changes to shared components should be checked here and in a populated screen.

## Layout and typography

Use the system font with default design. Hero: large title semibold. Sections: title 2 semibold. Actions and row titles: subheadline semibold. Body and caption use Dynamic Type. Numeric metrics use monospaced digits. Do not shrink text to fit new layouts; allow wrapping and scrolling.

Spacing uses 8, 12, 16, 20, and 24 points. Pages use 20-point horizontal padding and 24-point section separation. Cards use 20-point inner padding. Forms scroll above pinned primary actions. Tappable controls should be at least 44 points.

## Context and behavior

iPhone browsing, account, score, club, voice, and review forms use the light scheme. Camera/video and satellite imagery retain dark overlays with white text. Watch remains black for legibility and battery efficiency, using the shared coral accent.

Visual changes must preserve entered scores, shot locations, penalty assignments, voice/transcription behavior, and navigation. Do not reset or create golfer data merely to show the new design. New screens should compose these components rather than copy their styles.

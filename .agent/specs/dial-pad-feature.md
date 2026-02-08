# Dial Pad Feature Spec

## Overview

**Problem Statement:** Users cannot interact with IVR (Interactive Voice Response) systems during active browser-based calls. When an answering machine says "Press 1 for sales, press 2 for support," users have no way to send DTMF (Dual-Tone Multi-Frequency) tones to navigate these systems.

**Why This Matters:** Many businesses and customer service lines use IVR systems. Without DTMF capability, users cannot complete calls that require menu navigation, significantly limiting the app's utility for real-world sales calls.

**Current State:** The calling screen has mute and end call buttons, but no DTMF input capability. The BrowserAudioSession component manages Twilio calls but doesn't expose DTMF sending functionality.

**Desired State:** A dial pad button next to the end call button that opens a modal with digit buttons (0-9, *, #). Pressing digits sends DTMF tones through the active Twilio call, enabling full IVR interaction.

---

## Requirements

### Requirement 1: Dial Pad Button

**User Story:** As a sales rep on a call, I want to access a dial pad, so that I can interact with IVR systems.

#### Acceptance Criteria

1. **WHEN** a call is active **THE** System **SHALL** display a dial pad icon button to the right of the End Call button
2. **THE** dial pad button **SHALL** use the `hover:scale-95 active:scale-90` press-in effect pattern matching the mute button
3. **THE** dial pad button **SHALL** be styled consistently with the mute button (simple icon, theme-text-primary)
4. **WHEN** the user clicks the dial pad button **THE** System **SHALL** open a modal/popup with the dial pad interface

### Requirement 2: Dial Pad Modal Interface

**User Story:** As a user, I want a standard telephone dial pad layout, so that I can easily input digits.

#### Acceptance Criteria

1. **THE** modal **SHALL** display a 3x4 grid layout matching a standard telephone dial pad:
   - Row 1: 1, 2, 3
   - Row 2: 4, 5, 6
   - Row 3: 7, 8, 9
   - Row 4: *, 0, #
2. **EACH** digit button **SHALL** display its character prominently
3. **EACH** digit button **SHALL** use the press-in hover effect (`hover:scale-95 active:scale-90`)
4. **THE** modal **SHALL** include a close button or close when clicking outside the modal
5. **THE** modal **SHALL** use theme colors (theme-bg-secondary, theme-text-primary) with backdrop-blur for consistency

### Requirement 3: DTMF Tone Sending

**User Story:** As a user pressing dial pad buttons, I want the digits to actually be sent to the call, so that the IVR system receives my input.

#### Acceptance Criteria

1. **WHEN** a digit button is clicked **THE** System **SHALL** send the corresponding DTMF tone through the active Twilio call
2. **THE** DTMF sending **SHALL** use Twilio's `sendDigits()` method on the active call object
3. **WHEN** the DTMF tone is sent **THE** System **SHALL** provide visual feedback (button press animation, brief highlight)
4. **IF** DTMF sending fails **THE** System **SHALL** log the error and show a brief error toast
5. **THE** dial pad **SHALL** only be functional when a call is active (callStatus.status === 'active')

### Requirement 4: Error Handling

**User Story:** As a user, I want clear feedback if DTMF sending fails, so that I know the system is working.

#### Acceptance Criteria

1. **WHEN** DTMF sending fails **THE** System **SHALL** display a user-friendly error message
2. **THE** System **SHALL** log DTMF errors to Sentry with 'dtmf' category tag
3. **THE** System **SHALL** handle edge cases:
   - No active call (button disabled or hidden)
   - Call disconnected while dial pad is open (close modal)
   - Twilio SDK not initialized (disable dial pad)

---

## Design

### Architecture

```
App.tsx (Calling Screen)
├── Mute Button (existing)
├── End Call Button (existing)
└── Dial Pad Button (new)
    └── DialPadModal (new component)
        ├── Close Button
        └── Dial Pad Grid
            ├── Row 1: [1] [2] [3]
            ├── Row 2: [4] [5] [6]
            ├── Row 3: [7] [8] [9]
            └── Row 4: [*] [0] [#]
                └── onClick → sendDTMF(digit)
                    └── BrowserAudioSession.sendDigits(digit)
                        └── activeCall.sendDigits(digit) [Twilio SDK]
```

### Key Files

- `src/App.tsx` - Add dial pad button next to end call button (lines ~2379-2405), add state for modal visibility
- `src/components/DialPadModal.tsx` - New component for the dial pad modal interface
- `src/components/BrowserAudioSession.tsx` - Expose `sendDigits()` method via ref/imperative handle

### Implementation Notes

1. **Twilio SDK DTMF:** The Twilio Device SDK's Call object has a `sendDigits()` method that accepts a string of DTMF digits (e.g., "123", "#")
2. **BrowserAudioSession Integration:** The `activeCall` state holds the Twilio Call object. Pass a ref or callback from App.tsx to access `sendDigits()`
3. **Modal Styling:** Follow the pattern in `AudioSourcePopup.tsx` for modal backdrop styling (theme-bg-secondary with backdrop-blur, no bg-black/50)
4. **Button Styling:** Follow the mute button pattern in App.tsx lines 2382-2396
5. **State Management:** 
   - Add `isDialPadOpen` state in App.tsx
   - Pass `onSendDTMF` callback to DialPadModal
6. **Edge Cases:**
   - Modal should auto-close if call ends while open
   - DTMF should only work when call is active
   - Visual feedback on digit press (scale animation + color flash)

---

## Tasks

- [ ] Create `src/components/DialPadModal.tsx` component with dial pad grid layout (Req 1, 2)
- [ ] Expose `sendDigits()` method from BrowserAudioSession via ref/imperative handle (Req 3)
- [ ] Add dial pad button to App.tsx calling screen next to end call button (Req 1)
- [ ] Implement state management for dial pad modal visibility (Req 1)
- [ ] Connect digit buttons to DTMF sending via BrowserAudioSession (Req 3)
- [ ] Add visual feedback animations for digit presses (Req 3)
- [ ] Implement error handling and logging for DTMF failures (Req 4)
- [ ] Add logic to disable/hide dial pad when call is not active (Req 1, 4)
- [ ] Test DTMF functionality with actual IVR systems
- [ ] Add data-testid attributes for E2E testing

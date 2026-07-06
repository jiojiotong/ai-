# AI Composition Camera Design

## Overview

This project is a new native iOS camera app focused on real-time AI-assisted photo composition. The first version validates the core shooting experience: helping the user compose before taking a photo.

The app combines two analysis layers:

- On-device real-time composition guidance for low-latency overlays and short tips.
- GPT-based current-frame analysis for more natural, photography-coach-style suggestions.

The first version does not include post-shot critique, image editing, filters, beauty effects, social sharing, accounts, subscriptions, or custom model training.

## Goals

- Provide real-time composition feedback while the camera preview is active.
- Support portrait, landscape/street, and general subject composition scenarios.
- Show visual overlays and one short actionable suggestion without distracting from shooting.
- Allow GPT analysis of the current camera frame through manual and configurable automatic triggers.
- Keep real-time camera usability independent of network quality or GPT latency.

## Non-Goals

- No post-capture GPT review or photo critique.
- No custom model training in the first version.
- No cloud photo library or user account system.
- No beautification, retouching, filters, or generative image editing.
- No frame-by-frame GPT analysis.
- No Android or cross-platform implementation in the first version.

## Target Platform

- Native iOS app.
- Primary target devices: iPhone 13 and newer.
- Implementation language and UI framework: Swift and SwiftUI.
- Camera pipeline: AVFoundation.
- On-device visual analysis: Apple Vision.
- Local configuration: UserDefaults or a lightweight observable settings store.

## Product Experience

### Camera Screen

The camera screen is the main product surface. It contains:

- Live camera preview.
- Composition overlays such as rule-of-thirds grid, subject bounding box, face/body guide, horizon guide, and directional hints.
- One short real-time suggestion, such as "Move the subject slightly right" or "Level the horizon".
- A shutter button.
- A manual GPT analysis button, labeled like "AI Look" or "AI Analyze".
- A settings entry.

The camera remains responsive while analysis is running. GPT loading state appears as a small non-blocking indicator.

### Settings Screen

Settings control GPT behavior and guidance intensity:

- GPT analysis mode: off, manual only, automatic only, manual plus automatic.
- Automatic GPT interval: 5 seconds, 10 seconds, 15 seconds, or 30 seconds.
- Automatic trigger condition: only analyze when the frame is stable.
- Guidance categories: portrait, landscape/street, and general subject.
- Overlay intensity: minimal, normal, or detailed.
- OpenAI API key configuration for the first local prototype.
- Privacy notice explaining that GPT analysis uploads the current frame to the configured API provider.

The default mode is manual GPT analysis enabled and automatic GPT analysis disabled.

## Architecture

```text
Camera preview frames
  -> FrameSampler
  -> VisionAnalyzer
  -> CompositionEngine
  -> OverlayRenderer + TipPresenter

Manual or automatic GPT trigger
  -> CurrentFrameCapture
  -> FrameCompressor
  -> GPTCompositionAdvisor
  -> GPTAdvicePresenter
```

## Components

### CameraView

Owns the main camera UI. It displays the camera preview, overlays, current real-time tip, GPT advice panel, shutter button, manual GPT button, and settings link.

It does not contain composition logic directly. It consumes state from the camera session, composition engine, and GPT advisor.

### CameraSessionController

Wraps AVFoundation session setup and frame delivery. It manages camera authorization, session lifecycle, preview output, and still image capture.

It emits sample buffers for on-device analysis and exposes a way to capture the current frame for GPT analysis.

### FrameSampler

Controls analysis frequency so Vision does not run on every raw camera frame. For iPhone 13 and newer, the initial target is around 10 to 15 analysis passes per second for lightweight local rules, with adaptive throttling if the device heats up or frame processing falls behind.

### VisionAnalyzer

Runs Apple Vision requests on sampled frames. The first version should support:

- Face detection.
- Human body or person detection where available.
- Salient object or subject bounding region where available.
- Rectangle/edge cues for horizon and strong structural lines.
- Basic image geometry such as frame size, orientation, and normalized coordinates.

The analyzer returns structured observations. It does not decide user-facing advice.

### CompositionEngine

Converts observations into composition rules, scores, overlays, and short suggestions.

Each rule produces:

- `id`
- `category`
- `score`
- `confidence`
- `priority`
- `suggestion`
- `overlay`

The engine selects the highest-priority actionable suggestion for display. This keeps the camera screen calm and avoids overwhelming the user.

Initial rule groups:

- General subject: subject size, subject edge distance, center composition, thirds alignment, empty-space balance.
- Portrait: face position, eye-line placement, headroom, body crop risk, face too close to edge.
- Landscape/street: horizon tilt, horizon vertical placement, major line tilt, subject-to-thirds relationship, excessive dead space.

### OverlayRenderer

Draws lightweight visual guidance over the camera preview:

- Rule-of-thirds grid.
- Subject bounding box.
- Face/body guide.
- Horizon guide.
- Directional movement arrow.

Overlay drawing uses normalized coordinates from the analysis pipeline and maps them to preview coordinates.

### GPTCompositionAdvisor

Provides GPT-based current-frame composition advice. It is triggered manually from the camera screen or automatically based on settings.

For each request, it sends:

- A low-resolution JPEG of the current camera frame.
- Optional structured local analysis results from VisionAnalyzer and CompositionEngine.
- A compact prompt asking for one to three actionable composition suggestions.

The GPT advisor should not block camera preview or local guidance. It should support cancellation, timeout handling, and request throttling.

### SettingsStore

Stores user preferences for analysis modes, intervals, overlays, guidance categories, and API key configuration. The first local prototype can use UserDefaults.

## GPT Behavior

GPT is used for semantic and natural-language composition advice, not for continuous real-time control.

Manual mode:

- User taps the GPT analysis button.
- App captures the current frame.
- App sends the compressed image and local observations to GPT.
- App displays concise advice when the response returns.

Automatic mode:

- User enables automatic GPT analysis in settings.
- App waits until the frame is stable.
- App triggers at the configured interval.
- App skips requests if one is already in flight or if the scene has not meaningfully changed.

Recommended initial GPT prompt behavior:

- Return advice in Chinese by default.
- Limit response to one to three short suggestions.
- Prefer actionable camera movement or framing guidance.
- Avoid post-shot editing suggestions.
- Avoid verbose explanations unless the user later requests a learning mode.

## Data Flow

1. CameraSessionController receives live camera frames.
2. FrameSampler selects frames for local analysis.
3. VisionAnalyzer extracts visual observations.
4. CompositionEngine scores composition and emits overlays plus the top suggestion.
5. CameraView displays overlays and the current suggestion.
6. If GPT is triggered, CurrentFrameCapture captures the latest frame.
7. FrameCompressor creates a low-resolution JPEG.
8. GPTCompositionAdvisor sends the frame and local analysis context to GPT.
9. CameraView displays GPT advice separately from instant local tips.

## Error Handling

- Camera permission denied: show a clear permission request state and link to Settings.
- Camera unavailable: show a recoverable error message.
- Vision analysis failure: keep preview active and hide only affected overlays.
- GPT API key missing: show settings prompt when GPT analysis is requested.
- GPT network failure: show a short non-blocking error and keep local guidance active.
- GPT timeout: cancel the request and allow retry.
- Automatic GPT rate limit: skip requests rather than queueing many stale frames.

## Privacy And Security

- On-device real-time analysis never uploads frames.
- GPT analysis uploads only the current frame when manually triggered or when automatic mode is enabled.
- The app must show a clear privacy notice before GPT analysis is enabled.
- First prototype API key storage can be local only, but production should use a backend proxy to avoid exposing keys in the app bundle or device storage.
- The app should compress images before upload to reduce data exposure, latency, and cost.

## Testing Strategy

### Unit Tests

- CompositionEngine rule scoring with synthetic observations.
- Suggestion priority selection.
- SettingsStore defaults and persistence.
- GPT request-building prompt content without making real network calls.

### Integration Tests

- Camera authorization state transitions.
- VisionAnalyzer handling of sample images.
- Overlay coordinate mapping from normalized coordinates to preview coordinates.
- GPT error handling with mocked responses, timeouts, and failures.

### Manual Validation

- Portrait subject centered, off-center, too close, and cropped.
- Landscape with level and tilted horizon.
- Street/general subject near thirds, centered, too small, and too close to edge.
- GPT manual analysis in good network, poor network, missing key, and timeout states.
- Automatic GPT analysis with 5, 10, 15, and 30 second intervals.

## First Implementation Boundary

The first build should prove the end-to-end loop:

- Launch app and open camera preview.
- Display real-time overlays and one local composition suggestion.
- Open settings and configure GPT mode and interval.
- Tap manual GPT analysis and receive current-frame advice.
- Enable automatic GPT analysis and receive low-frequency current-frame advice while the camera remains responsive.

Anything outside this loop is deferred.

## Future Extensions

- Replace or augment rules with a Core ML aesthetic/composition scoring model.
- Add a learning mode with longer GPT explanations.
- Add more scene categories such as food, product, architecture, and night shots.
- Add backend proxy for API key protection and usage control.
- Add personalization based on preferred composition style.

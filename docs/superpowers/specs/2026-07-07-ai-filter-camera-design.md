# AI Filter Camera Design

## Overview

The app should remain a standalone iOS camera experience: opening the app shows the camera, the user can take a photo immediately, and AI can analyze the current frame for composition and filter choice.

This extension adds a real-time filter pipeline and AI-assisted filter recommendation on top of the existing AI composition camera. The first implementation should prioritize a reliable end-to-end shooting experience over a large editing suite.

## Goals

- Show selected filters in the live camera preview.
- Save photos with the same selected filter applied.
- Provide a practical set of built-in filters suitable for portraits, street scenes, landscapes, food, night scenes, and black-and-white shots.
- Let GPT recommend one filter while it provides composition advice.
- Keep local Vision composition analysis working while filters are enabled.
- Preserve a path for copied GitHub filter source or parameters when the license is clear.

## Non-Goals

- No post-capture editor in this phase.
- No beauty retouching or face reshaping.
- No video recording or video filters.
- No account system, cloud album, or subscription logic.
- No hard dependency on a large third-party camera app that would replace the current app architecture.

## GitHub Filter Research

Relevant repositories found during initial research:

- `Yummypets/YPImagePicker`: Swift, MIT license, Instagram-like image picker and filters. Good reference for filter UX and simple filter handling.
- `kxvn-lx/Kontax-Cam`: Swift, Apache-2.0 license, instant camera effects and filters. Good reference for film/instant camera style presets.
- `GhostZephyr/MetalVideoProcess`: Swift, MIT license, Metal video processing based on GPUImage3. Good candidate for a later high-performance realtime filter layer.
- `GottaYotta/PixelSDK`: Swift photo/video editor, but the GitHub API reports a non-standard/unclear license. Do not copy source from this project unless the license is reviewed manually.

The implementation should not blindly copy whole projects. It should copy only small, auditable source files or parameter ideas with compatible licenses, and it must include attribution in `ThirdPartyFilters/LICENSES.md` when copied code is added.

## Architecture

```text
AVCaptureVideoDataOutput sample buffer
  -> VisionAnalyzer + CompositionEngine
  -> FilterEngine
  -> published preview image
  -> FilteredCameraPreviewView

AVCapturePhotoOutput still photo
  -> FilterEngine
  -> Photos save request

Manual or automatic GPT trigger
  -> latest original/current frame
  -> GPTCompositionAdvisor
  -> composition advice + recommended filter id
  -> CameraView displays recommendation and optional apply action
```

## Components

### PhotoFilter

Defines each available filter:

- `id`: stable string used by settings and GPT mapping.
- `title`: Chinese display name.
- `subtitle`: short usage hint.
- `category`: neutral, portrait, street, landscape, night, black-and-white, creative.
- `aiDescription`: compact description sent to GPT so it can choose a filter.

Initial filters:

- `original`: 原图, no filter.
- `vivid`: 鲜明, higher contrast and saturation.
- `warmFilm`: 暖调胶片, warm tone, softer highlights.
- `japaneseSoft`: 日系淡彩, lower contrast and light pastel color.
- `coolStreet`: 冷调街拍, cooler shadows and stronger contrast.
- `monoClassic`: 经典黑白, monochrome with moderate contrast.
- `retro`: 复古, warmer colors with muted saturation.
- `cyber`: 赛博霓虹, boosted blue/purple contrast.
- `softPortrait`: 柔和人像, gentle contrast and warmer skin-friendly tone.
- `landscapePop`: 风景增强, richer greens/blues and added clarity.

### FilterEngine

Applies filters using CoreImage as the primary stable pipeline.

The engine should expose:

- `apply(filter:to ciImage:) -> CIImage`
- `makeUIImage(from ciImage:) -> UIImage?`
- `apply(filter:to uiImage:) -> UIImage?`

Filters should be implemented as small chains of built-in CoreImage filters such as `CIColorControls`, `CITemperatureAndTint`, `CIExposureAdjust`, `CIHighlightShadowAdjust`, `CISepiaTone`, and `CIPhotoEffectMono`. This avoids adding a fragile package dependency while still allowing GitHub-inspired presets.

### FilteredCameraPreviewView

Replaces the direct `AVCaptureVideoPreviewLayer` UI for filtered mode. It displays the latest filtered preview frame with aspect-fill behavior.

The current `CameraPreviewView` can remain in the repository as a fallback or reference, but the main camera screen should use the filtered preview once the pipeline is implemented.

### CameraSessionController

Adds filter state and publishes a filtered preview image.

Responsibilities:

- Keep running AVFoundation session setup.
- Continue feeding sample buffers to VisionAnalyzer and CompositionEngine.
- Apply the selected filter to preview frames.
- Publish only the newest filtered preview image to avoid UI backlog.
- Apply the selected filter to captured still photos before saving.
- Keep `latestImage` available for GPT analysis. The first implementation should send the unfiltered or lightly compressed current frame plus local context, not every filtered frame.

### CameraView

Adds a horizontal filter selector above or near the shutter controls.

The selector should:

- Show filter names in Chinese.
- Highlight the active filter.
- Include `原图` as the first option.
- Allow one-tap switching without leaving the camera.
- Show AI recommended filter with a small `AI 推荐` badge when available.

### SettingsStore

Persists the selected filter id in `UserDefaults` so the app reopens with the last used filter.

### GPTCompositionAdvisor

Extends the current prompt to ask for both composition guidance and a filter recommendation.

The prompt should provide the allowed filter ids and descriptions. GPT should return concise Chinese advice plus one filter id. The first implementation can parse a simple text format instead of full JSON if that is more robust with the existing code, but the response must map only to known filter ids.

Recommended response shape:

```text
建议：...
滤镜：coolStreet
原因：...
```

If GPT returns an unknown filter id, the app should ignore the filter recommendation and display only composition advice.

## Data Flow

1. The app starts and requests camera permission.
2. `CameraSessionController` starts the camera session and receives sample buffers.
3. Each sampled buffer still goes through Vision and composition scoring.
4. The selected filter is applied to preview frames through `FilterEngine`.
5. `CameraView` renders the filtered preview and existing overlays.
6. The user selects filters manually from the filter strip.
7. GPT analysis sends the current frame and local composition context, along with available filter descriptions.
8. GPT returns concise composition advice and a filter id recommendation.
9. `CameraView` displays the recommendation and lets the user apply it.
10. When the user takes a photo, the selected filter is applied before saving to Photos.

## Performance Strategy

- Preview rendering should discard stale frames and show only the newest processed frame.
- Start with CoreImage filters because they use platform-optimized rendering and avoid third-party compile risk.
- Keep Vision analysis cadence close to the existing 0.08 second throttle.
- Preview image conversion should avoid excessive full-resolution rendering; still photos can use higher quality rendering.
- If live preview drops frames on device, reduce preview publish rate before reducing composition analysis quality.

## Error Handling

- Filter application failure: fall back to the original frame and keep the camera running.
- Unknown saved filter id: fall back to `original`.
- Unknown GPT filter id: ignore the recommendation.
- Third-party copied filter code fails to compile: keep it isolated under `ThirdPartyFilters` and do not wire it into the main pipeline until fixed.
- Photo save failure: keep the current existing user-facing save error behavior.

## Privacy And Security

- Local filter preview and local Vision composition analysis do not upload images.
- GPT analysis continues to upload the current frame only when manual or automatic GPT analysis is enabled.
- The privacy text should mention that GPT may recommend a filter based on the uploaded current frame.
- Copied GitHub source must keep license attribution and should not include unrelated analytics, network code, or app-specific trackers.

## Testing Strategy

### Static Checks

- `plutil -lint AICompositionCamera/Info.plist`
- `plutil -lint AICompositionCamera.xcodeproj/project.pbxproj`
- Inspect copied third-party files for license headers and unrelated dependencies.

### Manual Device Validation

- App launches directly to camera.
- Filter strip switches filters without leaving the camera.
- Live preview visibly changes for each filter.
- Existing composition overlays remain aligned enough for practical use.
- GPT manual analysis returns composition advice and can recommend a known filter.
- Applying AI recommendation changes the active filter.
- Captured photo saved to Photos matches the selected filter.
- Missing API key still shows the current settings prompt behavior.

## Implementation Boundary

The first implementation should include the built-in CoreImage filter pipeline and a license-safe folder for third-party filter sources or references. It should not attempt a full Metal/GPUImage rewrite unless CoreImage preview performance is unacceptable on a real iPhone.

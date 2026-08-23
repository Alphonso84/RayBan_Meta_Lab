# Ray-Ban Meta - NoteBuddy

## Project Type
iOS SwiftUI app for Meta Ray-Ban smart glasses enabling OCR document scanning, AI-powered summarization, and study deck organization using Meta Wearables SDK (MWDATCore, MWDATCamera) and Apple Foundation Models.

## Core Architecture

```
App Entry: Smart_GlassesApp.swift → MainTabView.swift
                                          ↓
                    ┌─────────────────────┬─────────────────────┐
                    ↓                     ↓                     ↓
               Library Tab           Scan Tab              Settings Tab
          (DeckLibraryView)    (LibraryScannerView)      (SettingsView)
                    ↓                     ↓
                    │         ┌───────────────────────┐
                    │         │   WearablesManager    │
                    │         │  - Device connection  │
                    │         │  - Video streaming    │
                    │         │  - Photo capture      │
                    │         └───────────────────────┘
                    │                     ↓
                    │         ┌───────────────────────┐
                    │         │ DocumentReaderProcessor│
                    │         │  - Boundary detection │
                    │         │  - OCR processing     │
                    │         │  - Auto-capture       │
                    │         └───────────────────────┘
                    │                     ↓
                    │         ┌───────────────────────┐
                    │         │  StreamingSummarizer  │
                    │         │  - AI summarization   │
                    │         │  - Key points extract │
                    │         └───────────────────────┘
                    │                     ↓
                    └────────→ SwiftData (SummaryCard, SummaryDeck)
```

## Key Managers & Singletons

| Class | File | Purpose |
|-------|------|---------|
| `WearablesManager.shared` | WearablesManager.swift | Central hub: device connection, stream control, photo capture |
| `VoiceFeedbackManager.shared` | Audio/VoiceFeedbackManager.swift | TTS, haptics, audio cues for feedback |
| `StreamingSummarizer` | Services/StreamingSummarizer.swift | Apple Foundation Models AI summarization |
| `PDFGenerator` | Services/PDFGenerator.swift | Export cards/decks as PDF |

## Document Scanning Flow

```
User enters Scan tab
        ↓
MainTabView.handleStreamForTab() → WearablesManager.startStream()
        ↓
Video frames arrive → WearablesManager.latestFrameImage
        ↓
LibraryScannerView displays live preview
        ↓
DocumentReaderProcessor.processFrameForAutoCapture() (every 3rd frame)
        ↓
VNDetectDocumentSegmentationRequest → boundary detection
        ↓
If document stable → triggerHighResPhotoCapture()
        ↓
WearablesManager.capturePhoto() → high-res image
        ↓
DocumentReaderProcessor.captureAndProcess()
  ├── Perspective correction (CIPerspectiveCorrection)
  ├── Image preprocessing (grayscale, contrast)
  └── OCR (VNRecognizeTextRequest)
        ↓
DocumentReadingResult with extracted text
        ↓
StreamingSummarizer.summarize() → summary, key points, title
        ↓
Save SummaryCard to SwiftData
        ↓
User views card in Library
```

## Multi-Page Scanning Flow

```
First page captured → showPageCapturedOptions = true
        ↓
User taps "Add Page"
        ↓
processor.addPageToSession()
  ├── Increment page count
  ├── Accumulate text
  └── Store thumbnail
        ↓
Reset for next page capture
        ↓
Repeat for additional pages...
        ↓
User taps "Done"
        ↓
finishMultiPageSession()
        ↓
Summarize combined text from all pages
        ↓
Save single card with all page content
```

## Key Data Models

```swift
// SwiftData Models
@Model SummaryCard {
    id: UUID
    title: String
    summary: String
    keyPoints: [String]
    sourceText: String
    pageNumber: Int?
    thumbnailData: Data?
    createdAt: Date
    deck: SummaryDeck?
}

@Model SummaryDeck {
    id: UUID
    title: String
    deckDescription: String?
    colorHex: String           // 6-digit hex color
    cards: [SummaryCard]       // Cascade delete
    createdAt: Date
    lastAccessedAt: Date
    isQuickCapture: Bool       // Special "Quick Capture" deck
    deckSummary: String?       // Aggregated deck summary
    deckKeyPoints: [String]?   // Key themes across all cards
}

// Document Processing
struct DocumentReadingResult {
    extractedText: String
    documentBoundary: VNRectangleObservation?
    textBlocks: [TextBlock]
    confidence: Float
    processedImage: CGImage?
}

struct TextBlock {
    text: String
    boundingBox: CGRect
    confidence: Float
}

// Summarizer Output
struct DocumentSummaryOutput {
    summary: String           // 1-3 sentences
    keyPoints: [String]       // 3-5 bullet points
    suggestedTitle: String    // Auto-generated title
    documentType: String      // article, letter, receipt, etc.
}

// Processor States
enum DocumentReaderState {
    case idle, detecting, processing, captured, error(String)
}

enum SummarizerState {
    case idle, preparing, summarizing, complete, error(String)
}
```

## File Structure

```
Smart Glasses/
├── Smart_GlassesApp.swift          # App entry, SwiftData container
├── WearablesManager.swift          # Central manager singleton
├── WearablesConfig.swift           # Meta SDK initialization
├── AppIntents.swift                # Siri Shortcuts support
│
├── Models/
│   ├── SummaryCard.swift           # SwiftData card model
│   └── SummaryDeck.swift           # SwiftData deck model
│
├── DocumentReader/
│   ├── DocumentReaderProcessor.swift  # OCR pipeline, auto-capture
│   └── DocumentReadingResult.swift    # Result structs
│
├── Services/
│   ├── StreamingSummarizer.swift   # Apple Foundation Models
│   └── PDFGenerator.swift          # PDF export
│
├── Audio/
│   └── VoiceFeedbackManager.swift  # TTS, haptics, sounds
│
└── Views/
    ├── MainTabView.swift              # Tab navigation (Library/Scan/Settings)
    ├── SettingsView.swift             # Connection, preferences
    ├── DocumentBoundaryOverlay.swift  # Real-time boundary visualization
    │
    ├── DeckLibrary/
    │   ├── DeckLibraryView.swift      # Main library grid
    │   ├── DeckDetailView.swift       # Card carousel, playback
    │   └── LibraryScannerView.swift   # Scanning interface
    │
    └── DocumentScanner/
        └── CardPreviewSheet.swift     # Save card dialog
```

## UI Components

### MainTabView (Tab Navigation)
```
┌─────────────────────────────────────────────┐
│  [Library]    [Scan]    [Settings]          │  ← Tab bar
└─────────────────────────────────────────────┘
```

### LibraryScannerView (Scan Tab)
```
┌─────────────────────────────────────────────┐
│  [Auto-Capture Toggle]                      │  ← Top bar
├─────────────────────────────────────────────┤
│                                             │
│         Live Video Feed                     │
│         + DocumentBoundaryOverlay           │
│         (boundary polygon, stability ring)  │
│                                             │
├─────────────────────────────────────────────┤
│  Status: "Hold steady..." / "Captured!"    │
│  [Streaming summary text appears here]      │
├─────────────────────────────────────────────┤
│  Multi-page: [Page 1] [Page 2] thumbnails  │
├─────────────────────────────────────────────┤
│  [Add Page]  [Done]  [Skip]                │  ← After capture
└─────────────────────────────────────────────┘
```

### DeckLibraryView (Library Tab)
```
┌─────────────────────────────────────────────┐
│  X Decks • Y Cards • Z Unsorted            │  ← Stats
├─────────────────────────────────────────────┤
│  Quick Capture                              │
│  [Card] [Card] [Card] →                    │  ← Horizontal scroll
├─────────────────────────────────────────────┤
│  Decks                            [+ New]   │
│  ┌──────┐  ┌──────┐                        │
│  │ Deck │  │ Deck │                        │  ← 2-column grid
│  │ ■■■■ │  │ ■■■■ │                        │
│  └──────┘  └──────┘                        │
└─────────────────────────────────────────────┘
```

### DeckDetailView (Card Carousel)
```
┌─────────────────────────────────────────────┐
│  [Back]   Deck Title            [Options]   │
├─────────────────────────────────────────────┤
│  ┌─────────────────────────────────────┐    │
│  │         Card Thumbnail              │    │
│  │                                     │    │
│  └─────────────────────────────────────┘    │
│  Card Title                    1 / 5        │
│  Jan 26, 2026 • 150 words                  │
├─────────────────────────────────────────────┤
│  Summary text here...                       │
│                                             │
│  Key Points:                                │
│  • Point 1                                  │
│  • Point 2                                  │
├─────────────────────────────────────────────┤
│        [◀]    [▶ Play]    [▶]              │  ← Playback controls
└─────────────────────────────────────────────┘
```

## DocumentReaderProcessor Configuration

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `documentConfidenceThreshold` | 0.5 | Minimum detection confidence |
| `textConfidenceThreshold` | 0.2 | OCR confidence (lowered for distance) |
| `stableFramesRequired` | 8 | Frames document must stay steady |
| `stabilityThreshold` | 0.03 | Maximum boundary movement allowed |
| `targetProcessingDimension` | 2500 | Optimal image size for Vision |
| `minimumTextLines` | 2 | Minimum lines to accept |
| `minimumCharacters` | 30 | Minimum chars to accept |

## Distance Mode
Toggle in Settings that adjusts OCR parameters:

| Setting | Close-up | Distance |
|---------|----------|----------|
| Processing dimension | 2000px | 2500px |
| Grayscale preprocessing | No | Yes |
| Contrast boost | No | Yes (1.1x) |
| Text confidence threshold | Higher | 0.2 |

## Stability Tracking
Auto-capture uses visual stability detection:

```
Document detected → Monitor boundary corners
        ↓
Calculate movement between frames
        ↓
If movement < stabilityThreshold:
  stableFrameCount++
  Progress: stableFrameCount / stableFramesRequired
        ↓
Haptic feedback at 25%, 50%, 75%
        ↓
At 100% → Capture high-res photo
```

Visual states:
- White: No document
- Cyan: Document detected
- Yellow: Partially stable (>50%)
- Green: Ready to capture

## Key Patterns

1. **Singletons**: WearablesManager.shared, VoiceFeedbackManager.shared
2. **@MainActor**: All UI managers ensure main thread safety
3. **@Published + Combine**: Reactive state updates
4. **SwiftData @Query**: Reactive database queries with sorting
5. **async/await**: All async operations
6. **Task-based concurrency**: Background processing with proper cancellation
7. **Frame throttling**: Process every 3rd frame to reduce CPU load

## Dependencies

| Framework | Purpose |
|-----------|---------|
| MWDATCore, MWDATCamera | Meta Wearables SDK |
| SwiftUI | UI framework |
| SwiftData | Persistence |
| Vision | Document detection, OCR |
| CoreImage | Image processing, perspective correction |
| AVFoundation | Audio feedback, TTS |
| AppIntents | Siri Shortcuts |
| Foundation Models | AI summarization (iOS 26+) |

## Siri Shortcuts (AppIntents)

`ScanDocumentIntent`:
- Opens app, waits for stream
- Captures and processes document
- Returns extracted text
- Phrases: "Scan document with Smart Glasses"

## Common Tasks

| Task | Location |
|------|----------|
| Adjust OCR sensitivity | DocumentReaderProcessor configuration parameters |
| Modify summarization prompts | StreamingSummarizer.summarize() |
| Change TTS behavior | VoiceFeedbackManager |
| Add new deck colors | SummaryDeck.presetColors |
| Modify auto-capture timing | DocumentReaderProcessor.stableFramesRequired |
| Change PDF layout | PDFGenerator |
| Add new tab | MainTabView |

## Tests

`Smart GlassesTests` is a Swift Testing bundle hosted by the app. It uses a
**file-system synchronized group**, so a new `.swift` file dropped in the folder
is picked up automatically — there is nothing to register in the project file.

```
xcodebuild test -project "Smart Glasses.xcodeproj" -scheme "Smart Glasses" \
  -destination 'platform=iOS Simulator,id=<an iOS 27 sim UDID>'
```

Target simulators by UDID: several share the name "iPhone 17 Pro" across iOS
17/26/27 and `name=` resolves to one that fails the iOS 27 deployment target.

| Suite | Covers |
|-------|--------|
| `CaptureRulesTests` | `isSummarizable` / `canStandOnImageAlone`, `CaptureMode`, ISBN detection |
| `SearchMatchingTests` | `StudyEntityStore.searchTerms` / `matches` — Siri and Spotlight fallback lookup |
| `TokenBudgetTests` | Budget arithmetic and greedy batch packing |
| `DocumentBoundaryTests` | Vision (bottom-left) → SwiftUI (top-left) coordinate conversion |
| `DeckTests` | Summary/flashcard staleness, aggregation, hex colors |
| `SummaryCardTests` | Spoken text, preview truncation |
| `StudyEntityTests` | What Spotlight is given, including the deliberate `sourceText` exclusion |
| `PageVisionImageTests` | Attachment downscaling |

Two seams exist purely for tests, both with defaults so callers are unaffected:
`DocumentReadingResult.isSummarizable(in:visionSupported:)` and
`TokenBudget.pack(_:into:measuring:)`. The real values depend on the device's
model variant and tokenizer, which vary between devices on the same OS.

Tests must stay free of model inference, network, and glasses hardware.

## Reference Docs

| File | Read it before |
|------|----------------|
| `AGENTS.md` | Touching any MWDAT SDK code — session lifecycle, `Stream`/`Camera` setup, photo capture, permissions/registration, MockDeviceKit, Display, Info.plist keys. Verbatim copy of the upstream [meta-wearables-dat-ios](https://github.com/facebook/meta-wearables-dat-ios) AGENTS.md; treat it as the API source of truth over memory. |
| `AppleFoundationModels.md` | Changing summarization / guided generation in `StreamingSummarizer`. |

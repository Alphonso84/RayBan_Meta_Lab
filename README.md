<h1 align="center">Ray-Ban Meta - NoteBuddy</h1>

Imagine reading a book or document and your AI assistant has the ability to summarize, save, and quiz you on what you read. Well Notebuddy does just that. Notebuddy is a iOS application that pairs with Ray-Ban Meta smart glasses (via [Meta Wearables SDK](https://github.com/facebook/meta-wearables-dat-ios)) to transform physical documents into AI-summarized study cards. Scan documents hands-free through your smart glasses — or use your phone's camera as a fallback — extract text with OCR, generate intelligent summaries, and organize content into study decks with quiz mode.

Supports dual AI providers: [Apple Foundation Models](https://developer.apple.com/documentation/FoundationModels) for fully on-device, offline summarization, and OpenAI for cloud-powered summarization, text-to-speech, and quiz generation.

## Features

### Document Scanning
<p align="center">
  <img src="Smart%20Glasses/IMG_4942.PNG" width="250" />
</p>
- **Hands-Free Scanning**: Use Meta Ray-Ban smart glasses camera for document capture
- **Phone Camera Fallback**: Use your iPhone's built-in camera when glasses aren't connected
- **Auto-Capture Mode**: Automatically detects document boundaries and captures when stable
- **Multi-Page Support**: Scan multiple pages and combine them into a single summary card
- **Real-Time Boundary Detection**: Visual overlay shows detected document edges with color-coded stability
- **Distance Mode**: Enhanced OCR processing with upscaling, grayscale, and adaptive thresholding
- **Perspective Correction**: Automatic skew correction for angled documents

### AI-Powered Summarization (Dual Provider)
<p align="center">
  <img src="Smart%20Glasses/IMG_4943.PNG" width="250" />
</p>
- **Apple Intelligence (On-Device)**: Uses Foundation Models for privacy-preserving, offline summarization (iOS 26+)
- **OpenAI (Cloud)**: Supports gpt-4o-mini, gpt-4, and custom models for cloud summarization
- **Streaming Output**: Watch summaries generate in real-time, token by token
- **Smart Extraction**: Automatically generates titles, summaries (1-3 sentences), and key points (3-5 bullets)
- **Document Classification**: Identifies document type (article, letter, receipt, etc.)
- **Deck-Level Summaries**: Aggregate summaries and key themes across all cards in a deck using map-reduce for large decks

### Quiz Mode
<p align="center">
  <img src="Smart%20Glasses/IMG_5347.PNG" width="250" />
</p>
- **Multiple-Choice Questions**: Generate 10+ questions from deck content for active recall study
- **Dual AI Support**: Generate quizzes with OpenAI or Apple Intelligence, with fallback generation from key points
- **Results & Review**: Score display with percentage, review missed questions with correct answers
- **Haptic Feedback**: Tactile responses for correct and incorrect answers

### Flashcard Study Mode
<p align="center">
  <img src="Smart%20Glasses/IMG_5396.PNG" width="250" />
  <img src="Smart%20Glasses/IMG_5397.PNG" width="250" />
  <img src="Smart%20Glasses/IMG_5398.PNG" width="250" />
</p>
- **AI-Generated Flashcards**: Create study flashcards from deck content with term/question on front and answer on back
- **Realistic 3D Flip Animation**: Tap cards to flip with smooth spring animation
- **Swipe Navigation**: Swipe left/right through flashcards like physical cards
- **Print Support**: Export flashcards as PDF with 4 cards per page, formatted for double-sided printing
- **Study Tracking**: Track cards studied, flip count, and session duration

### PDF Import
- **Import PDFs as Study Cards**: Select any PDF file and automatically create one summarized card per page
- **Two Entry Points**: Import from the Library toolbar (creates a new deck) or from a deck's menu (adds cards to that deck)
- **Progress Tracking**: Real-time progress view showing streaming AI summaries as each page is processed
- **Page Thumbnails**: Each card includes a rendered thumbnail of the original PDF page
- **Smart Filtering**: Automatically skips blank or image-only pages (< 30 characters of text)

### Study Organization
- **Deck Management**: Organize cards into color-coded study decks (10 preset colors)
- **Quick Capture**: Save cards without assigning to a deck for later organization
- **Card Carousel**: Swipe through cards in a deck with playback controls
- **PDF Export**: Export individual cards as formatted, shareable PDFs
- **Search & Filter**: Find cards and decks across your entire library
- **Deck Summaries**: Generate aggregated summaries and key themes for entire decks

### Audio & Text-to-Speech
- **Apple TTS**: Built-in speech synthesis for instant feedback
- **OpenAI TTS**: High-quality cloud voices (nova, alloy, ash, coral, echo, fable, ballad, onyx, sage, shimmer)
- **Smart Audio Routing**: Automatically routes audio to glasses speakers (Bluetooth) or phone speakers based on connection state
- **Haptic & Audio Cues**: Feedback for capture success, stability progress, and errors
- **Voice Announcements**: Status updates and card content read aloud

### Siri Shortcuts
- **"Scan document with Smart Glasses"**: Hands-free scanning via Siri
- Automates the full pipeline: connect glasses, capture, OCR, summarize
- Returns extracted text and summary

---

## Requirements

### Hardware
- **iPhone** running **iOS 26+** (required for Apple Foundation Models AI summarization)
- **Meta Ray-Ban Smart Glasses** (optional — phone camera works as fallback)

### Software
- **Xcode 16+** for building
- **Meta AI App** installed on your iPhone (required to allow NoteBuddy to access the glasses)
- **Apple Developer Account** (free or paid) for code signing and deploying to your device

### Dependencies (Automatically Installed)
The following dependencies are managed via Swift Package Manager and will be **automatically downloaded** when you open the project in Xcode:

| Dependency | Purpose |
|------------|---------|
| `MWDATCore` / `MWDATCamera` | [Meta Wearables SDK](https://github.com/facebook/meta-wearables-dat-ios) (public) |

Built-in Apple frameworks used:
| Framework | Purpose |
|-----------|---------|
| `SwiftUI` / `SwiftData` | UI and persistence |
| `Vision` | Document detection and OCR |
| `CoreImage` | Image processing and perspective correction |
| `FoundationModels` | On-device AI (iOS 26+) |
| `AVFoundation` | Camera capture, audio, speech synthesis |
| `PDFKit` | PDF document generation |
| `AppIntents` | Siri Shortcuts integration |

---

## Getting Started

### Prerequisites Checklist

Before you begin, make sure you have:

- [ ] iPhone with iOS 26+ installed
- [ ] Xcode 16+ installed on your Mac
- [ ] Apple Developer Account (free accounts work for personal devices)
- [ ] Meta Ray-Ban Smart Glasses paired with your iPhone (optional)
- [ ] Meta AI App installed from the App Store (if using glasses)

### Step 1: Clone the Repository

```bash
git clone https://github.com/Alphonso84/RayBan_Meta_Lab.git
cd RayBan_Meta_Lab
```

### Step 2: Open in Xcode

```bash
open "Smart Glasses.xcodeproj"
```

When Xcode opens, it will **automatically download** the Meta Wearables SDK via Swift Package Manager. Wait for the package resolution to complete (you'll see progress in the status bar).

### Step 3: Configure Code Signing

1. Select the **Smart Glasses** project in the navigator (blue icon)
2. Select the **Smart Glasses** target
3. Go to the **Signing & Capabilities** tab
4. Check **Automatically manage signing**
5. Select your **Team** from the dropdown (sign in with your Apple ID if needed)
6. If needed, change the **Bundle Identifier** to something unique (e.g., `com.yourname.notebuddy`)

### Step 4: Enable Developer Mode on Meta AI App

On your iPhone:
1. Open the **Meta AI** app
2. Go to **Settings** > **App Info**
3. Tap the **App version number 5 times** to reveal the Developer Mode toggle
4. Enable **Developer Mode**
5. Tap **Enable** to confirm

### Step 5: Build and Run

1. Connect your iPhone to your Mac via USB
2. Select your iPhone from the device dropdown in Xcode's toolbar
3. Press **Cmd + R** (or click the Play button) to build and run
4. On first launch, trust the developer certificate on your iPhone:
   - Go to **Settings** > **General** > **VPN & Device Management**
   - Tap your developer certificate and tap **Trust**

### Step 6: Connect Your Glasses (Optional)

1. Launch the app on your iPhone
2. Navigate to the **Settings** tab
3. Tap **Connect Glasses**
4. Follow the on-screen prompts to complete registration
5. Grant camera permissions when prompted

If you don't have glasses, you can use the **Phone Camera** fallback on the Scan tab.

---

## How to Use

### Scanning Documents

1. **Open Scanner** - Tap the Scan tab (viewfinder icon)
2. **Choose Source**:
   - If glasses are connected, the glasses camera feed starts automatically
   - If not, tap **"Use Phone Camera"** to use your iPhone's camera
3. **Point at Document** - Hold a document in view
4. **Wait for Detection** - A cyan boundary appears around detected documents
5. **Hold Steady** - The progress ring fills as you hold still (boundary turns yellow, then green)
6. **Auto-Capture** - Document captures automatically when stable (or tap Manual Capture)
7. **Review Summary** - AI generates title, summary, and key points in real-time
8. **Save Card** - Choose a deck and save

### Multi-Page Scanning

1. Toggle **Multi** mode in the top bar
2. **Scan First Page** - Follow standard scanning process
3. **Add Page** - Tap "Add Page" to include and continue scanning
4. **Scan Additional Pages** - Repeat for all pages
5. **Finish** - Tap "Done" to combine all pages and summarize
6. **Skip** - Tap "Skip" to discard current page without adding

### Quiz Mode

1. Open a deck from the Library tab
2. Tap the **quiz icon** in the deck options
3. Wait for questions to generate (uses AI or key point extraction)
4. Answer multiple-choice questions
5. Review your score and missed questions
6. Retry to improve your recall

### Flashcard Study

1. Open a deck with 2+ cards from the Library tab
2. Tap the **menu (⋯)** → **"Study Flashcards"**
3. Wait for flashcards to generate (uses AI or key point extraction)
4. **Tap** a card to flip between front (question) and back (answer)
5. **Swipe left/right** to navigate between cards
6. Tap **menu** → **"Print Flashcards"** to export as PDF for printing
7. Tap **"Finish Study"** to see your session stats

### PDF Import

1. **From Library**: Tap the **"+"** button in the Library toolbar → **"Import PDF"**
2. **From a Deck**: Open a deck → tap the **menu (⋯)** → **"Import PDF"**
3. Select a PDF file from the file picker
4. Review the page count and tap **"Start Import"**
5. Watch as each page is summarized with streaming AI output
6. Cards are created automatically — one per page with title, summary, key points, and thumbnail
7. A new deck is created from the filename (Library import) or cards are added to the existing deck

### PDF Export

1. Open a card in deck detail view
2. Tap the **share/export** option
3. A formatted PDF is generated with title, summary, key points, and source text
4. Share via the iOS share sheet

### Managing Decks

1. **View Library** - Tap the Library tab (books icon)
2. **Browse Decks** - Scroll through your deck grid with stats
3. **Create Deck** - Tap **"+"** → **"New Deck"** with title, description, and color
4. **Import PDF** - Tap **"+"** → **"Import PDF"** to create a deck from a PDF file
5. **Open Deck** - Tap a deck to view its cards in a carousel
6. **Generate Deck Summary** - Tap the summary option to aggregate insights across all cards
7. **Listen** - Tap play to hear card content or deck summaries via TTS

---

## Settings

### Ray-Ban Meta Glasses
| Setting | Description |
|---------|-------------|
| Status | Connection status indicator (green/yellow/red) |
| Registration | Registration state with glasses |
| Stream | Video streaming status |
| Camera Permission | Request glasses camera access |
| Connect/Disconnect | Manage glasses pairing |

### AI Provider
| Setting | Description |
|---------|-------------|
| Provider | Apple Intelligence (on-device) or OpenAI (cloud) |
| OpenAI API Key | Stored securely in Keychain |
| OpenAI Model | Select from available models (with refresh) |
| OpenAI Voice | TTS voice selection (10 voices) |
| Test Connection | Verify OpenAI API connectivity |

### Scanning Options
| Setting | Default | Description |
|---------|---------|-------------|
| Distance Mode | ON | Enhanced processing for normal reading distance |
| Auto-Summarize | ON | Automatically generate AI summary after capture |
| Speak Summaries | OFF | Read summaries aloud via TTS |

---

## Architecture

### High-Level Overview

```
+------------------------------------------------------------------+
|                      Smart Glasses App                            |
+------------------------------------------------------------------+
|                                                                   |
|   +---------------+   +---------------+   +---------------+       |
|   |    Library    |   |     Scan      |   |   Settings    |       |
|   |      Tab      |   |      Tab      |   |      Tab      |       |
|   +-------+-------+   +-------+-------+   +-------+-------+       |
|           |                   |                   |               |
|   +-------v-------+   +-------v-------+   +-------v-------+       |
|   |  DeckLibrary  |   |LibraryScanner |   | SettingsView  |       |
|   |     View      |   |     View      |   |               |       |
|   +--+----+-------+   +--+----+-------+   +---------------+       |
|      |    |              |    |                                   |
|   +--v-+  +--v------+ +--v--+ +--v-----------+                   |
|   |Deck|  |  Quiz   | |Phone| |   Document   |                   |
|   |Det.|  |  View   | |Cam  | |   Boundary   |                   |
|   |View|  |  +------+ |Prev.| |   Overlay    |                   |
|   |    |  |  |Quiz  | |Layer| +--v-----------+                   |
|   +----+  |  |Res.  | +-----+                                    |
|           +--+------+                                             |
+------------------------------------------------------------------+
|                          SERVICES                                 |
|   +---------------+   +---------------+   +---------------+       |
|   |  Wearables    |   |   Document    |   |  Streaming    |       |
|   |   Manager     |<--|    Reader     |-->|  Summarizer   |       |
|   |  (glasses)    |   |   Processor   |   | (Apple/OpenAI)|       |
|   +---------------+   +---------------+   +---------------+       |
|   +---------------+   +---------------+   +---------------+       |
|   |  PhoneCamera  |   |    Quiz       |   |     PDF       |       |
|   |   Manager     |   |   Generator   |   |   Generator   |       |
|   |  (fallback)   |   |              |   |               |       |
|   +---------------+   +---------------+   +---------------+       |
|   +---------------+   +---------------+   +---------------+       |
|   |VoiceFeedback  |   |   OpenAI      |   |   Keychain    |       |
|   |   Manager     |   |   Provider    |   |    Helper     |       |
|   |  (TTS/haptic) |   |  (cloud AI)   |   |  (API keys)   |       |
|   +---------------+   +---------------+   +---------------+       |
+------------------------------------------------------------------+
|                        DATA LAYER                                 |
|   +-----------------------------------------------------+         |
|   |                     SwiftData                        |         |
|   |   +--------------+           +--------------+        |         |
|   |   | SummaryDeck  |<--------->| SummaryCard  |        |         |
|   |   +--------------+           +--------------+        |         |
|   +-----------------------------------------------------+         |
+------------------------------------------------------------------+
```

### Core Components

#### Entry Point
- **`Smart_GlassesApp.swift`** - App initialization, SwiftData container, URL handling

#### Views
| View | Purpose |
|------|---------|
| `MainTabView.swift` | Three-tab navigation (Library, Scan, Settings) |
| `DeckLibraryView.swift` | Deck grid with stats, search, and quick capture section |
| `DeckDetailView.swift` | Card carousel with playback controls and deck summary |
| `LibraryScannerView.swift` | Full scanner interface with auto-capture and source selection |
| `SettingsView.swift` | Glasses connection, AI provider config, scanning preferences |
| `DocumentBoundaryOverlay.swift` | Real-time boundary visualization with stability indicators |
| `CardPreviewSheet.swift` | Deck selector and card preview for saving |
| `QuizView.swift` | Multiple-choice quiz interface with progress tracking |
| `QuizResultsView.swift` | Quiz score display and missed questions review |
| `FlashcardView.swift` | Flashcard study interface with swipe navigation |
| `FlashcardCardView.swift` | Individual flashcard with 3D flip animation |
| `FlashcardStudyResultsView.swift` | Study session stats and completion screen |
| `PDFImportView.swift` | PDF import progress sheet with streaming summaries |
| `PhoneCameraPreviewLayer.swift` | UIViewRepresentable for phone camera preview |

#### Services
| Service | Purpose |
|---------|---------|
| `WearablesManager.swift` | Meta glasses connection, streaming, and photo capture (singleton) |
| `PhoneCameraManager.swift` | Phone camera fallback with AVCaptureSession |
| `DocumentReaderProcessor.swift` | Document detection, OCR, auto-capture, multi-page sessions |
| `StreamingSummarizer.swift` | AI summarization with Apple Foundation Models and OpenAI |
| `OpenAIProvider.swift` | OpenAI API for summarization, deck summaries, quiz generation, and TTS |
| `LLMProvider.swift` | Protocol abstraction for AI providers |
| `QuizGenerator.swift` | Quiz question generation from deck cards |
| `FlashcardGenerator.swift` | AI-powered flashcard generation from deck cards |
| `PDFGenerator.swift` | Formatted PDF export for cards and flashcards |
| `PDFImporter.swift` | PDF text extraction and page thumbnail rendering |
| `VoiceFeedbackManager.swift` | TTS (Apple + OpenAI), haptics, audio routing (singleton) |
| `KeychainHelper.swift` | Secure API key storage |

#### Models
| Model | Purpose |
|-------|---------|
| `SummaryCard.swift` | Study card with summary, key points, source text, thumbnail |
| `SummaryDeck.swift` | Card collection with color theme, deck summary, and key themes |
| `QuizQuestion.swift` | Quiz question with options, correct answer, and source card |
| `Flashcard.swift` | Flashcard with front/back content for study mode |
| `DocumentReadingResult.swift` | OCR result structures with text blocks and confidence |

---

## Document Processing Pipeline

```
Camera Source (Glasses or Phone)
         |
         v
+-------------------------+
|  Document Detection     |  VNDetectDocumentSegmentationRequest
|  (boundary detection)   |
+-----------+-------------+
            |
            v
+-------------------------+
|  Stability Tracking     |  8 stable frames, <3% movement
|  (auto-capture)         |  Haptic feedback at 25/50/75%
+-----------+-------------+
            |
            v
+-------------------------+
|  High-Res Photo Capture |  Glasses: StreamSession.capturePhoto()
|                         |  Phone: AVCapturePhotoOutput
+-----------+-------------+
            |
            v
+-------------------------+
|  Perspective Correction |  CIPerspectiveCorrection filter
|  (skew removal)         |
+-----------+-------------+
            |
            v
+-------------------------+
|  Image Enhancement      |  CISharpenLuminance
|  (Distance Mode only)   |  CIColorControls (contrast)
|                         |  Grayscale, adaptive threshold
+-----------+-------------+
            |
            v
+-------------------------+
|  Text Recognition       |  VNRecognizeTextRequest
|  (OCR)                  |  .accurate recognition level
+-----------+-------------+
            |
            v
+-------------------------+
|  AI Summarization       |  Apple Foundation Models (on-device)
|                         |  or OpenAI API (cloud)
+-----------+-------------+
            |
            v
     SummaryCard (saved to SwiftData)
```

---

## Data Models

### SummaryCard
```swift
@Model
final class SummaryCard {
    var id: UUID
    var title: String              // AI-generated or user title
    var summary: String            // 1-3 sentence summary
    var keyPoints: [String]        // 3-5 extracted key points
    var sourceText: String         // Original OCR text
    var pageNumber: Int?           // For multi-page documents
    var thumbnailData: Data?       // JPEG thumbnail (external storage)
    var createdAt: Date
    var deck: SummaryDeck?         // Optional deck relationship
}
```

### SummaryDeck
```swift
@Model
final class SummaryDeck {
    var id: UUID
    var title: String
    var deckDescription: String?
    var colorHex: String           // UI color theme (10 presets)
    var cards: [SummaryCard]       // @Relationship(deleteRule: .cascade)
    var createdAt: Date
    var lastAccessedAt: Date
    var isQuickCapture: Bool       // Special "Quick Capture" deck
    var deckSummary: String?       // Aggregated deck summary
    var deckKeyPoints: [String]?   // Key themes across all cards
    var summaryGeneratedAt: Date?  // Tracks summary freshness
}
```

### QuizQuestion
```swift
struct QuizQuestion: Identifiable {
    var id: UUID
    var question: String
    var options: [String]          // 4 multiple-choice options
    var correctAnswerIndex: Int
    var sourceCardTitle: String
}
```

---

## File Structure

```
Smart Glasses/
|-- Smart_GlassesApp.swift              # App entry point
|-- WearablesConfig.swift               # Meta SDK configuration
|-- WearablesManager.swift              # Glasses connection manager
|-- PhoneCameraManager.swift            # Phone camera fallback
|-- AppIntents.swift                    # Siri Shortcuts
|-- Smart-Glasses-Info.plist            # App configuration
|
|-- Models/
|   |-- SummaryCard.swift               # Card data model
|   |-- SummaryDeck.swift               # Deck data model
|   |-- QuizQuestion.swift              # Quiz data structures
|   +-- Flashcard.swift                 # Flashcard data structures
|
|-- Views/
|   |-- MainTabView.swift               # Tab navigation
|   |-- SettingsView.swift              # Settings screen
|   |-- DocumentBoundaryOverlay.swift   # Scanning overlay
|   |
|   |-- DeckLibrary/
|   |   |-- DeckLibraryView.swift       # Library grid
|   |   |-- DeckDetailView.swift        # Card carousel + deck summary
|   |   |-- LibraryScannerView.swift    # Scanner interface
|   |   |-- PDFImportView.swift         # PDF import progress sheet
|   |   +-- PhoneCameraPreviewLayer.swift # Phone camera preview
|   |
|   |-- DocumentScanner/
|   |   +-- CardPreviewSheet.swift      # Save card sheet
|   |
|   |-- QuizMode/
|   |   |-- QuizView.swift              # Quiz interface
|   |   +-- QuizResultsView.swift       # Quiz results
|   |
|   +-- FlashcardMode/
|       |-- FlashcardView.swift         # Flashcard study interface
|       |-- FlashcardCardView.swift     # 3D flip card component
|       +-- FlashcardStudyResultsView.swift # Study session results
|
|-- DocumentReader/
|   |-- DocumentReaderProcessor.swift   # OCR engine
|   +-- DocumentReadingResult.swift     # Result models
|
|-- Services/
|   |-- StreamingSummarizer.swift       # AI summarization (Apple + OpenAI)
|   |-- PDFGenerator.swift              # PDF export (cards + flashcards)
|   |-- PDFImporter.swift              # PDF text extraction + thumbnails
|   |-- OpenAIProvider.swift            # OpenAI API integration
|   |-- LLMProvider.swift               # AI provider protocol
|   |-- QuizGenerator.swift             # Quiz question generation
|   |-- FlashcardGenerator.swift        # Flashcard generation
|   +-- KeychainHelper.swift            # Secure key storage
|
|-- Audio/
|   +-- VoiceFeedbackManager.swift      # TTS, haptics, audio routing
|
+-- Assets.xcassets/                    # App resources
```

---

## Configuration

### Distance Mode Settings
| Parameter | Distance Mode | Close-up Mode |
|-----------|---------------|---------------|
| `targetProcessingDimension` | 3500px | 2000px |
| `convertToGrayscale` | Yes | No |
| `useAdaptiveThreshold` | Yes | No |
| `textConfidenceThreshold` | 0.2 | 0.4 |
| `documentConfidenceThreshold` | 0.35 | 0.5 |
| `minimumTextLines` | 1 | 3 |
| `minimumCharacters` | 15 | 50 |

### Auto-Capture Settings
| Parameter | Value | Description |
|-----------|-------|-------------|
| `stableFramesRequired` | 8 | Consecutive stable frames needed |
| `stabilityThreshold` | 0.03 | Max movement allowed (fraction) |
| `detectionFrameSkip` | 3 | Process every Nth frame |
| `documentConfidenceThreshold` | 0.5 | Minimum detection confidence |

---

## Permissions

The app requires the following permissions configured in `Info.plist`:

| Permission | Usage |
|------------|-------|
| Bluetooth | Connect to Meta smart glasses |
| Camera | Phone camera fallback and document scanning |
| Microphone | Voice commands (optional) |
| Photo Library | Save captured images |
| Siri | Voice shortcuts integration |

### Background Modes
- `audio` - Bluetooth A2DP audio playback
- `bluetooth-peripheral` - Wearable connection
- `external-accessory` - Meta glasses communication

---

## Troubleshooting

### Glasses Won't Connect
1. Ensure glasses are powered on and in range
2. Check Bluetooth is enabled on iPhone
3. Try "Disconnect Glasses" then "Connect Glasses"
4. Restart the Meta AI app if installed

### Poor OCR Results
1. Enable Distance Mode in Settings
2. Ensure adequate lighting
3. Hold document steady until green indicator appears
4. Try moving slightly closer to the document
5. Try using the phone camera if glasses produce low-quality frames

### AI Summarization Not Working
- **Apple Intelligence**: Requires iOS 26+ and Apple Intelligence enabled in Settings > Apple Intelligence & Siri
- **OpenAI**: Requires valid API key entered in Settings
- The app falls back to basic text extraction on unsupported configurations

### No Audio Through Glasses
1. Verify glasses are connected via Bluetooth A2DP
2. Check iPhone audio output is set to glasses
3. Ensure "Speak Summaries" is enabled in Settings
4. Audio automatically routes to phone speakers when glasses disconnect

---

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## Acknowledgments

- Meta Wearables SDK team for glasses integration
- Apple Vision framework for OCR capabilities
- Apple Foundation Models for on-device AI
- OpenAI for cloud AI and TTS APIs
- SwiftUI and SwiftData teams for modern iOS development tools

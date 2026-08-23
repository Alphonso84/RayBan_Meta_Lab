# Foundation Models Upgrade Plan (iOS 27 / WWDC26)

**Audience:** a future Claude Code session (Opus 4.8, Opus 5, or later) implementing these upgrades.
**Source:** `Smart Glasses/wwdc2026-241.txt` — "What's new in the Foundation Models framework" (WWDC26).
**Companion docs:** `AppleFoundationModels.md` (WWDC25 baseline API), `AGENTS.md` (Meta SDK), `CLAUDE.md` (architecture).

Every API signature in this document was **read directly out of the iOS 27.0 SDK's `.swiftinterface`**, not inferred
from the transcript. Signatures are quoted with their real availability annotations. Trust them, but re-verify if
the SDK has been updated since (see "Verifying the SDK" below).

---

## Status

| # | Upgrade | Status |
|---|---------|--------|
| 1 | Vision: attach page image to summarization | **Implemented, builds clean — needs a device test** |
| 2 | Private Cloud Compute as the big-context tier | **Implemented, builds clean — needs a device test + entitlement** |
| 3 | Dynamic profiles → study-session agent | Not started |
| 4 | Spotlight RAG (ask-my-library + auto-filing) | Not started |
| 5 | `LanguageModel` protocol → collapse provider fork | Not started |
| 6 | Real token counting (replace `maxCardsPerBatch`) | **Implemented, builds clean — needs a device test** |
| 7 | `OCRTool` / `BarcodeReaderTool` | **BarcodeReaderTool implemented; OCRTool deliberately deferred** |
| 10 | Whiteboard capture mode | **Implemented, builds clean — needs a device test** |
| 11 | Siri / App Intents entities + indexing | **Implemented, builds clean — needs a device test** |
| 8 | Evaluations framework | Not started |
| 9 | watchOS companion + `fm` CLI tooling | Not started |

---

## Environment (verified 2026-08-13)

| Fact | Value |
|------|-------|
| Xcode | **27.0 beta**, at `/Users/alphonsosensleyii/Downloads/Xcode-beta 3.app` (note: in `~/Downloads`, **not** `/Applications`) |
| iOS SDK | `iPhoneOS27.0.sdk` — present |
| `xcode-select -p` | `/Library/Developer/CommandLineTools` — **points at CLT, not Xcode** |
| Project deployment target | `IPHONEOS_DEPLOYMENT_TARGET = 26.0` |
| Swift version | `SWIFT_VERSION = 5.0` |

### This has one important consequence

Because the project builds against the **iOS 27 SDK** but deploys to **iOS 26**, all iOS 27 symbols
*compile* fine and only need **runtime** `if #available(iOS 27.0, *)` guards.

**Do not add `#if SG_FM_*` custom compilation flags.** An earlier draft of this plan proposed them under the
assumption that only the iOS 26 SDK was installed. That assumption was wrong and the flags are unnecessary
complexity. Use plain `@available` / `if #available` throughout.

Keep `#if canImport(FoundationModels)` where it already exists — that is a separate, pre-existing pattern in this
codebase guarding the framework import itself.

### Building

`xcode-select` points at Command Line Tools, so `xcodebuild` alone will fail. Override `DEVELOPER_DIR`:

```bash
DEVELOPER_DIR="/Users/alphonsosensleyii/Downloads/Xcode-beta 3.app/Contents/Developer" \
  xcodebuild -project "Smart Glasses.xcodeproj" -scheme "Smart Glasses" \
  -destination 'generic/platform=iOS' -configuration Debug build
```

**Always build before reporting an item complete.** If a build fails for reasons unrelated to your change (beta
toolchain churn, signing), say so explicitly rather than implying the change was verified.

### ⚠️ Beta seed skew — read this before debugging a launch crash

**The Xcode seed and the iOS seed on the test device must match.** Apple does not hold FoundationModels ABI stable
across betas, so a mismatch produces a `dyld: Symbol not found` crash *at launch*, not a compile error and not a
runtime failure on the affected code path.

Real example from this project: the `metadata:` parameter on the `contextOptions:` overloads changed type between
seeds — `[String : any Sendable & Codable & Equatable]` → `[String : any ConvertibleToGeneratedContent]`. Different
type, different mangled symbol, instant crash on an older device seed.

`if #available(iOS 27.0, *)` **cannot** help here: every iOS 27 beta reports 27.0. Availability checks distinguish
OS versions, not seeds.

Diagnosing it:

```bash
# 1. What seed is the device on? (compare the build, not the version)
xcrun devicectl list devices
xcrun devicectl device info details --device <UDID> | grep -A2 Software

# 2. Which symbols does the built binary need that an older SDK lacks?
xcrun nm -u "<DerivedData>/…/Smart Glasses.debug.dylib" | grep FoundationModels | sed 's/^ *//' | sort -u > undef.txt
while read -r s; do grep -qF "$s" "<older-SDK>/…/FoundationModels.tbd" || echo "$s"; done < undef.txt | xcrun swift-demangle
```

The fix is always to align the toolchain and the OS — never to delete the API call. When this happened here, the
mismatch set included `Attachment.init(_:orientation:)` and `BarcodeReaderTool`, so patching the one symbol named
in the crash would only have exposed the next.

Note the Xcode app's **filename means nothing** — `Xcode-beta 3.app` in this project is Xcode 27 *beta 5*. Check
Xcode → About, or `CFBundleShortVersionString` in its `Info.plist`.

### Verifying the SDK

To re-read any API surface:

```bash
SDK="/Users/alphonsosensleyii/Downloads/Xcode-beta 3.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS27.0.sdk"
IF="$SDK/System/Library/Frameworks/FoundationModels.framework/Modules/FoundationModels.swiftmodule/arm64e-apple-ios.swiftinterface"
grep -n "someSymbol" "$IF"
```

The interface is ~3,650 lines. Symbols appear as `FoundationModels::TypeName` — mentally strip the module prefix.
The Vision system tools live in a **cross-import overlay**, not the main framework:
`_Vision_FoundationModels.framework` (you get it by importing both `Vision` and `FoundationModels`).

**Never invent a symbol name.** The transcript is a spoken talk; it names capabilities, not signatures. If you
cannot find a symbol in the interface, say so rather than guessing.

---

## Architecture facts you will need

Pipeline (see `CLAUDE.md` for the full diagram):

```
glasses frame → DocumentReaderProcessor.processFrameForAutoCapture (every 3rd frame, stability tracking)
             → WearablesManager.captureDocumentPhoto() (high-res)
             → DocumentReaderProcessor.captureAndProcess(_:)
                  → VNDetectDocumentSegmentationRequest  (boundary)
                  → CIPerspectiveCorrection              (deskew)
                  → preprocessForOCR                     (grayscale + contrast)
                  → VNRecognizeTextRequest               (OCR)
                  → DocumentReadingResult { extractedText, correctedImage, textBlocks }
             → StreamingSummarizer.summarize(_:pageImage:)
             → SummaryCard → SwiftData
```

- **`DocumentReadingResult.correctedImage: UIImage?`** carries the deskewed page — but when `preprocessImage` is on
  it is **grayscale with 1.3× contrast**, tuned for OCR and actively harmful for a vision model looking at figures.
  Vision work needs a *separate*, un-preprocessed copy: item 1 added
  **`DocumentReadingResult.visionImage: UIImage?`**, rendered by the same
  `applyPerspectiveCorrection` with `preprocess: false`. Always pass `visionImage`, never `correctedImage`, to
  anything that looks at pictures.
- **Two OCR entry points**: `processLatestFrame()` (continuous timer scan) and `captureAndProcess(_:)` (high-res
  on-demand). They duplicate the detect → correct → OCR sequence. Only `captureAndProcess` matters for card creation.
- **Multi-page** accumulates into `processor.accumulatedText` and `processor.capturedPageThumbnails: [UIImage]`
  (full corrected images despite the name).
- **`summarize()` call sites (4)**: `LibraryScannerView.startSummarization(for:)`,
  `LibraryScannerView.finishAndSummarize()`, `AppIntents.swift` (~line 90), `PDFImportView.swift` (~line 332).
- **The provider fork**: `StreamingSummarizer` branches on `selectedProvider == "openai"` in every method, with a
  duplicate implementation in `OpenAIProvider` (673 lines). Same in `QuizGenerator` / `FlashcardGenerator`. Item 5
  fixes this.
- **The real-time loop is latency-critical.** `processFrameForAutoCapture` runs every 3rd frame and drives the
  stability ring. Never put an LLM call, system tool, or heavy async work in that path.

### SwiftData migration safety

`SummaryCard` / `SummaryDeck` are `@Model` types with existing user data. Adding a **new optional property** is a
safe lightweight migration. Renaming, removing, or retyping an existing property is **not** — it crashes on launch
against an existing store. If an item needs a non-additive change, write an explicit `VersionedSchema` +
`MigrationPlan` and call it out in your final message.

### Scope discipline

Each item is scoped to be reviewable alone. Do not opportunistically refactor adjacent code — in particular do
**not** start item 5's provider-fork cleanup while doing items 1–4, however tempting the duplication is. Item 5
exists to do it once, properly, after the call sites stop moving.

---

## Item 1 — Vision: attach the page image to summarization ✅ IMPLEMENTED

**Goal:** stop throwing away pixels. Send the page image alongside the OCR text so the model repairs OCR errors and
describes figures.

### Verified API

```swift
@available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
public struct Attachment<Content> { }

@available(iOS 27.0, ...)
extension Attachment where Content == ImageAttachmentContent {
    public init(_ cgImage: CGImage,          orientation: CGImagePropertyOrientation? = nil)
    public init(_ ciImage: CIImage,          orientation: CGImagePropertyOrientation? = nil)
    public init(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation? = nil)
    public init(imageURL: URL,               orientation: CGImagePropertyOrientation? = nil)
}

@available(iOS 27.0, ...)
extension Attachment: PromptRepresentable, InstructionsRepresentable { }

@available(iOS 27.0, ...)
extension Attachment { public func label(_ label: String) -> Attachment<Content> }
```

Because `Attachment` is `PromptRepresentable`, it composes directly inside a `@PromptBuilder` closure. The builder
overload used is **iOS 26**, so only the `Attachment` itself needs the 27 guard:

```swift
@available(iOS 26.0, ...)
final public func streamResponse<Content>(
    to prompt: Prompt,
    generating type: Content.Type = Content.self,
    includeSchemaInPrompt: Bool = true,
    options: GenerationOptions = GenerationOptions()
) -> sending ResponseStream<Content> where Content: Generable
```

**Note:** there is no `UIImage` initializer despite what the transcript says — use `.cgImage`.

**Related, currently unused:** `ImageReference` is a `Generable` struct with an `attachmentLabel` property, letting
the model name *which* attached image it is describing. Combined with `Attachment.label(_:)` this is the path to
true multi-page vision (one attachment per page, model cites the page). Item 1 attaches a single image; see
"Follow-on work" below.

### What shipped

- **`Services/PageVisionSupport.swift`** (new) — `PageVisionImage.prepare(_:maxDimension:)` downscales and
  orientation-normalizes for the model; `PageVisionPrompt` holds both prompt wordings and the
  `isVisionSupported` runtime check.
- **`DocumentSummaryOutput.visualDescription: String`** — new `@Generable` field; empty when the page is plain
  text. Mirrored in the non-FoundationModels fallback struct and in `OpenAIProvider`'s parser (always `""` there —
  page images are never sent to OpenAI).
- **`SummaryCard.visualDescription: String?`** + `hasVisualDescription` — additive optional property, folded into
  `textForSpeech` and rendered as an "On the Page" block in `DeckDetailView`.
- **`StreamingSummarizer.summarize(_:pageImage:)`** — new optional parameter defaulting to `nil`, so all existing
  call sites keep compiling. Publishes `streamingVisualDescription`. Picks the OCR-repair prompt when an image is
  present, the original prompt otherwise.
- **`applyPerspectiveCorrection(cgImage:boundary:targetDimension:preprocess:)`** — the two new parameters default to
  the existing OCR values, so the pre-existing call sites are unchanged in behavior.
- **`DocumentReadingResult.visionImage`** — added via an explicit `init` with a `nil` default so the other
  construction sites did not have to change.
- **`DocumentReaderProcessor.capturedPageVisionImages`** — parallel to `capturedPageThumbnails` for multi-page.
- All 4 call sites pass an image where one exists. PDF import renders the page at vision resolution rather than
  reusing the 300px thumbnail.
- Settings toggle `useVisionSummarization` (`@AppStorage`, default on), hidden below iOS 27.

### Verification state

**Builds clean** against the iOS 27 SDK targeting iOS 26 (`BUILD SUCCEEDED`, no new warnings — the
`ActorIsolatedCall` and `switch must be exhaustive` warnings in that file are pre-existing).

**Not yet run on a device.** Still to confirm:

1. Test against a page with a diagram, a table, and a deliberately blurry distance capture.
2. Confirm the on-device model honors attachments on the target hardware. If it does not, the graceful path is
   already in place — it falls back to the text-only prompt.
3. Compare summaries with the toggle on vs. off. This is exactly what item 8 should automate.

### Tuning

`maxDimension` defaults to **1024**. The transcript is explicit that larger images cost more tokens and latency,
and that the model accepts **any aspect ratio** — so never crop or pad to a square. If figure detail is being
missed, raise to 1536 before changing anything else.

### Follow-on work

Multi-page currently attaches only the first page. With `Attachment.label(_:)` + `ImageReference`, attach every
page and let the model cite which page a figure came from. Worth doing after item 6 lands, so the token cost of
N attachments can be measured rather than guessed.

---

## Item 2 — Private Cloud Compute as the big-context tier ✅ IMPLEMENTED

**Goal:** replace OpenAI as the "large context" escape hatch with PCC — bigger context, reasoning, no API keys, no
billing, no key storage.

**Why:** the app currently pushes users to OpenAI when context is large (Settings alert added in commit `9640bc1`),
which means keys in Keychain, per-token cost, and user data leaving the device. PCC removes all three. Free for
developers under 2M first-time downloads; iCloud+ subscribers get higher limits.

### Verified API

```swift
@available(iOS 27.0, ...)
final public class PrivateCloudComputeLanguageModel: Sendable {
    final public var availability: Availability { get }          // same shape as SystemLanguageModel.availability
    final public var contextSize: Int { get }                    // nonisolated(nonsending)
    final public func supportsLocale(_ locale: Locale = .current) async throws -> Bool
}

@available(iOS 27.0, ...)
public struct ContextOptions: Sendable, Equatable {
    public var reasoningLevel: ReasoningLevel?
    public init(includeSchemaInPrompt: Bool? = nil, reasoningLevel: ReasoningLevel? = nil)

    public enum ReasoningLevel: Sendable, Equatable {
        case light, moderate, deep
        case custom(String)
    }
}
```

`contextOptions:` is accepted by the **iOS 27** `respond` / `streamResponse` overloads (the iOS 26 overloads take
`includeSchemaInPrompt:` instead — note they are *different overloads*, so passing `contextOptions` implicitly
requires iOS 27 at runtime).

**Files:** `Services/StreamingSummarizer.swift`, `Services/QuizGenerator.swift`, `Views/SettingsView.swift`,
entitlements.

**The big win:** `summarizeDeckChunked()` exists *only* because on-device context cannot hold a deck. It is
map-reduce over `maxCardsPerBatch = 4`, and summarizing summaries is lossy — themes spanning batches are
structurally unfindable. PCC's larger context lets most decks go in one pass. Keep the chunked path as a fallback
for genuinely huge decks, driven by item 6's real token count rather than the magic number.

Also apply `.deep` reasoning to `QuizGenerator` — question quality is where reasoning models pull furthest ahead.

**Gotchas:**
- PCC requires the **`com.apple.developer.private-cloud-compute`** entitlement (Boolean). It is a *managed*
  entitlement — it cannot simply be toggled on in Signing & Capabilities; Apple must assign it to the account
  first, after which it flows into the provisioning profile. Missing it is a runtime failure, not a compile error.
  Eligibility is stricter than the WWDC transcript implies: enrolled in the **App Store Small Business Program**,
  **fewer than 2M first-time downloads**, and the entitlement assigned. Request it at
  <https://developer.apple.com/contact/request/private-cloud-compute/>. Exceeding either limit later gives 6
  months to migrate off.
- **Do not add the key to an entitlements file before Apple assigns it** — code signing then fails with
  "provisioning profile doesn't include the com.apple.developer.private-cloud-compute entitlement", which breaks
  device builds for a feature that would not have worked anyway.
- PCC is a network call. Handle offline by falling back on-device — the glasses use case is frequently mobile.
- Set the privacy boundary explicitly: **page images stay on-device** (item 1's on-device vision); only derived text
  goes to PCC. Do not silently send raw scans off-device.
- Provider picker becomes three-way: Apple on-device / Apple PCC / OpenAI.

**Done when:** a 20-card deck summarizes in one pass under PCC, offline falls back cleanly, and the Settings alert
recommends PCC rather than OpenAI.

### What shipped

- **`Services/AppleModelProvider.swift`** (new) — the single place that knows about PCC, mirroring what
  `PageVisionSupport.swift` does for item 1. Contains `AppleModelTier`, `SummarizationProvider` (raw values match
  the persisted `@AppStorage` strings — `"apple"` must never be renamed), availability and quota messages, the
  session factory, `respond`/`streamResponse` wrappers that apply reasoning only where supported, and
  `isRecoverablePCCError(_:)`.
- The shared PCC instance lives in `enum PrivateCloudCompute` marked `@available(iOS 27.0, *)`. That nesting is the
  trick worth remembering: a `static let` of an iOS 27 type cannot exist in a type that also compiles for iOS 26,
  but it can inside an availability-gated type.
- **`StreamingSummarizer`** — tier-aware. `runDocumentSummarization(text:visionCGImage:tier:)` was extracted so a
  failed PCC attempt can be retried on-device with clean state (`clearStreamedFields()`). Instructions moved to
  `documentInstructions` / `deckInstructions` statics so a summary reads the same on either tier.
- **Deck summaries go one-pass on PCC** with `.deep` reasoning, falling back to the chunked map-reduce path on
  failure. `summarizeDeckDirect` gained a `tier:` parameter and returns `nil` on recoverable PCC errors instead of
  swallowing them, which is what lets the caller retry locally.
- **`QuizGenerator` / `FlashcardGenerator`** — same tier + reasoning + on-device-retry shape. Both now recurse into
  a `tier:`-parameterized overload rather than duplicating the body.
- **`SettingsView`** — three-way picker (On-Device / Apple Cloud / OpenAI), a live PCC readiness row, a quota row
  wired to `limitIncreaseSuggestion.show()`, and per-provider footers.
- **`DeckDetailView` / `PDFImportView`** — the "OpenAI Recommended" alerts now recommend Apple Cloud on iOS 27 and
  fall back to the OpenAI wording on iOS 26.

### Design decision: images never go to PCC

`summarize(_:pageImage:)` picks `.onDevice` whenever a page image is attached, regardless of provider. PCC is the
big-context tier **for text**, not a general replacement for the local model. Consequence to keep in mind: choosing
"Apple Cloud" does **not** change single-page scan behavior — it affects deck summaries, quizzes, flashcards, and
PDF import. The Settings footer says so explicitly. If you ever want cloud vision, that is a deliberate policy
change and needs its own user-facing consent, not a silent flip.

### Verification state

**Builds clean** (`BUILD SUCCEEDED`, no new warnings). **Not run on a device**, and specifically unverified:

1. **The entitlement is not wired up**, deliberately. It is `com.apple.developer.private-cloud-compute` (see
   Gotchas above for the eligibility bar and request link). It is a managed entitlement, so adding the key to the
   project *before* Apple assigns it breaks code signing — request it first, then add it. Until then
   `availability` reports `.unavailable(.deviceNotEligible)` and the Settings row says so, which is the intended
   graceful degradation rather than a crash. Note the string is **not** present anywhere in the SDK; it is only in
   Apple's online documentation, so do not go looking for it in the `.swiftinterface`.
2. Whether `.deep` reasoning measurably improves quiz questions — item 8's job.
3. The offline fallback path (turn on Airplane Mode mid-deck-summary and confirm it completes on-device).

---

## Item 3 — Dynamic profiles → study-session agent

**Goal:** one `LanguageModelSession` that switches instructions, tools, model, and reasoning level by mode, instead
of three disconnected one-shot generators.

**Why:** `StreamingSummarizer`, `FlashcardGenerator`, and `QuizGenerator` each rebuild context from scratch and
discard it. The unlock is **continuity**: because history survives a mode switch, "why was that answer wrong?" and
adaptive re-quizzing on missed topics become nearly free. Today they are impossible — the quiz generator has no
memory of the answering session.

### Verified API

```swift
extension LanguageModelSession {
    @_typeEraser(AnyDynamicProfile)
    public protocol DynamicProfile { ... }

    public struct Profile: DynamicProfile { ... }

    public protocol DynamicProfileModifier { ... }
}

// modifier, on DynamicProfile:
public func reasoningLevel(_ reasoningLevel: ContextOptions.ReasoningLevel?) -> some DynamicProfile
```

Read the full `Profile` initializer and the remaining modifiers (including the model modifier) out of the interface
before writing — grep `DynamicProfile` and `DynamicProfileModifier` and read the surrounding ~100 lines.

**Sketch:**
```swift
struct StudyProfile: LanguageModelSession.DynamicProfile {
    let mode: StudyMode
    var body: some LanguageModelSession.DynamicProfile {
        switch mode {
        case .analyze:                     // on-device + vision; images never leave device
            LanguageModelSession.Profile(instructions: ..., tools: [])
        case .quiz:                        // PCC + deep reasoning
            LanguageModelSession.Profile(instructions: ..., tools: [SwitchModeTool()])
                .reasoningLevel(.deep)
        }
    }
}
```

**Gotchas:**
- A `DynamicProfile` resolves to **exactly one** active `Profile` at a time. Drive it from an existing `@Published`
  mode variable; never try to hold two active.
- A mode-switch *tool* lets the model move itself to PCC — i.e. move data off-device. Gate that on the user's
  provider setting.
- The mode table maps onto item 2's privacy boundary. Keep them consistent.

**Done when:** a user can scan → summarize → quiz → ask "why was I wrong?" in one session, and the answer
references the actual scanned material.

---

## Item 4 — Spotlight RAG: ask-my-library + auto-filing

**Goal:** index every `SummaryCard` into CoreSpotlight and attach the Spotlight-backed search tool for fully local
RAG across the user's scan history.

**Files:** new `Services/CardSpotlightIndexer.swift`; `Models/SummaryCard.swift`; `Smart_GlassesApp.swift` (launch
indexing / backfill); `Views/DeckLibrary/DeckLibraryView.swift` (search UI).

**Two features — the second is the more valuable one day-to-day:**

1. **Ask my library** — "what have I read about mitochondrial respiration?" answered across all decks, locally.
2. **Auto-filing** — at save time, retrieve similar existing cards and suggest a deck. The Quick Capture / Unsorted
   pile is where scans currently go to die; `DeckLibraryView` counts unsorted cards but does nothing about them.
   This fixes the problem instead of reporting it.

**Gotchas:**
- Index `title`, `summary`, `keyPoints`, and `visualDescription`. Do **not** index raw `sourceText` — noisy OCR will
  pollute retrieval.
- Backfill existing cards once on first launch after update; guard with a `UserDefaults` flag.
- Delete from the index on card **and** deck deletion — `SummaryDeck` cascade-deletes its cards, so hook the deck
  path too, not just the single-card path.
- The transcript mentions "specially processed queries" — check the "LLM search using Core Spotlight" session before
  hand-rolling query construction. Find the tool's real name in the SDK first; it was not located during this
  plan's verification pass.

**Done when:** a natural-language question returns an answer citing cards from more than one deck, and saving a new
card suggests a plausible existing deck.

---

## Item 5 — `LanguageModel` protocol: collapse the provider fork

**Goal:** one code path per operation instead of a per-provider fork in every method.

**Why:** every method in `StreamingSummarizer` does `if selectedProvider == "openai" { return await
summarizeWithOpenAI(...) }`, with a parallel implementation in `OpenAIProvider`. Same in `QuizGenerator` and
`FlashcardGenerator`. The paths have **already drifted**: the OpenAI path hand-parses markdown
(`parseDocumentResponse`) while the Apple path uses guided generation and cannot fail the same way. iOS 27 opens
the abstraction layer so any model can back a `LanguageModelSession`.

**Sketch:**
```swift
private func makeModel() -> any LanguageModel {
    switch selectedProvider {
    case "openai": return /* Chat Completions model from FM utilities package */
    case "pcc":    return PrivateCloudComputeLanguageModel()
    default:       return SystemLanguageModel.default
    }
}
let session = LanguageModelSession(model: makeModel(), instructions: ...)
// everything downstream identical, including guided generation
```

The **Foundation Models utilities** package (open source, per the transcript) ships a Chat Completions–standard
`LanguageModel` that likely covers OpenAI directly. Check that before writing a custom conformance.

**Token accounting** — verified, use this instead of hand-rolled counters:
```swift
@available(iOS 27.0, ...) extension LanguageModelSession {
    final public var usage: Usage { get }
}
public struct Usage: Sendable {
    public var input: Input      // .totalTokenCount, .cachedTokenCount
    public var output: Output
    public var metadata: [String: GeneratedContent]
}
```

**Payoff:** deletes most of `OpenAIProvider`'s 673 lines, kills hand-rolled markdown parsing (OpenAI gets real
guided generation), and removes `Services/LLMProvider.swift` entirely.

**Gotchas:**
- Keep `KeychainHelper` — third-party models still need keys. The transcript is emphatic: never ship keys in the
  binary; fetch via OAuth where possible; store in Keychain.
- Do this **after** items 1–3, or you will rebase their call-site changes onto a moving refactor.

**Done when:** `StreamingSummarizer` has zero `if selectedProvider` branches and all providers produce identical
`DocumentSummaryOutput` shapes through guided generation.

---

## Item 6 — Real token counting ✅ IMPLEMENTED

**Goal:** replace `StreamingSummarizer.maxCardsPerBatch = 4` with measured token budgeting.

**Why:** 4 is a guess, wrong in both directions — it wastes context on short cards and overflows on long ones.

### Verified API

Two corrections to what an earlier draft of this plan claimed — both were wrong and both matter:

1. `tokenCount(for:)` is on **`SystemLanguageModel`**, *not* on `LanguageModelSession`.
2. It requires **iOS 26.4**, not 26.0, and is **unavailable on watchOS** (relevant to item 9).

```swift
// All on SystemLanguageModel, all nonisolated(nonsending) async throws:
@available(iOS 26.4, *) @available(watchOS, unavailable)
final public func tokenCount(for prompt: some PromptRepresentable) async throws -> Int
final public func tokenCount(for instructions: Instructions) async throws -> Int
final public func tokenCount(for tools: [any Tool]) async throws -> Int
final public func tokenCount(for schema: GenerationSchema) async throws -> Int
final public func tokenCount(for transcriptEntries: some Collection<Transcript.Entry>) async throws -> Int

@available(iOS 26.0, *) @backDeployed(before: iOS 26.4)
final public var contextSize: Int { get }   // ⚠️ returns a hardcoded 4096 below iOS 27

// Generable exposes its schema for the schema overload:
static var generationSchema: GenerationSchema { get }
```

**The `contextSize` back-deployment is the subtle one.** Below iOS 27 the property returns a literal `4096`
regardless of hardware — it only reports the real per-device window on iOS 27+. That is conservative rather than
wrong (you under-fill rather than overflow), so it needs no special handling, but do not mistake 4096 for a
measurement.

Overflow errors have two spellings and both must be matched:
```swift
@available(iOS 27.0, *) LanguageModelError.contextSizeExceeded(ContextSizeExceeded)  // .contextSize, .tokenCount
LanguageModelSession.GenerationError.exceededContextWindowSize(Context)              // deprecated in 27
```

**Done when:** batch sizes vary with actual card length, and the chunked path only triggers when content genuinely
exceeds context.

### What shipped

- **`Services/TokenBudget.swift`** (new) — `Budget { contextSize, overhead, outputReserve }` with
  `availableForContent`, plus `makeBudget(instructions:schemaFor:outputReserve:)`, `measure(_:)`,
  `pack(_:into:)`, and `fits(_:in:)`. `measure` uses the real tokenizer on iOS 26.4+ and falls back to a
  4-characters-per-token estimate below that, so callers get one code path.
- **`AppleModelProvider.isContextSizeExceeded(_:)`** — matches both error spellings.
- **`StreamingSummarizer`** — `maxCardsPerBatch` is gone. `summarizeDeck` now measures the deck against the
  budget: fits → one pass; doesn't → `TokenBudget.pack` groups cards into batches that each fit.
  `summarizeDeckChunked` takes pre-packed `batches:` rather than re-deriving them, so a single measurement decides
  both *whether* to chunk and *how big* each batch is.
- **`summarizeDeckDirect` returns `nil` on overflow** so the caller can chunk — the measurement is the fast path,
  the typed error is the safety net behind it.
- **The provider-recommendation alerts are now measurements.** They previously fired for *every* deck whenever the
  provider was on-device, which trains people to dismiss them. `DeckDetailView.begin(_:)` consolidates the three
  trigger sites and only warns when the deck actually exceeds the window; the messages state the real consequence
  instead of hedging about what the model "may struggle with".
- **`PDFImportView` measures the largest single page, not the document.** Pages are summarized in separate
  sessions, so nothing accumulates across them — the old alert copy blamed "processing pages sequentially", which
  was simply the wrong premise. Both the trigger and the wording are corrected.

### Verification state

**Builds clean** (`BUILD SUCCEEDED`, no warnings). **Not run on a device.** Worth checking:

1. That `pack` produces sensible batch counts on a real deck — log line is
   `[StreamingSummarizer] Chunking N cards into M batches`.
2. That the recommendation alert now stays *quiet* for ordinary decks. If it still fires constantly on iOS 26.x,
   that is the hardcoded 4096 `contextSize` talking, not a bug in the packing.
3. `defaultOutputReserve = 1024` is a considered guess, not a measurement. If summaries come back truncated, raise
   it; if the alert is over-eager on iOS 27 hardware with a large window, lower it.

---

## Item 7 — `OCRTool` and `BarcodeReaderTool`

### Verified API — note the module

These live in the **cross-import overlay** `_Vision_FoundationModels`, which activates when you
`import Vision` *and* `import FoundationModels`. There is no `import _Vision_FoundationModels`.

```swift
public struct OCRTool: FoundationModels.Tool, @unchecked Sendable {
    public init(name: String? = nil, description: String? = nil)
}
public struct BarcodeReaderTool: FoundationModels.Tool, @unchecked Sendable {
    public init(name: String? = nil, description: String? = nil)
}
```

Both are ordinary `Tool`s — pass them in `LanguageModelSession(tools:)`.

- **`OCRTool`** — structured extraction preserving reading order and layout, versus the current flat
  `VNRecognizeTextRequest` + manual bounding-box sort in `performOCR`. Multi-column and tabular layouts are where
  the current sort fails worst.
- **`BarcodeReaderTool`** — scan a textbook ISBN through the glasses to auto-create and title a deck; QR codes on
  lecture slides, posters, museum placards.

**Critical gotcha:** post-capture **only**. Keep `VNDetectDocumentSegmentationRequest` in
`processFrameForAutoCapture` for real-time stability tracking — routing that every-3rd-frame path through an LLM
tool call would destroy the interaction.

**Overlap with item 1:** if image attachments already repair OCR well, `OCRTool` may be redundant on the main path.
Measure with item 8 before adopting it wholesale. `BarcodeReaderTool` is a genuinely new capability regardless.

**Done when:** ISBN scanning creates a titled deck, and (if adopted) multi-column pages extract in reading order.

### What shipped (BarcodeReaderTool only)

- **`Services/BookBarcodeScanner.swift`** (new) — session with `BarcodeReaderTool()`, a **labeled** image
  attachment (`Attachment(cgImage).label("barcode-photo")`), and a `@Generable ScannedBookCode`. The label matters:
  the tool resolves an `ImageReference` back to the attachment by name, so an unlabeled attachment gives the model
  nothing to point at.
- Runs at **1536px**, above `PageVisionImage.defaultMaxDimension` — a barcode is small in a head-worn frame and
  needs finer detail than page text.
- **`Views/DeckLibrary/BookDeckSheet.swift`** (new) — always-editable confirmation sheet.

**The honest-titles decision.** A barcode gives the digits reliably; turning an ISBN into a *title* depends on the
model recognizing that specific number, which a small on-device model often will not. So the prompt explicitly
instructs it never to guess, `ScannedBookCode.recognizedTitle` is empty when unsure, and the sheet falls back to
`ISBN <code>` and tells the user where the title came from. A silently mislabelled deck is worse than an unnamed
one. If you want reliable titles, that needs an ISBN lookup API, which is a network call and a separate decision.

**`OCRTool` deferred deliberately.** Item 1's image attachments already repair OCR on the main path, so adopting
`OCRTool` on top is unmeasured churn until item 8 exists to say whether it adds anything. `BarcodeReaderTool` was
worth taking now because it is a genuinely new capability rather than an alternative to something that works.

---

## Item 8 — Evaluations framework

**Goal:** measure whether prompt changes help, instead of guessing.

**Why:** prompts live in four services with no regression signal. This item is what makes items 1, 2, and 7
*decidable* rather than matters of taste.

**Build the corpus first.** The repo already has sample scans (`Smart Glasses/IMG_*.PNG`). Expand to ~20 pages
covering the real hard cases: plain text, dense text, diagram-heavy, a table, multi-column, handwriting, and a
deliberately blurry distance capture.

**Highest-value first experiment:** OCR-text-only vs. text+image (item 1), scored on summary accuracy against
degraded OCR. That one number decides whether the vision path stays always-on and whether `OCRTool` adds anything
on top.

Pairs with item 9's `fm` CLI for batching variants outside the app.

**Done when:** an eval target reports a score per prompt variant and a change can be defended with a number.

---

## Item 9 — watchOS companion and `fm` CLI tooling

**watchOS 27** gets Foundation Models via PCC — note that much of the framework is annotated `watchOS 27.0` even
where iOS is 26.0, so the watch starts at parity with iOS 27. A wrist companion for flashcard review and deck
playback pairs naturally with hands-free glasses capture: capture with the glasses, review on the watch. Requires a
new watchOS target and SwiftData sharing via App Group. Largest item here, least certain value — do it last, and
only once the core loop is solid.

**`fm` CLI (macOS 27)** and the **Python SDK** are dev-side tooling, not shipped code. Use `fm` to batch sample
images through prompt variants when building item 8's corpus. Cheap — worth doing early if item 8 is on the table.

---

## Item 10 — Whiteboard capture mode ✅ IMPLEMENTED

**Goal:** capture a whiteboard, not just a page. Arguably the *native* use case for camera glasses — your hands are
busy and you are already looking at the board, whereas document scanning competes with just using your phone.

### Why it needed more than a config tweak

Three things in the document pipeline are actively wrong for a board:

1. **The boundary gate.** `captureAndProcess` refused to proceed without a `VNDetectDocumentSegmentationRequest`
   hit. A frameless board on a light wall gives that request no edge to lock onto, so document mode simply cannot
   capture one.
2. **`preprocessForOCR` destroys the content.** Grayscale throws away marker colour, which on a board carries
   meaning ("the red boxes are the constraints"), and boosting contrast on a glossy surface amplifies
   overhead-light glare rather than sharpening handwriting.
3. **The acceptance thresholds reject valid captures.** A board holding a diagram and four words fails
   `minimumTextLines`/`minimumCharacters`, even though it is exactly what the user meant to capture.

### What shipped

- **`CaptureMode`** enum in `DocumentReadingResult.swift` — `.document` / `.whiteboard` / `.barcode`, with
  `requiresDocumentBoundary` and `usesTextPipeline`. Unifying the three as *modes* was cleaner than bolting two
  independent toggles onto an already-crowded top bar.
- **Boundary is now optional.** When none is found and the mode allows it, `captureAndProcess` falls back to the
  uncropped frame via a new `scaledImage(_:targetDimension:preprocess:)`, skipping perspective correction. The
  model reads an un-deskewed board far better than it reads nothing.
- **Whiteboard preprocessing profile** in `configureProcessorForDistanceMode()` — no grayscale, no contrast, no
  threshold, `textConfidenceThreshold` 0.15, and looser stability (`0.05` / 10 frames) because standing back from a
  board means the same head movement sweeps far more of the scene than it does over a page at arm's length.
- **Image-only captures succeed.** `imageCanStandAlone` lets a whiteboard capture through with little or no OCR
  text, provided vision is available to carry it.
- **`PageVisionPrompt.whiteboardHeader` / `whiteboardBody`** — deliberately never mention "page" or reading order.
  A board is spatial, so the prompt asks what is boxed, what arrows connect to what, what is grouped or starred,
  and what the marker colours distinguish. OCR is demoted to "likely unreliable — prefer the image".
- **`StreamingSummarizer.summarize(_:pageImage:mode:)`** selects the prompt pair by mode.
- Mode picker in the scanner top bar, mode-aware idle prompts, and state reset on mode switch.

### Deliberately not built

**Panorama stitching across a wide board.** Genuinely hard, and the existing multi-page session already gives
multi-region capture — tell the model the regions belong to one board and you get most of the value for none of
the work.

### Verification state

**Builds clean.** **Not run on a device**, and this feature rests on an assumption I could not test:

> **The whole feature depends on the on-device model reading marker handwriting acceptably.** If it does not, no
> amount of capture plumbing saves it. Before investing further, photograph one real whiteboard, run it through
> this path, and read the `visualDescription` that comes back. That check is ~20 minutes and de-risks everything
> above it.

Also worth checking on device: whether auto-capture ever triggers in whiteboard mode (it is best-effort — a
frameless board may never produce a boundary, in which case capture is always manual, which is the intended
fallback rather than a bug).

---

## Item 11 — Siri: App Entities, semantic indexing, hands-free intents ✅ IMPLEMENTED

**Source:** `~/Downloads/wwdc2026-240.txt` — "Bring your app to Siri" (WWDC26).

**This subsumes most of item 4.** `IndexedEntity` puts entities into the system semantic index, which is the same
mechanism item 4 was going to reach through raw CoreSpotlight — but it also gets Siri question-answering and entity
resolution for free. Do not build item 4's `CardSpotlightIndexer` separately; extend this instead.

### What shipped

- **`SharedModelContainer.swift`** — one SwiftData container for the app *and* intents. Intents can run outside the
  app process, so they could not reach the container the `App` struct used to build privately.
- **`Intents/StudyEntities.swift`** — `SummaryCardEntity` and `SummaryDeckEntity` as `AppEntity` + `IndexedEntity`,
  with `EntityQuery` + `EntityStringQuery` for resolution, and a `StudyEntityStore` for the SwiftData reads.
- **`Services/StudyEntityIndexer.swift`** — full reindex on launch. Full rather than incremental deliberately: a
  heavy user has hundreds of cards, not millions, and several views can mutate the model, so cheap-and-correct
  beats incremental-and-occasionally-stale.
- **`Intents/StudyIntents.swift`** — `ReadCardIntent` and `SummarizeDeckIntent`. Both set
  `openAppWhenRun = false`: the point of asking while wearing glasses is to keep your hands and eyes where they
  are, so they answer aloud and return. `ReadCardIntent` with no card falls back to the most recent.
  `SummarizeDeckIntent` reuses a stored summary when present and persists any it generates.
- Shortcut phrases for both.

**Indexing excludes `sourceText`** for the same reason item 4 called out: raw OCR is noisy and pollutes retrieval
with words the user never actually read. Title, summary, key points and `visualDescription` are indexed.

### Deliberately not built

- **AppSchema domain adoption** (`.reader`, `.whiteboard`, `.books` all exist in the SDK). Adopting a domain is
  closer to all-or-nothing than it looks: the session shows Xcode **hard-erroring** when you adopt `sendMessage`
  without its companion `draftMessage`. The `reader` domain includes `ReaderRotatePagesIntent`,
  `ReaderResizeDocumentsIntent`, `ReaderInsertPagesIntent`, `ReaderDeletePagesIntent` and more — operations
  NoteBuddy has no concept of. Adopting it means stubbing actions that do not exist. Worth doing deliberately as
  its own item, not as a side effect.
- **On-screen awareness** ("explain this card" while viewing it) and **Transferable / `IntentValueRepresentation`**
  ("text this summary to my study group"). Both genuinely fit — the card carousel is exactly the annotate-the-view
  case — but each needs API surface I had not verified, and this item was already large.
- **A deck-opening intent.** `NavigationState` only carries `selectedTab`; pushing to a specific deck needs real
  navigation plumbing in `DeckLibraryView`. Skipped rather than half-built.

### Verification state

**Builds clean, no warnings. Not run on a device.** Worth checking:

1. Does Siri answer a content question — "what did I read about X" — rather than just opening the app? That is the
   whole point of `IndexedEntity` and the one thing that cannot be verified by compiling.
2. Does the launch reindex actually populate Spotlight? Search a card title in Spotlight before trying Siri; the
   session's advice is to validate Spotlight *before* Siri, because Siri failing to find content and Siri failing
   to act on it look identical from the outside.
3. `AppIntentsTesting` (new framework) can exercise the intents in isolation with no Siri involved — the fastest
   way to validate the logic. Not adopted here; it is the natural next step if these intents grow.

---

## Suggested order

```
1 (vision) ──┬──> 8 (evals)  ──> validates 1, decides 7
             │
2 (PCC) ─────┼──> 6 (tokens) ──> makes 2's chunking decision correct
             │
             └──> 3 (profiles) ──> 4 (Spotlight RAG)
                       │
                       └──> 5 (abstraction cleanup, after call sites settle)
```

**1** is the biggest quality jump for the smallest diff (done). **2** removes a dependency rather than adding one.
**6** is small and makes **2** correct. **3** and **4** are the real new-feature work and want a settled
foundation. **5** is a refactor — after the call sites stop moving, never during. **8** ideally comes earlier than
its dependencies suggest, because without it every other decision is unmeasured. **7** and **9** are opportunistic.

---

## Conventions for whoever implements the rest

- Match the existing file style: header comment block with filename and purpose, `// MARK: -` sections, `@MainActor`
  on UI-facing managers, `@Published` + Combine for state, `print("[ClassName] ...")` for logging.
- Guard iOS 27 APIs with runtime `if #available(iOS 27.0, *)` and always provide a working iOS 26 fallback. The app
  must keep building **and running on iOS 26** after every item.
- Isolate new-API usage in one file per feature where practical (item 1 put it all in `PageVisionSupport.swift`);
  it keeps the availability guards in one reviewable place.
- Read the real `.swiftinterface` before writing against any symbol. Do not guess.
- Update the Status table at the top of this file when an item lands.
- Update `CLAUDE.md` when an item changes the architecture diagram or adds a manager.

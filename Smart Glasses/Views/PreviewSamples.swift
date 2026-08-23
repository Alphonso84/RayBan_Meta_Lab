//
//  PreviewSamples.swift
//  Smart Glasses
//
//  Shared sample content for SwiftUI previews.
//
//  Previews of this app are awkward without help: most screens read from
//  SwiftData, and the two study modes need generated content that normally
//  comes from the language model — which does not run in a preview. Seeding a
//  container once here means a preview shows a populated library rather than an
//  empty one, and the flashcard screen shows cards rather than a spinner.
//
//  DEBUG only, so none of this reaches a shipping build.
//

#if DEBUG

import Foundation
import PDFKit
import SwiftData
import SwiftUI
import UIKit

@MainActor
enum PreviewSamples {

    // MARK: - Store

    /// An in-memory store seeded with decks and cards.
    ///
    /// Attach with `.modelContainer(PreviewSamples.container)`. It never touches
    /// the real library, so a preview cannot corrupt the user's decks.
    static let container: ModelContainer = {
        let schema = Schema([SummaryCard.self, SummaryDeck.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        // Force-try is deliberate: a preview that cannot build its own store has
        // nothing useful to show, and the crash names the problem immediately.
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        seed(container.mainContext)
        return container
    }()

    /// A populated deck — the one most previews want.
    static var deck: SummaryDeck {
        // Sorted so this always resolves to the same deck; an unsorted fetch
        // would let previews drift between runs.
        let descriptor = FetchDescriptor<SummaryDeck>(
            predicate: #Predicate { $0.isQuickCapture == false },
            sortBy: [SortDescriptor(\.lastAccessedAt, order: .reverse)]
        )
        return (try? container.mainContext.fetch(descriptor))?.first ?? fallbackDeck
    }

    /// A single card, for previews that show one in isolation.
    static var card: SummaryCard {
        deck.sortedCards.first ?? SummaryCard(
            title: "Untitled",
            summary: "No sample card available.",
            sourceText: ""
        )
    }

    /// Used only if the seeded fetch somehow comes back empty, so a preview
    /// degrades to something visible instead of crashing.
    private static let fallbackDeck = SummaryDeck(title: "Sample Deck")

    // MARK: - Seeding

    private static func seed(_ context: ModelContext) {
        // Dated in the past so the generated flashcards below do not read as
        // outdated, which would fire the "regenerate?" alert on every preview.
        let start = Date().addingTimeInterval(-86_400)

        let biology = SummaryDeck(
            title: "Cell Biology",
            deckDescription: "Lecture notes from BIO 210",
            colorHex: "34C759",
            createdAt: start,
            lastAccessedAt: Date().addingTimeInterval(-3_600)
        )
        biology.deckSummary = """
        The course works outward from the cell membrane to the organelles that \
        power it, ending on how energy is captured and spent.
        """
        biology.deckKeyPoints = [
            "Membranes are selectively permeable",
            "Mitochondria produce most cellular ATP",
            "Photosynthesis and respiration are near mirror images"
        ]
        biology.summaryGeneratedAt = start.addingTimeInterval(600)
        context.insert(biology)

        let cards: [(String, String, [String], String?)] = [
            (
                "Photosynthesis",
                "Plants convert light energy into chemical energy stored as sugar, using carbon dioxide and water and releasing oxygen.",
                ["Occurs in chloroplasts", "Light and dark reactions", "Produces glucose and oxygen"],
                "A cross-section of a leaf with arrows tracing carbon dioxide in and oxygen out."
            ),
            (
                "Cellular Respiration",
                "Cells break glucose down to release energy as ATP, in glycolysis, the Krebs cycle and the electron transport chain.",
                ["Glycolysis happens in the cytoplasm", "The Krebs cycle runs in the mitochondrial matrix", "Yields roughly 36 ATP"],
                nil
            ),
            (
                "The Cell Membrane",
                "A phospholipid bilayer studded with proteins controls what enters and leaves the cell.",
                ["Selectively permeable", "Embedded transport proteins", "Fluid mosaic model"],
                "A bilayer diagram with embedded channel proteins spanning both leaflets."
            )
        ]

        for (offset, entry) in cards.enumerated() {
            let (title, summary, keyPoints, visual) = entry
            let card = SummaryCard(
                title: title,
                summary: summary,
                keyPoints: keyPoints,
                sourceText: "Raw OCR text for \(title).",
                visualDescription: visual,
                pageNumber: offset + 1,
                createdAt: start.addingTimeInterval(Double(offset) * 60),
                deck: biology
            )
            context.insert(card)
        }

        // Seeded so `FlashcardView` loads from cache and renders real cards
        // instead of trying to reach a language model that previews cannot run.
        biology.saveFlashcards(flashcards)

        let history = SummaryDeck(
            title: "Modern History",
            deckDescription: "Reading notes",
            colorHex: "AF52DE",
            createdAt: start,
            lastAccessedAt: start
        )
        context.insert(history)
        context.insert(
            SummaryCard(
                title: "The Marshall Plan",
                summary: "American economic aid rebuilt Western Europe after 1948 and bound its recovery to United States trade.",
                keyPoints: ["Roughly $13 billion committed", "Ran from 1948 to 1952"],
                sourceText: "Raw OCR text for the Marshall Plan.",
                createdAt: start,
                deck: history
            )
        )

        // Quick Capture holds the loose cards the library shows separately.
        let quickCapture = SummaryDeck(
            title: "Quick Capture",
            colorHex: "FF9500",
            createdAt: start,
            isQuickCapture: true
        )
        context.insert(quickCapture)

        context.insert(
            SummaryCard(
                title: "Whiteboard: Sprint Plan",
                summary: "Three swimlanes with arrows from discovery through build to release, and a starred blocker on auth.",
                keyPoints: ["Auth is the critical path", "Release gated on review"],
                sourceText: "",
                visualDescription: "Three boxed columns joined left to right by thick arrows, with a starred note above the middle column.",
                createdAt: Date().addingTimeInterval(-1_800)
            )
        )
    }

    // MARK: - Study Content

    static let flashcards: [Flashcard] = [
        Flashcard(
            front: "Where does photosynthesis take place?",
            back: "In the chloroplasts, specifically the thylakoid membranes and the stroma.",
            sourceCardTitle: "Photosynthesis",
            category: "Organelles"
        ),
        Flashcard(
            front: "What are the three stages of cellular respiration?",
            back: "Glycolysis, the Krebs cycle, and the electron transport chain.",
            sourceCardTitle: "Cellular Respiration",
            category: "Energy"
        ),
        Flashcard(
            front: "What does 'selectively permeable' mean?",
            back: "The membrane lets some substances cross while blocking others.",
            sourceCardTitle: "The Cell Membrane",
            category: "Membranes"
        )
    ]

    static let quizQuestions: [QuizQuestion] = [
        QuizQuestion(
            question: "Which organelle carries out photosynthesis?",
            options: ["Chloroplast", "Mitochondrion", "Ribosome", "Golgi apparatus"],
            correctAnswerIndex: 0,
            sourceCardTitle: "Photosynthesis"
        ),
        QuizQuestion(
            question: "Where does glycolysis occur?",
            options: ["Nucleus", "Cytoplasm", "Mitochondrial matrix", "Cell membrane"],
            correctAnswerIndex: 1,
            sourceCardTitle: "Cellular Respiration"
        ),
        QuizQuestion(
            question: "What model describes the cell membrane?",
            options: ["Lock and key", "Fluid mosaic", "Induced fit", "Double helix"],
            correctAnswerIndex: 1,
            sourceCardTitle: "The Cell Membrane"
        )
    ]

    /// A finished quiz where `correct` of the questions were answered right.
    ///
    /// Results styling changes with the score, so previews need to be able to
    /// ask for a good run and a bad one.
    static func quizResult(correct: Int) -> QuizResult {
        let answers: [Int?] = quizQuestions.enumerated().map { index, question in
            index < correct ? question.correctAnswerIndex : (question.correctAnswerIndex + 1) % 4
        }
        return QuizResult(
            questions: quizQuestions,
            answers: answers,
            startedAt: Date().addingTimeInterval(-240),
            completedAt: Date()
        )
    }

    static let flashcardStudyResult = FlashcardStudyResult(
        flashcards: flashcards,
        cardsStudied: flashcards.count,
        cardsFlipped: flashcards.count + 2,
        startedAt: Date().addingTimeInterval(-180),
        completedAt: Date()
    )

    // MARK: - Scanning

    static let scannedBook = ScannedBookCode(
        code: "9780306406157",
        isISBN: true,
        recognizedTitle: "Molecular Biology of the Cell"
    )

    static let documentBoundary = DocumentBoundary(
        topLeft: CGPoint(x: 0.12, y: 0.86),
        topRight: CGPoint(x: 0.88, y: 0.84),
        bottomRight: CGPoint(x: 0.90, y: 0.18),
        bottomLeft: CGPoint(x: 0.10, y: 0.20),
        confidence: 0.94
    )

    // MARK: - PDF

    /// A small multi-page PDF on disk, for previewing the import flow.
    ///
    /// `PDFImportView` takes a file URL and reads it, so a preview needs a real
    /// file. Each page carries well over the 30 characters `PDFImporter`
    /// requires, otherwise the importer would skip them all.
    static let pdfURL: URL = {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreviewSample.pdf")

        let pageSize = CGRect(x: 0, y: 0, width: 612, height: 792)
        let bodies = [
            "Chapter 1: The Cell Membrane. A phospholipid bilayer studded with proteins controls what enters and leaves the cell, making it selectively permeable.",
            "Chapter 2: Photosynthesis. Plants convert light energy into chemical energy stored as sugar, consuming carbon dioxide and water and releasing oxygen.",
            "Chapter 3: Cellular Respiration. Cells break glucose down to release energy as ATP through glycolysis, the Krebs cycle and the electron transport chain."
        ]

        let data = UIGraphicsPDFRenderer(bounds: pageSize).pdfData { context in
            for body in bodies {
                context.beginPage()
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 18)
                ]
                NSAttributedString(string: body, attributes: attributes)
                    .draw(in: pageSize.insetBy(dx: 48, dy: 72))
            }
        }

        try? data.write(to: url)
        return url
    }()
}

#endif

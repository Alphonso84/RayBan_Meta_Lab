//
//  PreviewSamplesTests.swift
//  Smart GlassesTests
//
//  Checks that the preview fixtures actually work.
//
//  A preview that compiles can still crash the canvas — the sample store is
//  built with a force-try, the deck is resolved through a `#Predicate`, and the
//  sample PDF is written to disk. None of that is exercised by a build, and a
//  broken preview is usually discovered by opening the file weeks later.
//

import Testing
import Foundation
import SwiftData
@testable import Smart_Glasses

@MainActor
struct PreviewSamplesTests {

    // MARK: - Store

    @Test func sampleStoreBuildsAndSeeds() throws {
        let context = PreviewSamples.container.mainContext

        let decks = try context.fetch(FetchDescriptor<SummaryDeck>())
        let cards = try context.fetch(FetchDescriptor<SummaryCard>())

        #expect(decks.count == 3)
        #expect(cards.count == 5)
        #expect(decks.contains { $0.isQuickCapture })
    }

    /// A preview must never write to the real library.
    @Test func sampleStoreIsInMemoryOnly() {
        let configuration = PreviewSamples.container.configurations.first

        #expect(configuration?.isStoredInMemoryOnly == true)
    }

    /// Previews should not drift between runs, so this must always resolve to
    /// the same deck rather than whatever the fetch happens to return first.
    @Test func sampleDeckIsStable() {
        #expect(PreviewSamples.deck.title == PreviewSamples.deck.title)
        #expect(PreviewSamples.deck.title == "Cell Biology")
        #expect(!PreviewSamples.deck.isQuickCapture)
    }

    @Test func sampleCardHasContentWorthShowing() {
        let card = PreviewSamples.card

        #expect(!card.title.isEmpty)
        #expect(!card.summary.isEmpty)
        #expect(!card.keyPoints.isEmpty)
    }

    // MARK: - Flashcards

    /// `FlashcardView.startStudy()` calls the language model unless the deck has
    /// cached flashcards. A preview cannot run the model, so without this the
    /// canvas sits on a spinner.
    @Test func sampleDeckShipsCachedFlashcards() {
        let deck = PreviewSamples.deck

        #expect(deck.hasFlashcards)
        #expect(deck.cachedFlashcards?.isEmpty == false)
    }

    /// An outdated cache fires a "regenerate?" alert over the preview.
    @Test func cachedFlashcardsAreNotStale() {
        #expect(!PreviewSamples.deck.areFlashcardsOutdated)
    }

    // MARK: - Quiz

    @Test(arguments: [0, 1, 2, 3])
    func quizResultScoresAsRequested(correct: Int) {
        let result = PreviewSamples.quizResult(correct: correct)

        #expect(result.score == correct)
        #expect(result.total == PreviewSamples.quizQuestions.count)
    }

    /// Four options with an in-range answer is what `QuizView` renders against.
    @Test func quizQuestionsAreWellFormed() {
        for question in PreviewSamples.quizQuestions {
            #expect(question.options.count == 4)
            #expect(question.correctAnswerIndex >= 0)
            #expect(question.correctAnswerIndex < 4)
        }
    }

    // MARK: - PDF

    /// `PDFImportView` reads a real file, and `PDFImporter` drops any page under
    /// 30 characters — so a sample PDF that is too sparse imports as nothing.
    @Test func samplePDFExistsAndYieldsPages() {
        let url = PreviewSamples.pdfURL

        #expect(FileManager.default.fileExists(atPath: url.path))

        let extracted = PDFImporter.extractPages(from: url)
        #expect(extracted.document != nil)
        #expect(extracted.pages.count == 3)
        #expect(extracted.pages.allSatisfy { $0.text.count >= 30 })
    }

    // MARK: - Scanning

    @Test func sampleBookCodeIsARecognizableISBN() {
        let book = PreviewSamples.scannedBook

        #expect(book.isISBN)
        #expect(book.hasCode)
        #expect(RecognizedBarcode(payload: book.code, symbology: "ean13").isISBN)
    }

    /// The overlay draws a quadrilateral, so the corners have to be inside
    /// Vision's normalized space or it renders off-screen.
    @Test func sampleBoundaryIsNormalized() {
        let boundary = PreviewSamples.documentBoundary
        let corners = [boundary.topLeft, boundary.topRight, boundary.bottomRight, boundary.bottomLeft]

        #expect(corners.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
        #expect(boundary.topLeft.y > boundary.bottomLeft.y)  // Vision origin is bottom-left
    }
}

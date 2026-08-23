//
//  FlashcardView.swift
//  Smart Glasses
//
//  Main flashcard study interface with swipe navigation
//

import SwiftUI
import SwiftData

struct FlashcardView: View {
    @Bindable var deck: SummaryDeck
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var generator = FlashcardGenerator()
    @ObservedObject private var voiceFeedback = VoiceFeedbackManager.shared
    
    @State private var currentIndex = 0
    @State private var flippedCards: Set<Int> = []
    @State private var studyStartedAt = Date()
    @State private var studyResult: FlashcardStudyResult? = nil
    @State private var showingPrintSheet = false
    @State private var showingOutdatedAlert = false
    @State private var pdfData: Data?
    @State private var loadedFromCache = false
    
    private var sortedCards: [SummaryCard] { deck.sortedCards }
    
    var body: some View {
        NavigationStack {
            Group {
                switch generator.state {
                case .idle, .generating:
                    generatingView
                case .complete:
                    if let result = studyResult {
                        FlashcardStudyResultsView(
                            result: result,
                            deckColor: deck.color,
                            onStudyAgain: { retryStudy() },
                            onDone: { dismiss() }
                        )
                    } else {
                        flashcardStudyView
                    }
                case .error(let message):
                    errorView(message)
                }
            }
            .navigationTitle("Flashcards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        voiceFeedback.stopSpeaking()
                        dismiss()
                    }
                }
                
                if generator.state == .complete && studyResult == nil {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                exportFlashcardsPDF()
                            } label: {
                                Label("Print Flashcards", systemImage: "printer")
                            }
                            
                            Button {
                                regenerateFlashcards()
                            } label: {
                                Label("Regenerate Flashcards", systemImage: "arrow.clockwise")
                            }
                            
                            Button {
                                finishStudy()
                            } label: {
                                Label("Finish Study", systemImage: "checkmark.circle")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
        .onAppear {
            startStudy()
        }
        .sheet(isPresented: $showingPrintSheet) {
            if let data = pdfData {
                FlashcardShareSheet(items: [data], fileName: "\(deck.title) Flashcards.pdf")
            }
        }
        .alert("Flashcards Outdated", isPresented: $showingOutdatedAlert) {
            Button("Regenerate") {
                regenerateFlashcards()
            }
            Button("Use Existing", role: .cancel) {}
        } message: {
            Text("\(deck.cardsAddedSinceFlashcards) card(s) have been added since these flashcards were generated. Would you like to regenerate them?")
        }
    }
    
    // MARK: - Generating View
    
    private var generatingView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(deck.color)
                .symbolEffect(.pulse, isActive: generator.state == .generating)
            
            Text("Generating flashcards...")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("Creating study cards from \(sortedCards.count) cards")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            ProgressView(value: generator.progress)
                .progressViewStyle(.linear)
                .tint(deck.color)
                .padding(.horizontal, 40)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Flashcard Study View
    
    private var flashcardStudyView: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack {
                Text("\(currentIndex + 1) / \(generator.flashcards.count)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("Tap to flip")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            // Progress bar
            ProgressView(value: Double(currentIndex + 1), total: Double(generator.flashcards.count))
                .tint(deck.color)
                .padding(.horizontal)
                .padding(.top, 8)
            
            // Card carousel with swipe
            TabView(selection: $currentIndex) {
                ForEach(Array(generator.flashcards.enumerated()), id: \.element.id) { index, flashcard in
                    FlashcardCardView(
                        flashcard: flashcard,
                        isFlipped: flippedCards.contains(index),
                        deckColor: deck.color,
                        onFlip: {
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                if flippedCards.contains(index) {
                                    flippedCards.remove(index)
                                } else {
                                    flippedCards.insert(index)
                                    // Haptic feedback on flip
                                    let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
                                    impactGenerator.impactOccurred()
                                }
                            }
                        }
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxHeight: .infinity)
            
            // Navigation buttons
            HStack(spacing: 40) {
                Button {
                    withAnimation {
                        currentIndex = max(0, currentIndex - 1)
                    }
                } label: {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(currentIndex > 0 ? deck.color : Color(.systemGray4))
                }
                .disabled(currentIndex == 0)
                
                Button {
                    withAnimation {
                        currentIndex = min(generator.flashcards.count - 1, currentIndex + 1)
                    }
                } label: {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(currentIndex < generator.flashcards.count - 1 ? deck.color : Color(.systemGray4))
                }
                .disabled(currentIndex >= generator.flashcards.count - 1)
            }
            .padding(.vertical, 20)
        }
    }
    
    // MARK: - Error View
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            
            Text("Couldn't Generate Flashcards")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button {
                retryStudy()
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.headline)
                    .padding()
                    .background(deck.color)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            Spacer()
        }
    }
    
    // MARK: - Actions
    
    private func startStudy() {
        studyResult = nil
        currentIndex = 0
        flippedCards = []
        studyStartedAt = Date()
        
        // Check for cached flashcards
        if let cached = deck.cachedFlashcards, !cached.isEmpty {
            generator.loadCachedFlashcards(cached)
            loadedFromCache = true
            
            // Show alert if flashcards are outdated
            if deck.areFlashcardsOutdated {
                showingOutdatedAlert = true
            }
        } else {
            // Generate new flashcards
            generateNewFlashcards()
        }
    }
    
    private func generateNewFlashcards() {
        loadedFromCache = false
        let flashcardCount = min(15, sortedCards.count * 5)
        Task {
            await generator.generateFlashcards(from: sortedCards, count: flashcardCount)
            
            // Save to cache after generation
            if generator.state == .complete && !generator.flashcards.isEmpty {
                deck.saveFlashcards(generator.flashcards)
                try? modelContext.save()
            }
        }
    }
    
    private func regenerateFlashcards() {
        generator.reset()
        currentIndex = 0
        flippedCards = []
        generateNewFlashcards()
    }
    
    private func retryStudy() {
        generator.reset()
        generateNewFlashcards()
    }
    
    private func finishStudy() {
        studyResult = FlashcardStudyResult(
            flashcards: generator.flashcards,
            cardsStudied: currentIndex + 1,
            cardsFlipped: flippedCards.count,
            startedAt: studyStartedAt,
            completedAt: Date()
        )
    }
    
    private func exportFlashcardsPDF() {
        pdfData = PDFGenerator.generateFlashcardPDF(
            flashcards: generator.flashcards,
            deckTitle: deck.title,
            deckColor: deck.color
        )
        showingPrintSheet = true
    }
}

// MARK: - Share Sheet for Flashcards

struct FlashcardShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var fileName: String = "Flashcards.pdf"
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        var activityItems: [Any] = items
        
        if let pdfData = items.first as? Data {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try? pdfData.write(to: tempURL)
            activityItems = [tempURL]
        }
        
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        
        controller.excludedActivityTypes = [
            .assignToContact,
            .addToReadingList,
            .postToVimeo,
            .postToWeibo,
            .postToFlickr,
            .postToTencentWeibo
        ]
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    // The sample deck ships with cached flashcards, so `startStudy()` loads
    // them instead of calling a language model the preview cannot run.
    FlashcardView(deck: PreviewSamples.deck)
        .modelContainer(PreviewSamples.container)
}

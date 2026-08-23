//
//  DeckDetailView.swift
//  Smart Glasses
//
//  Created by Claude on 1/22/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Detail view for a deck showing cards in a carousel
struct DeckDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var deck: SummaryDeck

    @State private var selectedCardIndex = 0
    @State private var showingEditSheet = false
    @State private var showingShareSheet = false
    @State private var showingDeckSummary = false
    @State private var showingQuiz = false
    @State private var showingFlashcards = false
    @State private var showingPDFPicker = false
    @State private var importedPDFURL: URL?
    @State private var showingPDFImportView = false
    @State private var pdfData: Data?

    // Provider recommendation alert
    @AppStorage("selectedProvider") private var selectedProvider: String = "apple"
    @AppStorage("hideOpenAIRecommendation") private var hideRecommendation = false
    @State private var showingProviderAlert = false
    @State private var pendingAction: PendingAIAction?

    enum PendingAIAction {
        case quiz, flashcards, deckSummary
    }

    @StateObject private var summarizer = StreamingSummarizer()
    @ObservedObject private var voiceFeedback = VoiceFeedbackManager.shared
    private var sortedCards: [SummaryCard] { deck.sortedCards }
    private var isPlaying: Bool { voiceFeedback.isSpeaking }

    var body: some View {
        ZStack {
            // Background with deck color
            deck.color.opacity(0.1)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if sortedCards.isEmpty {
                    emptyState
                } else {
                    // Card carousel
                    cardCarousel

                    // Card indicator
                    cardIndicator
                        .padding(.vertical, 16)

                    // Playback controls
                    playbackControls
                        .padding(.bottom, 16)
                }
            }
        }
        .navigationTitle(deck.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Label("Edit Deck", systemImage: "pencil")
                    }

                    if sortedCards.count >= 2 {
                        Button {
                            begin(.deckSummary)
                        } label: {
                            if deck.hasDeckSummary {
                                Label(deck.isSummaryOutdated ? "View Deck Summary (Outdated)" : "View Deck Summary", systemImage: "doc.text.magnifyingglass")
                            } else {
                                Label("Generate Deck Summary", systemImage: "sparkles")
                            }
                        }
                    }

                    if !sortedCards.isEmpty {
                        Button {
                            speakAllCards()
                        } label: {
                            Label("Read All Cards", systemImage: "speaker.wave.3")
                        }

                        if sortedCards.count >= 2 {
                            Button {
                                begin(.quiz)
                            } label: {
                                Label("Start Quiz", systemImage: "questionmark.circle")
                            }

                            Button {
                                begin(.flashcards)
                            } label: {
                                Label("Study Flashcards", systemImage: "rectangle.on.rectangle.angled")
                            }
                        }

                        Button {
                            exportCurrentCardPDF()
                        } label: {
                            Label("Export Card as PDF", systemImage: "doc.text")
                        }
                    }

                    Button {
                        showingPDFPicker = true
                    } label: {
                        Label("Import PDF", systemImage: "doc.badge.plus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditDeckSheet(deck: deck)
        }
        .sheet(isPresented: $showingShareSheet) {
            if let data = pdfData {
                ShareSheet(items: [data], fileName: "\(currentCard?.title ?? "Card").pdf")
            }
        }
        .sheet(isPresented: $showingDeckSummary) {
            DeckSummarySheet(deck: deck, summarizer: summarizer)
        }
        .sheet(isPresented: $showingQuiz) {
            QuizView(deck: deck)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showingFlashcards) {
            FlashcardView(deck: deck)
                .presentationDetents([.large])
        }
        .fileImporter(
            isPresented: $showingPDFPicker,
            allowedContentTypes: [.pdf]
        ) { result in
            switch result {
            case .success(let url):
                importedPDFURL = url
                showingPDFImportView = true
            case .failure:
                break
            }
        }
        .sheet(isPresented: $showingPDFImportView) {
            if let url = importedPDFURL {
                PDFImportView(pdfURL: url, targetDeck: deck)
            }
        }
        .alert(recommendedProviderTitle, isPresented: $showingProviderAlert) {
            Button("Continue Anyway") { executePendingAction() }
            Button(recommendedProviderButton) {
                selectedProvider = recommendedProvider
                executePendingAction()
            }
            Button("Don't Show Again", role: .cancel) {
                hideRecommendation = true
                executePendingAction()
            }
        } message: {
            Text(providerAlertMessage)
        }
        .onAppear {
            deck.markAccessed()
        }
        .onDisappear {
            voiceFeedback.stopSpeaking()
        }
    }

    // MARK: - Provider Alert Helpers

    /// Recommend Apple's own cloud tier: no API key, no billing, prompts not stored.
    private let recommendedProvider = "pcc"
    private let recommendedProviderTitle = "Apple Cloud Recommended"
    private let recommendedProviderButton = "Switch to Apple Cloud"

    private var providerAlertMessage: String {
        let remedy = "Apple Cloud (Private Cloud Compute) has a much larger context window and can reason about the material before answering. It needs no API key and stores no prompts."

        // The alert only appears once the deck has been measured against the
        // on-device context window, so these can state the problem rather than
        // hedge about what the model "may" struggle with.
        switch pendingAction {
        case .quiz:
            return "This deck is larger than the on-device model's context window, so it would only see part of your cards when writing questions. \(remedy)"
        case .flashcards:
            return "This deck is larger than the on-device model's context window, so it would only see part of your cards when making flashcards. \(remedy)"
        case .deckSummary:
            return "This deck is larger than the on-device model's context window, so it would have to be summarized in batches and themes spanning several cards may be missed. \(remedy)"
        case nil:
            return ""
        }
    }

    /// Start an AI action, warning about the on-device model only when this
    /// deck genuinely will not fit its context window.
    ///
    /// The alert used to fire for every deck on the on-device provider, which
    /// trained people to dismiss it. Now it is a measurement.
    private func begin(_ action: PendingAIAction) {
        guard selectedProvider == "apple", !hideRecommendation else {
            execute(action)
            return
        }

        Task {
            if await deckExceedsOnDeviceBudget() {
                pendingAction = action
                showingProviderAlert = true
            } else {
                execute(action)
            }
        }
    }

    /// Whether this deck's content exceeds what the on-device model can hold in
    /// one request. Quizzes and flashcards read the same combined card text as
    /// the deck summary, so one measurement covers all three actions.
    private func deckExceedsOnDeviceBudget() async -> Bool {
        let budget = await TokenBudget.makeBudget(instructions: StreamingSummarizer.deckInstructions)
        return await !TokenBudget.fits(deck.combinedCardSummaries, in: budget)
    }

    private func execute(_ action: PendingAIAction) {
        switch action {
        case .quiz: showingQuiz = true
        case .flashcards: showingFlashcards = true
        case .deckSummary: showingDeckSummary = true
        }
    }

    private func executePendingAction() {
        if let pendingAction {
            execute(pendingAction)
        }
        pendingAction = nil
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 64))
                .foregroundStyle(deck.color.opacity(0.5))

            Text("No Cards Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Scan documents to add summary cards to this deck.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Card Carousel

    private var cardCarousel: some View {
        TabView(selection: $selectedCardIndex) {
            ForEach(Array(sortedCards.enumerated()), id: \.element.id) { index, card in
                CardCarouselItem(card: card, deckColor: deck.color)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxHeight: .infinity)
    }

    // MARK: - Card Indicator

    private var cardIndicator: some View {
        HStack(spacing: 8) {
            Text("\(selectedCardIndex + 1) / \(sortedCards.count)")
                .font(.subheadline)
                .fontWeight(.medium)
                .monospacedDigit()

            if sortedCards.count > 1 {
                HStack(spacing: 4) {
                    ForEach(0..<min(sortedCards.count, 10), id: \.self) { index in
                        Circle()
                            .fill(index == selectedCardIndex ? deck.color : Color(.systemGray4))
                            .frame(width: 6, height: 6)
                    }
                    if sortedCards.count > 10 {
                        Text("...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        HStack(spacing: 24) {
            // Previous
            Button {
                withAnimation {
                    selectedCardIndex = max(0, selectedCardIndex - 1)
                }
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(selectedCardIndex > 0 ? deck.color : Color(.systemGray4))
            }
            .disabled(selectedCardIndex == 0)

            // Play/Speak current card
            Button {
                if isPlaying {
                    voiceFeedback.stopSpeaking()
                } else {
                    speakCurrentCard()
                }
            } label: {
                Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(deck.color)
            }

            // Next
            Button {
                withAnimation {
                    selectedCardIndex = min(sortedCards.count - 1, selectedCardIndex + 1)
                }
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(selectedCardIndex < sortedCards.count - 1 ? deck.color : Color(.systemGray4))
            }
            .disabled(selectedCardIndex >= sortedCards.count - 1)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Computed Properties

    private var currentCard: SummaryCard? {
        guard selectedCardIndex < sortedCards.count else { return nil }
        return sortedCards[selectedCardIndex]
    }

    // MARK: - Actions

    private func speakCurrentCard() {
        guard let card = currentCard else { return }
        voiceFeedback.speakSummary(card.textForSpeech)
    }

    private func speakAllCards() {
        // Speak all cards by queuing them
        for card in sortedCards {
            voiceFeedback.speakSummary(card.textForSpeech)
        }
    }

    private func exportCurrentCardPDF() {
        guard let card = currentCard else { return }
        pdfData = PDFGenerator.generatePDF(from: card)
        showingShareSheet = true
    }
}


// MARK: - Card Carousel Item

struct CardCarouselItem: View {
    @Environment(\.modelContext) private var modelContext
    let card: SummaryCard
    let deckColor: Color

    @State private var showingDetail = false

    var body: some View {
        VStack(spacing: 0) {
            // Card content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header with thumbnail
                    HStack(alignment: .top, spacing: 12) {
                        if let thumbnailData = card.thumbnailData,
                           let uiImage = UIImage(data: thumbnailData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 70, height: 90)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.title)
                                .font(.title3)
                                .fontWeight(.bold)
                                .lineLimit(2)

                            Text(card.formattedDate)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let pageNumber = card.pageNumber {
                                Text("Page \(pageNumber)")
                                    .font(.caption)
                                    .foregroundStyle(deckColor)
                            }
                        }

                        Spacer()
                    }

                    Divider()

                    // Summary
                    Text(card.summary)
                        .font(.body)
                        .lineSpacing(4)

                    // Key points
                    if !card.keyPoints.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Key Points")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)

                            ForEach(card.keyPoints, id: \.self) { point in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(deckColor)
                                        .font(.subheadline)
                                        .padding(.top, 1)

                                    Text(point)
                                        .font(.subheadline)
                                        .lineSpacing(2)
                                }
                            }
                        }
                    }

                    // Diagrams, charts and tables the model read off the page
                    if card.hasVisualDescription, let visualDescription = card.visualDescription {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("On the Page", systemImage: "chart.xyaxis.line")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)

                            Text(visualDescription)
                                .font(.subheadline)
                                .lineSpacing(2)
                        }
                    }
                }
                .padding(20)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .onTapGesture {
            showingDetail = true
        }
        .sheet(isPresented: $showingDetail) {
            CardDetailSheet(card: card)
        }
        .contextMenu {
            Button(role: .destructive) {
                deleteCard()
            } label: {
                Label("Delete Card", systemImage: "trash")
            }
        }
    }

    private func deleteCard() {
        modelContext.delete(card)
        try? modelContext.save()
    }
}

// MARK: - Edit Deck Sheet

struct EditDeckSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var deck: SummaryDeck

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var selectedColor: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Deck Title", text: $title)
                    TextField("Description (optional)", text: $description)
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(SummaryDeck.presetColors, id: \.self) { colorHex in
                            Button {
                                selectedColor = colorHex
                            } label: {
                                Circle()
                                    .fill(Color(hex: colorHex) ?? .blue)
                                    .frame(width: 44, height: 44)
                                    .overlay {
                                        if selectedColor == colorHex {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.white)
                                                .fontWeight(.bold)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    HStack {
                        Text("Cards in Deck")
                        Spacer()
                        Text("\(deck.cardCount)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Created")
                        Spacer()
                        Text(deck.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveDeck()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                title = deck.title
                description = deck.deckDescription ?? ""
                selectedColor = deck.colorHex
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func saveDeck() {
        deck.title = title.trimmingCharacters(in: .whitespaces)
        deck.deckDescription = description.isEmpty ? nil : description
        deck.colorHex = selectedColor

        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Deck Summary Sheet

struct DeckSummarySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var deck: SummaryDeck
    @ObservedObject var summarizer: StreamingSummarizer

    @ObservedObject private var voiceFeedback = VoiceFeedbackManager.shared
    @State private var showingOutdatedAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    headerSection

                    if summarizer.state == .summarizing || summarizer.state == .preparing {
                        // Generating state
                        generatingView
                    } else if deck.hasDeckSummary {
                        // Display existing summary
                        summaryContentView
                    } else {
                        // No summary yet
                        noSummaryView
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Deck Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                if deck.hasDeckSummary {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                speakSummary()
                            } label: {
                                Label(voiceFeedback.isSpeaking ? "Stop" : "Read Summary", systemImage: voiceFeedback.isSpeaking ? "stop.fill" : "speaker.wave.3")
                            }

                            Button {
                                Task {
                                    await regenerateSummary()
                                }
                            } label: {
                                Label("Regenerate", systemImage: "arrow.clockwise")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            // Auto-generate if no summary exists
            if !deck.hasDeckSummary && deck.cardCount >= 2 {
                Task {
                    await generateSummary()
                }
            } else if deck.isSummaryOutdated && deck.hasDeckSummary {
                showingOutdatedAlert = true
            }
        }
        .onDisappear {
            voiceFeedback.stopSpeaking()
        }
        .alert("Summary Outdated", isPresented: $showingOutdatedAlert) {
            Button("Regenerate") {
                Task {
                    await regenerateSummary()
                }
            }
            Button("Keep Current", role: .cancel) {}
        } message: {
            Text("\(deck.cardsAddedSinceSummary) card(s) have been added since the last summary was generated. Would you like to regenerate it?")
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(deck.color)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "rectangle.stack.fill")
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(deck.title)
                    .font(.headline)

                Text("\(deck.cardCount) cards")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if deck.isSummaryOutdated && deck.hasDeckSummary {
                Label("\(deck.cardsAddedSinceSummary) new", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Generating View

    private var generatingView: some View {
        VStack(spacing: 16) {
            ProgressView(value: summarizer.progress)
                .progressViewStyle(.linear)
                .tint(deck.color)

            Text("Generating deck summary...")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !summarizer.streamingSummary.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Summary")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    Text(summarizer.streamingSummary)
                        .font(.body)
                        .lineSpacing(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }

            if !summarizer.streamingKeyPoints.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Key Themes")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    ForEach(summarizer.streamingKeyPoints, id: \.self) { theme in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(deck.color)
                                .font(.caption)
                                .padding(.top, 3)

                            Text(theme)
                                .font(.subheadline)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }
        }
    }

    // MARK: - Summary Content View

    private var summaryContentView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Summary section
            VStack(alignment: .leading, spacing: 8) {
                Text("Summary")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Text(deck.deckSummary ?? "")
                    .font(.body)
                    .lineSpacing(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))
            )

            // Key themes section
            if let keyPoints = deck.deckKeyPoints, !keyPoints.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Key Themes")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    ForEach(keyPoints, id: \.self) { theme in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(deck.color)
                                .font(.caption)
                                .padding(.top, 3)

                            Text(theme)
                                .font(.subheadline)
                                .lineSpacing(2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }

            // Metadata
            if let generatedAt = deck.summaryGeneratedAt {
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    Text("Generated \(generatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - No Summary View

    private var noSummaryView: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(deck.color)

            Text("Generate Deck Summary")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Create an AI-powered summary that combines insights from all \(deck.cardCount) cards in this deck.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                Task {
                    await generateSummary()
                }
            } label: {
                Label("Generate Summary", systemImage: "sparkles")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(deck.color)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top)
        }
        .padding(.vertical, 40)
    }

    // MARK: - Actions

    private func generateSummary() async {
        guard let result = await summarizer.summarizeDeck(
            cardSummaries: deck.combinedCardSummaries,
            cardCount: deck.cardCount,
            deckTitle: deck.title
        ) else { return }

        // Save to deck
        deck.deckSummary = result.summary
        deck.deckKeyPoints = result.keyThemes
        deck.summaryGeneratedAt = Date()

        try? modelContext.save()
    }

    private func regenerateSummary() async {
        deck.clearDeckSummary()
        await generateSummary()
    }

    private func speakSummary() {
        if voiceFeedback.isSpeaking {
            voiceFeedback.stopSpeaking()
        } else if let summary = deck.deckSummary {
            var textToSpeak = summary
            if let keyPoints = deck.deckKeyPoints, !keyPoints.isEmpty {
                textToSpeak += ". Key themes: " + keyPoints.joined(separator: ". ")
            }
            voiceFeedback.speakSummary(textToSpeak)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DeckDetailView(deck: SummaryDeck(
            title: "Swift Programming",
            colorHex: "007AFF",
            cards: [
                SummaryCard(
                    title: "Chapter 1: Basics",
                    summary: "Swift is a powerful and intuitive programming language. It combines the best in modern language thinking with wisdom from the wider Apple engineering culture.",
                    keyPoints: ["Type safety", "Modern syntax", "Performance"],
                    sourceText: "Full text here..."
                ),
                SummaryCard(
                    title: "Chapter 2: Functions",
                    summary: "Functions are self-contained chunks of code that perform a specific task. You give a function a name that identifies what it does.",
                    keyPoints: ["Named parameters", "Return values", "Closures"],
                    sourceText: "Full text here..."
                )
            ]
        ))
    }
    .modelContainer(for: [SummaryCard.self, SummaryDeck.self], inMemory: true)
}

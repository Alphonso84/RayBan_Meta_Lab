//
//  DeckLibraryView.swift
//  Smart Glasses
//
//  Created by Claude on 1/22/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Main library view showing all decks and unsorted cards
struct DeckLibraryView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \SummaryDeck.lastAccessedAt, order: .reverse) private var decks: [SummaryDeck]
    @Query(filter: #Predicate<SummaryCard> { $0.deck == nil }, sort: \SummaryCard.createdAt, order: .reverse)
    private var unsortedCards: [SummaryCard]

    @State private var searchText = ""
    @State private var showingNewDeckSheet = false
    @State private var selectedCard: SummaryCard?
    @State private var showingPDFPicker = false
    @State private var importedPDFURL: URL?
    @State private var showingPDFImportView = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Stats header
                    statsHeader

                    // Quick Capture / Unsorted cards
                    if !unsortedCards.isEmpty {
                        quickCaptureSection
                    }

                    // Decks grid
                    if !decks.isEmpty {
                        decksSection
                    }

                    // Empty state
                    if decks.isEmpty && unsortedCards.isEmpty {
                        emptyState
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Library")
            .searchable(text: $searchText, prompt: "Search cards...")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingNewDeckSheet = true
                        } label: {
                            Label("New Deck", systemImage: "folder.badge.plus")
                        }

                        Button {
                            showingPDFPicker = true
                        } label: {
                            Label("Import PDF", systemImage: "doc.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewDeckSheet) {
                NewDeckSheet()
            }
            .sheet(item: $selectedCard) { card in
                CardDetailSheet(card: card)
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
                    PDFImportView(pdfURL: url, targetDeck: nil)
                }
            }
        }
    }

    // MARK: - Stats Header

    private var statsHeader: some View {
        HStack(spacing: 16) {
            StatBox(
                value: "\(decks.count)",
                label: "Decks",
                icon: "rectangle.stack.fill",
                color: .blue
            )

            StatBox(
                value: "\(totalCards)",
                label: "Cards",
                icon: "doc.text.fill",
                color: .green
            )

            StatBox(
                value: "\(unsortedCards.count)",
                label: "Unsorted",
                icon: "tray.fill",
                color: .orange
            )
        }
    }

    private var totalCards: Int {
        decks.reduce(0) { $0 + $1.cardCount } + unsortedCards.count
    }

    // MARK: - Quick Capture Section

    private var quickCaptureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "tray.fill")
                    .foregroundStyle(.orange)
                Text("Quick Capture")
                    .font(.headline)
                Spacer()
                Text("\(unsortedCards.count) cards")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Horizontal scroll of unsorted cards
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(filteredUnsortedCards) { card in
                        MiniCardView(card: card)
                            .onTapGesture {
                                selectedCard = card
                            }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var filteredUnsortedCards: [SummaryCard] {
        if searchText.isEmpty {
            return unsortedCards
        }
        return unsortedCards.filter { card in
            card.title.localizedCaseInsensitiveContains(searchText) ||
            card.summary.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Decks Section

    private var decksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Decks")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(filteredDecks) { deck in
                    NavigationLink(destination: DeckDetailView(deck: deck)) {
                        DeckCardView(deck: deck)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            deleteDeck(deck)
                        } label: {
                            Label("Delete Deck", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private var filteredDecks: [SummaryDeck] {
        if searchText.isEmpty {
            return decks
        }
        return decks.filter { deck in
            deck.title.localizedCaseInsensitiveContains(searchText) ||
            deck.cards.contains { card in
                card.title.localizedCaseInsensitiveContains(searchText) ||
                card.summary.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)

            Text("Your Library is Empty")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Scan documents to create summary cards.\nOrganize them into decks for easy review.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showingNewDeckSheet = true
            } label: {
                Label("Create Your First Deck", systemImage: "folder.badge.plus")
                    .font(.headline)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top, 8)
        }
        .padding(.vertical, 60)
    }

    // MARK: - Actions

    private func deleteDeck(_ deck: SummaryDeck) {
        modelContext.delete(deck)
        try? modelContext.save()
    }
}

// MARK: - Supporting Views

struct StatBox: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
            }

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

struct MiniCardView: View {
    let card: SummaryCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            if let thumbnailData = card.thumbnailData,
               let uiImage = UIImage(data: thumbnailData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 120, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 120, height: 80)
                    .overlay {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.tertiary)
                    }
            }

            Text(card.title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)

            Text(card.previewText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(width: 120)
    }
}

struct DeckCardView: View {
    let deck: SummaryDeck

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Deck icon with color
            RoundedRectangle(cornerRadius: 12)
                .fill(deck.color.gradient)
                .frame(height: 80)
                .overlay {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.9))
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(deck.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                HStack {
                    Text("\(deck.cardCount) cards")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(deck.formattedLastAccessed)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

// MARK: - New Deck Sheet

struct NewDeckSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var selectedColor = SummaryDeck.randomColor

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
            }
            .navigationTitle("New Deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createDeck()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func createDeck() {
        let deck = SummaryDeck(
            title: title.trimmingCharacters(in: .whitespaces),
            deckDescription: description.isEmpty ? nil : description,
            colorHex: selectedColor
        )

        modelContext.insert(deck)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Card Detail Sheet

struct CardDetailSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \SummaryDeck.lastAccessedAt, order: .reverse) private var decks: [SummaryDeck]

    let card: SummaryCard

    @State private var isEditing = false
    @State private var editedTitle: String = ""
    @State private var showingMoveSheet = false
    @State private var showingShareSheet = false
    @State private var pdfData: Data?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Thumbnail
                    if let thumbnailData = card.thumbnailData,
                       let uiImage = UIImage(data: thumbnailData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    }

                    // Title
                    if isEditing {
                        TextField("Title", text: $editedTitle)
                            .font(.title2)
                            .fontWeight(.bold)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Text(card.title)
                            .font(.title2)
                            .fontWeight(.bold)
                    }

                    // Metadata
                    HStack {
                        Label(card.formattedDate, systemImage: "calendar")
                        Spacer()
                        Label("\(card.wordCount) words", systemImage: "text.word.spacing")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Divider()

                    // Summary
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Summary")
                            .font(.headline)

                        Text(card.summary)
                            .font(.body)
                    }

                    // Key Points
                    if !card.keyPoints.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Key Points")
                                .font(.headline)

                            ForEach(card.keyPoints, id: \.self) { point in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.caption)
                                        .padding(.top, 2)

                                    Text(point)
                                        .font(.subheadline)
                                }
                            }
                        }
                    }

                    // Source text (collapsible)
                    DisclosureGroup {
                        Text(card.sourceText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } label: {
                        Text("Original Text")
                            .font(.headline)
                    }
                }
                .padding()
            }
            .navigationTitle("Card Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            editedTitle = card.title
                            isEditing.toggle()
                        } label: {
                            Label(isEditing ? "Save" : "Edit Title", systemImage: "pencil")
                        }

                        Button {
                            showingMoveSheet = true
                        } label: {
                            Label("Move to Deck", systemImage: "folder")
                        }

                        Button {
                            exportPDF()
                        } label: {
                            Label("Export PDF", systemImage: "doc.text")
                        }

                        Divider()

                        Button(role: .destructive) {
                            deleteCard()
                        } label: {
                            Label("Delete Card", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingMoveSheet) {
                MoveCardSheet(card: card, decks: decks)
            }
            .sheet(isPresented: $showingShareSheet) {
                if let data = pdfData {
                    ShareSheet(items: [data], fileName: "\(card.title).pdf")
                }
            }
            .onChange(of: isEditing) { wasEditing, nowEditing in
                if wasEditing && !nowEditing {
                    saveTitle()
                }
            }
        }
    }

    private func saveTitle() {
        card.title = editedTitle
        try? modelContext.save()
    }

    private func deleteCard() {
        modelContext.delete(card)
        try? modelContext.save()
        dismiss()
    }

    private func exportPDF() {
        pdfData = PDFGenerator.generatePDF(from: card)
        showingShareSheet = true
    }
}

// MARK: - Move Card Sheet

struct MoveCardSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let card: SummaryCard
    let decks: [SummaryDeck]

    var body: some View {
        NavigationStack {
            List {
                Button {
                    moveCard(to: nil)
                } label: {
                    HStack {
                        Image(systemName: "tray")
                            .foregroundStyle(.orange)
                        Text("Quick Capture (No Deck)")
                        Spacer()
                        if card.deck == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }

                ForEach(decks) { deck in
                    Button {
                        moveCard(to: deck)
                    } label: {
                        HStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(deck.color)
                                .frame(width: 24, height: 24)
                            Text(deck.title)
                            Spacer()
                            if card.deck?.id == deck.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Move Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func moveCard(to deck: SummaryDeck?) {
        // Remove from old deck
        if let oldDeck = card.deck {
            oldDeck.cards.removeAll { $0.id == card.id }
        }

        // Add to new deck
        card.deck = deck
        if let deck = deck {
            deck.cards.append(card)
            deck.markAccessed()
        }

        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Share Sheet

/// UIKit wrapper for UIActivityViewController
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var fileName: String = "Document.pdf"

    func makeUIViewController(context: Context) -> UIActivityViewController {
        // If the first item is PDF data, wrap it in a temporary file for better sharing
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

        // Exclude some activities that don't make sense for PDFs
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

// MARK: - Preview

#Preview {
    DeckLibraryView()
        .modelContainer(PreviewSamples.container)
}

#Preview("Empty library") {
    DeckLibraryView()
        .modelContainer(for: [SummaryCard.self, SummaryDeck.self], inMemory: true)
}

#Preview("Stat box") {
    HStack(spacing: 12) {
        StatBox(value: "4", label: "Decks", icon: "rectangle.stack.fill", color: .blue)
        StatBox(value: "27", label: "Cards", icon: "doc.text.fill", color: .green)
        StatBox(value: "3", label: "Unsorted", icon: "tray.fill", color: .orange)
    }
    .padding()
}

#Preview("Mini card") {
    MiniCardView(card: PreviewSamples.card)
        .modelContainer(PreviewSamples.container)
}

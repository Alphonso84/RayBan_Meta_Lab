//
//  CardPreviewSheet.swift
//  Smart Glasses
//
//  Created by Claude on 1/22/26.
//

import SwiftUI
import SwiftData

/// Sheet for previewing a summary card and selecting which deck to save it to
struct CardPreviewSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \SummaryDeck.lastAccessedAt, order: .reverse) private var decks: [SummaryDeck]

    let card: SummaryCard
    var onSave: (SummaryDeck?) -> Void
    var onDiscard: () -> Void

    @State private var selectedDeck: SummaryDeck?
    @State private var showingNewDeckSheet = false
    @State private var newDeckTitle = ""
    @State private var newDeckColor = SummaryDeck.randomColor

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Card preview
                    cardPreview

                    // Deck selection
                    deckSelector

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Save Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") {
                        onDiscard()
                    }
                    .foregroundStyle(.red)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(selectedDeck)
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingNewDeckSheet) {
                newDeckSheet
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Card Preview

    private var cardPreview: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with thumbnail
            HStack(alignment: .top, spacing: 12) {
                // Thumbnail
                if let thumbnailData = card.thumbnailData,
                   let uiImage = UIImage(data: thumbnailData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: 60, height: 80)
                        .overlay {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.tertiary)
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(card.title)
                        .font(.headline)
                        .lineLimit(2)

                    Text(card.formattedDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(card.wordCount) words")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }

            Divider()

            // Summary
            Text(card.summary)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(4)

            // Key points
            if !card.keyPoints.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Key Points")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    ForEach(card.keyPoints.prefix(3), id: \.self) { point in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                                .padding(.top, 2)

                            Text(point)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }
                    }

                    if card.keyPoints.count > 3 {
                        Text("+\(card.keyPoints.count - 3) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

    // MARK: - Deck Selector

    private var deckSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Add to Deck")
                    .font(.headline)

                Spacer()

                Button {
                    showingNewDeckSheet = true
                } label: {
                    Label("New Deck", systemImage: "plus.circle.fill")
                        .font(.subheadline)
                }
            }

            // Quick Capture option (no deck)
            deckOption(
                title: "Quick Capture",
                subtitle: "Save without a deck",
                color: Color(.systemGray),
                icon: "tray",
                isSelected: selectedDeck == nil
            ) {
                selectedDeck = nil
            }

            // Existing decks
            ForEach(decks) { deck in
                deckOption(
                    title: deck.title,
                    subtitle: "\(deck.cardCount) cards",
                    color: deck.color,
                    icon: "rectangle.stack.fill",
                    isSelected: selectedDeck?.id == deck.id
                ) {
                    selectedDeck = deck
                }
            }

            if decks.isEmpty {
                Text("No decks yet. Create one to organize your cards!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
    }

    private func deckOption(
        title: String,
        subtitle: String,
        color: Color,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Color indicator
                RoundedRectangle(cornerRadius: 8)
                    .fill(color)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: icon)
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.title3)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - New Deck Sheet

    private var newDeckSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Deck Title", text: $newDeckTitle)
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(SummaryDeck.presetColors, id: \.self) { colorHex in
                            Button {
                                newDeckColor = colorHex
                            } label: {
                                Circle()
                                    .fill(Color(hex: colorHex) ?? .blue)
                                    .frame(width: 44, height: 44)
                                    .overlay {
                                        if newDeckColor == colorHex {
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
                        showingNewDeckSheet = false
                        newDeckTitle = ""
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createNewDeck()
                    }
                    .fontWeight(.semibold)
                    .disabled(newDeckTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Actions

    private func createNewDeck() {
        let deck = SummaryDeck(
            title: newDeckTitle.trimmingCharacters(in: .whitespaces),
            colorHex: newDeckColor
        )

        modelContext.insert(deck)

        do {
            try modelContext.save()
            selectedDeck = deck
            showingNewDeckSheet = false
            newDeckTitle = ""
            newDeckColor = SummaryDeck.randomColor
        } catch {
            print("[CardPreviewSheet] Failed to create deck: \(error)")
        }
    }
}

// MARK: - Preview

#Preview {
    CardPreviewSheet(
        card: SummaryCard(
            title: "Chapter 3: Swift Functions",
            summary: "This chapter covers the fundamentals of functions in Swift, including parameter labels, return types, and closures. Functions are first-class citizens in Swift.",
            keyPoints: [
                "Functions can have external and internal parameter names",
                "Return types are specified with ->",
                "Closures are anonymous functions",
                "Functions can be passed as parameters"
            ],
            sourceText: "Full source text here..."
        ),
        onSave: { _ in },
        onDiscard: {}
    )
    // Seeded so the deck picker has decks to offer.
    .modelContainer(PreviewSamples.container)
}

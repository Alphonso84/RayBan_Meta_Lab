//
//  BookDeckSheet.swift
//  Smart Glasses
//
//  Confirms a deck created from a scanned book barcode.
//
//  The title is always editable and never auto-committed: a barcode gives the
//  digits reliably, but turning an ISBN into a title depends on the model
//  recognizing that specific number. A silently mislabelled deck is worse than
//  one the user names themselves.
//

import SwiftUI

struct BookDeckSheet: View {

    let book: ScannedBookCode
    let onCreate: (String) -> Void
    let onCancel: () -> Void

    @State private var title: String = ""

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether the title came from the model rather than from the barcode digits.
    private var titleWasRecognized: Bool {
        !book.recognizedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Deck title", text: $title)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Deck")
                } footer: {
                    if titleWasRecognized {
                        Text("This title came from the scanned ISBN and may be wrong — check it before creating the deck.")
                    } else {
                        Text("The barcode did not match a book the model recognizes, so give this deck a name.")
                    }
                }

                Section("Scanned Code") {
                    LabeledContent(book.isISBN ? "ISBN" : "Barcode") {
                        Text(book.code)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
            .navigationTitle("New Book Deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { onCreate(trimmedTitle) }
                        .disabled(trimmedTitle.isEmpty)
                }
            }
            .onAppear {
                if title.isEmpty {
                    title = book.suggestedDeckTitle
                }
            }
        }
        .presentationDetents([.medium])
    }
}

//
//  QuizView.swift
//  Smart Glasses
//
//  Main quiz interface: generating → quiz → results
//

import SwiftUI
import SwiftData

struct QuizView: View {
    let deck: SummaryDeck

    @Environment(\.dismiss) private var dismiss
    @StateObject private var generator = QuizGenerator()
    @ObservedObject private var voiceFeedback = VoiceFeedbackManager.shared
    @AppStorage("speakSummaries") private var speakSummaries = false

    @State private var currentIndex = 0
    @State private var answers: [Int?] = []
    @State private var selectedAnswer: Int? = nil
    @State private var showingFeedback = false
    @State private var quizStartedAt = Date()
    @State private var quizResult: QuizResult? = nil

    private var sortedCards: [SummaryCard] { deck.sortedCards }

    var body: some View {
        NavigationStack {
            Group {
                switch generator.state {
                case .idle, .generating:
                    generatingView
                case .complete:
                    if let result = quizResult {
                        resultsView(result)
                    } else {
                        quizQuestionView
                    }
                case .error(let message):
                    errorView(message)
                }
            }
            .navigationTitle("Quiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        voiceFeedback.stopSpeaking()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            startQuiz()
        }
        .onDisappear {
            voiceFeedback.stopSpeaking()
        }
    }

    // MARK: - Generating View

    private var generatingView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(deck.color)
                .symbolEffect(.pulse, isActive: generator.state == .generating)

            Text("Generating questions...")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Creating quiz from \(sortedCards.count) cards")
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

    // MARK: - Quiz Question View

    private var quizQuestionView: some View {
        let questions = generator.questions
        guard currentIndex < questions.count else {
            return AnyView(EmptyView())
        }

        let question = questions[currentIndex]

        return AnyView(
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 20) {
                        // Progress
                        HStack {
                            Text("Question \(currentIndex + 1) / \(questions.count)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text("From: \(question.sourceCardTitle)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        // Progress bar
                        ProgressView(value: Double(currentIndex + 1), total: Double(questions.count))
                            .tint(deck.color)

                        // Question text
                        Text(question.question)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)

                        // Options
                        VStack(spacing: 12) {
                            ForEach(0..<question.options.count, id: \.self) { index in
                                optionButton(
                                    index: index,
                                    text: question.options[index],
                                    isCorrect: index == question.correctAnswerIndex,
                                    question: question
                                )
                            }
                        }
                    }
                    .padding()
                }
            }
        )
    }

    private func optionButton(index: Int, text: String, isCorrect: Bool, question: QuizQuestion) -> some View {
        let isSelected = selectedAnswer == index
        let showResult = showingFeedback

        var backgroundColor: Color {
            if showResult && isCorrect {
                return .green.opacity(0.2)
            } else if showResult && isSelected && !isCorrect {
                return .red.opacity(0.2)
            } else if isSelected {
                return deck.color.opacity(0.15)
            }
            return Color(.secondarySystemGroupedBackground)
        }

        var borderColor: Color {
            if showResult && isCorrect {
                return .green
            } else if showResult && isSelected && !isCorrect {
                return .red
            } else if isSelected {
                return deck.color
            }
            return Color.clear
        }

        let optionLabel = ["A", "B", "C", "D"][index]

        return Button {
            guard !showingFeedback else { return }
            selectAnswer(index, for: question)
        } label: {
            HStack(spacing: 12) {
                Text(optionLabel)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(showResult && isCorrect ? .green : (showResult && isSelected ? .red : deck.color))
                    .frame(width: 28)

                Text(text)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)

                Spacer()

                if showResult && isCorrect {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if showResult && isSelected && !isCorrect {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .disabled(showingFeedback)
    }

    // MARK: - Results View

    private func resultsView(_ result: QuizResult) -> some View {
        QuizResultsView(
            result: result,
            deckColor: deck.color,
            onTryAgain: {
                retryQuiz()
            },
            onDone: {
                dismiss()
            }
        )
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Couldn't Generate Quiz")
                .font(.title3)
                .fontWeight(.semibold)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                retryQuiz()
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

    private func startQuiz() {
        quizResult = nil
        currentIndex = 0
        answers = []
        selectedAnswer = nil
        showingFeedback = false
        quizStartedAt = Date()

        let questionCount = min(10, sortedCards.count * 3)
        Task {
            await generator.generateQuestions(from: sortedCards, count: questionCount)
            answers = Array(repeating: nil, count: generator.questions.count)

            // Speak first question if enabled
            if speakSummaries, let first = generator.questions.first {
                voiceFeedback.speakSummary(first.question)
            }
        }
    }

    private func selectAnswer(_ index: Int, for question: QuizQuestion) {
        selectedAnswer = index
        answers[currentIndex] = index
        showingFeedback = true

        // Haptic feedback
        let feedbackGenerator = UINotificationFeedbackGenerator()
        if index == question.correctAnswerIndex {
            feedbackGenerator.notificationOccurred(.success)
        } else {
            feedbackGenerator.notificationOccurred(.error)
        }

        // Auto-advance after delay
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000) // 1.2s

            await MainActor.run {
                showingFeedback = false
                selectedAnswer = nil

                if currentIndex < generator.questions.count - 1 {
                    withAnimation {
                        currentIndex += 1
                    }

                    // Speak next question if enabled
                    if speakSummaries {
                        let nextQuestion = generator.questions[currentIndex]
                        voiceFeedback.speakSummary(nextQuestion.question)
                    }
                } else {
                    // Quiz complete
                    quizResult = QuizResult(
                        questions: generator.questions,
                        answers: answers,
                        startedAt: quizStartedAt,
                        completedAt: Date()
                    )
                }
            }
        }
    }

    private func retryQuiz() {
        generator.reset()
        startQuiz()
    }
}

/// Shows the generating state.
///
/// `startQuiz()` always calls the language model — questions are not cached the
/// way flashcards are — and a preview cannot run it, so this settles on the
/// generating or error screen rather than the question UI.
#Preview {
    // No `.modelContainer` needed: the deck is passed in directly and the
    // view reads nothing else from the store.
    QuizView(deck: PreviewSamples.deck)
}

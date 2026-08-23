//
//  QuizResultsView.swift
//  Smart Glasses
//
//  Displays quiz results with score, missed questions, and retry option
//

import SwiftUI

struct QuizResultsView: View {
    let result: QuizResult
    let deckColor: Color
    let onTryAgain: () -> Void
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Score ring
                scoreRing
                    .padding(.top, 20)

                // Score text
                VStack(spacing: 4) {
                    Text("\(result.score) / \(result.total) correct")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(scoreMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Missed questions
                if !missedQuestions.isEmpty {
                    missedSection
                }

                // Action buttons
                HStack(spacing: 16) {
                    Button {
                        onTryAgain()
                    } label: {
                        Label("Try Again", systemImage: "arrow.clockwise")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(deckColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        onDone()
                    } label: {
                        Text("Done")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.top, 8)
            }
            .padding()
        }
    }

    // MARK: - Score Ring

    private var scoreRing: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 12)
                .frame(width: 120, height: 120)

            Circle()
                .trim(from: 0, to: result.total > 0 ? CGFloat(result.score) / CGFloat(result.total) : 0)
                .stroke(deckColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .frame(width: 120, height: 120)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.8), value: result.score)

            Text("\(Int(result.percentage))%")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(deckColor)
        }
    }

    // MARK: - Missed Questions

    private var missedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Missed Questions")
                .font(.headline)
                .foregroundStyle(.secondary)

            ForEach(missedQuestions, id: \.question.id) { missed in
                VStack(alignment: .leading, spacing: 8) {
                    Text(missed.question.question)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if let userAnswer = missed.userAnswer, userAnswer < missed.question.options.count {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                            Text("Your answer: \(missed.question.options[userAnswer])")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text("Correct: \(missed.question.options[missed.question.correctAnswerIndex])")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }
        }
    }

    // MARK: - Helpers

    private var scoreMessage: String {
        let pct = result.percentage
        if pct >= 90 { return "Excellent work!" }
        if pct >= 70 { return "Good job! Keep studying." }
        if pct >= 50 { return "Not bad, review the missed ones." }
        return "Keep studying, you'll improve!"
    }

    private struct MissedQuestion {
        let question: QuizQuestion
        let userAnswer: Int?
    }

    private var missedQuestions: [MissedQuestion] {
        zip(result.questions, result.answers).compactMap { question, answer in
            if answer != question.correctAnswerIndex {
                return MissedQuestion(question: question, userAnswer: answer)
            }
            return nil
        }
    }
}

#Preview("Perfect score") {
    QuizResultsView(
        result: PreviewSamples.quizResult(correct: PreviewSamples.quizQuestions.count),
        deckColor: .green,
        onTryAgain: {},
        onDone: {}
    )
}

#Preview("Partial score") {
    QuizResultsView(
        result: PreviewSamples.quizResult(correct: 2),
        deckColor: .blue,
        onTryAgain: {},
        onDone: {}
    )
}

#Preview("All wrong") {
    QuizResultsView(
        result: PreviewSamples.quizResult(correct: 0),
        deckColor: .purple,
        onTryAgain: {},
        onDone: {}
    )
}

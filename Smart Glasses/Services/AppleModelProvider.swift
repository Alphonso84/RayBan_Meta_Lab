//
//  AppleModelProvider.swift
//  Smart Glasses
//
//  Central factory for Apple-backed language model sessions, and the single
//  place that knows about Private Cloud Compute.
//
//  Every `if #available(iOS 27.0, *)` for PCC lives here so the generators read
//  identically whether they end up on-device or in the cloud.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Tiers and Providers

/// Which Apple model should back a session.
enum AppleModelTier {
    /// `SystemLanguageModel` — runs entirely on-device, no network.
    case onDevice

    /// `PrivateCloudComputeLanguageModel` — larger context and reasoning,
    /// no API keys or billing, but requires a network round trip.
    case privateCloudCompute
}

/// The values stored in `@AppStorage("selectedProvider")`.
///
/// Raw values are the existing persisted strings — `"apple"` predates the other
/// two and must not be renamed or old installs would silently change provider.
enum SummarizationProvider: String {
    case onDevice = "apple"
    case privateCloudCompute = "pcc"
    case openAI = "openai"

    init(storedValue: String) {
        self = SummarizationProvider(rawValue: storedValue) ?? .onDevice
    }
}

#if canImport(FoundationModels)

/// Holds the shared PCC model.
enum PrivateCloudCompute {
    static let model = PrivateCloudComputeLanguageModel()
}

#endif

// MARK: - Provider

enum AppleModelProvider {

    // MARK: Availability

    /// Whether PCC can actually be used right now.
    ///
    /// Note this is a *device eligibility* check, not a connectivity check —
    /// there is no offline signal here, so a network failure still has to be
    /// caught at call time. See `isRecoverablePCCError(_:)`.
    static var isPCCAvailable: Bool {
        #if canImport(FoundationModels)
        return PrivateCloudCompute.model.isAvailable
        #else
        return false
        #endif
    }

    /// Human-readable reason PCC cannot be used, or `nil` when it is available.
    static var pccUnavailableMessage: String? {
        #if canImport(FoundationModels)
        switch PrivateCloudCompute.model.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "This device is not eligible for Private Cloud Compute."
            case .systemNotReady:
                return "Private Cloud Compute is not ready yet. Try again shortly."
            @unknown default:
                return "Private Cloud Compute is unavailable."
            }
        @unknown default:
            return "Private Cloud Compute is unavailable."
        }
        #else
        return "Private Cloud Compute requires iOS 27."
        #endif
    }

    /// Short description of remaining PCC quota, for display in Settings.
    /// `nil` when usage is comfortably below the limit.
    static var pccQuotaMessage: String? {
        #if canImport(FoundationModels)
        let usage = PrivateCloudCompute.model.quotaUsage
        switch usage.status {
        case .belowLimit(let belowLimit):
            guard belowLimit.isApproachingLimit else { return nil }
            return "You are approaching your Private Cloud Compute limit."
        case .limitReached:
            if let resetDate = usage.resetDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                return "Private Cloud Compute limit reached. Resets \(formatter.string(from: resetDate))."
            }
            return "Private Cloud Compute limit reached. Summaries will run on-device."
        @unknown default:
            return nil
        }
        #else
        return nil
        #endif
    }

    /// Offer the system's quota-increase flow, when one is available.
    static func showQuotaIncreaseSuggestion() {
        #if canImport(FoundationModels)
        PrivateCloudCompute.model.quotaUsage.limitIncreaseSuggestion?.show()
        #endif
    }

    // MARK: Tier Selection

    /// The tier to use for text-only work under the given stored provider.
    ///
    /// Falls back to on-device whenever PCC is selected but unusable, so callers
    /// never have to special-case an ineligible device.
    static func textTier(for storedProvider: String) -> AppleModelTier {
        switch SummarizationProvider(storedValue: storedProvider) {
        case .privateCloudCompute:
            return isPCCAvailable ? .privateCloudCompute : .onDevice
        case .onDevice, .openAI:
            return .onDevice
        }
    }

    // MARK: Sessions

    #if canImport(FoundationModels)

    /// Build a session on the requested tier.
    ///
    /// Returns `nil` only when the on-device model itself is unavailable, since
    /// a PCC request degrades to on-device rather than failing.
    static func makeSession(tier: AppleModelTier, instructions: String) -> LanguageModelSession? {
        if tier == .privateCloudCompute, isPCCAvailable {
            return LanguageModelSession(
                model: PrivateCloudCompute.model,
                instructions: instructions
            )
        }

        guard case .available = SystemLanguageModel.default.availability else { return nil }
        return LanguageModelSession(instructions: instructions)
    }

    // MARK: Requests

    /// Non-streaming structured request, optionally asking the model to reason.
    ///
    /// A model without the `.reasoning` capability ignores the request, so
    /// callers can pass it unconditionally.
    static func respond<Content: Generable>(
        session: LanguageModelSession,
        to prompt: String,
        generating type: Content.Type,
        reasoning: Bool = false
    ) async throws -> Content {
        guard reasoning else {
            return try await session.respond(to: prompt, generating: type).content
        }

        return try await session.respond(
            to: prompt,
            generating: type,
            contextOptions: ContextOptions(reasoningLevel: .deep)
        ).content
    }

    /// Streaming structured request, optionally asking the model to reason.
    static func streamResponse<Content: Generable>(
        session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        reasoning: Bool = false
    ) -> LanguageModelSession.ResponseStream<Content> {
        guard reasoning else {
            return session.streamResponse(to: prompt, generating: type)
        }

        return session.streamResponse(
            to: prompt,
            generating: type,
            contextOptions: ContextOptions(reasoningLevel: .deep)
        )
    }

    #endif

    // MARK: Error Classification

    /// Whether a request failed because the content did not fit the context window.
    static func isContextSizeExceeded(_ error: Error) -> Bool {
        #if canImport(FoundationModels)
        if case .contextSizeExceeded = error as? LanguageModelError {
            return true
        }
        #endif
        return false
    }

    /// Whether a failed PCC request should be retried on-device.
    ///
    /// All three PCC failure modes are transient or account-scoped rather than
    /// content problems, so every one of them is worth retrying locally instead
    /// of surfacing an error to someone mid-scan.
    static func isRecoverablePCCError(_ error: Error) -> Bool {
        #if canImport(FoundationModels)
        guard let pccError = error as? PrivateCloudComputeLanguageModel.Error else { return false }

        switch pccError {
        case .networkFailure, .quotaLimitReached, .serviceUnavailable:
            return true
        @unknown default:
            return true
        }
        #else
        return false
        #endif
    }
}

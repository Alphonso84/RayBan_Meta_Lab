//
//  SummarizationProviderTests.swift
//  Smart GlassesTests
//
//  Covers how the chosen AI provider is named and persisted.
//
//  The scanner's progress text used to be the hardcoded string "Using
//  on-device AI", so it claimed the on-device model no matter what the user had
//  selected. These pin the mapping that replaced it.
//

import Testing
@testable import Smart_Glasses

struct SummarizationProviderTests {

    // MARK: - Persistence

    /// `"apple"` predates the other two values and is what existing installs
    /// have stored. Renaming any of these silently switches a user's provider
    /// on the next launch.
    @Test func rawValuesArePersistedAndMustNotChange() {
        #expect(SummarizationProvider.onDevice.rawValue == "apple")
        #expect(SummarizationProvider.privateCloudCompute.rawValue == "pcc")
        #expect(SummarizationProvider.openAI.rawValue == "openai")
    }

    @Test func storedValuesRoundTrip() {
        #expect(SummarizationProvider(storedValue: "apple") == .onDevice)
        #expect(SummarizationProvider(storedValue: "pcc") == .privateCloudCompute)
        #expect(SummarizationProvider(storedValue: "openai") == .openAI)
    }

    /// An unreadable setting must land somewhere that always works rather than
    /// on a provider needing an API key or a network.
    @Test func unknownStoredValueFallsBackToOnDevice() {
        #expect(SummarizationProvider(storedValue: "") == .onDevice)
        #expect(SummarizationProvider(storedValue: "gemini") == .onDevice)
    }

    // MARK: - Naming

    /// These must match the Settings picker, or progress text and the setting
    /// driving it describe the same choice with different words.
    @Test func displayNamesMatchTheSettingsPicker() {
        #expect(SummarizationProvider.onDevice.displayName == "On-Device")
        #expect(SummarizationProvider.privateCloudCompute.displayName == "Apple Cloud")
        #expect(SummarizationProvider.openAI.displayName == "OpenAI")
    }

    /// The bug this suite exists for: every provider needs its own label.
    @Test func everyProviderHasADistinctSummarizingLabel() {
        let labels = [
            SummarizationProvider.onDevice.summarizingLabel,
            SummarizationProvider.privateCloudCompute.summarizingLabel,
            SummarizationProvider.openAI.summarizingLabel
        ]

        #expect(Set(labels).count == 3)
        #expect(labels.allSatisfy { !$0.isEmpty })
    }

    @Test func onlyTheOnDeviceLabelMentionsTheDevice() {
        #expect(SummarizationProvider.onDevice.summarizingLabel == "Using on-device AI")
        #expect(!SummarizationProvider.openAI.summarizingLabel.contains("on-device"))
        #expect(!SummarizationProvider.privateCloudCompute.summarizingLabel.contains("on-device"))
    }

    /// Interpolating "Using \(displayName) AI" would read "Using OpenAI AI".
    @Test func labelsDoNotRepeatAI() {
        for label in [SummarizationProvider.openAI.summarizingLabel,
                      SummarizationProvider.privateCloudCompute.summarizingLabel] {
            #expect(!label.contains("AI AI"))
        }
    }

    // MARK: - Tier mapping

    /// A tier is what actually ran; the progress label is derived from it, so
    /// the mapping has to be exact.
    @Test func tiersMapToTheMatchingProvider() {
        #expect(AppleModelTier.onDevice.provider == .onDevice)
        #expect(AppleModelTier.privateCloudCompute.provider == .privateCloudCompute)
    }
}

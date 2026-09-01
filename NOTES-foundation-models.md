# Apple Foundation Models Framework Feasibility Note

## 1. Overview & Clarification on OS Versions

There is a critical distinction between the **Apple Intelligence user feature** and the **`FoundationModels` developer framework**:
- **Apple Intelligence (Feature)**: Arrived in iOS 18.1 / macOS Sequoia 15.1 as consumer system features (Writing Tools, Siri, Mail summaries).
- **`FoundationModels` (Developer Swift Framework)**: Introduced in **iOS 26.0+ / macOS 26.0+ / visionOS 26.0+**. It provides the native Swift API (`import FoundationModels`, `@Generable`, `@Guide`, `LanguageModelSession`, `SystemLanguageModel`) for on-device structured token generation.

> Per `SPEC.md` §9.3, runtime fallback to template phrasing is triggered whenever running on `iOS < 26` or when Apple Intelligence / on-device model availability is unavailable.

### Official Apple Documentation Links
1. **FoundationModels Framework**: [https://developer.apple.com/documentation/foundationmodels](https://developer.apple.com/documentation/foundationmodels) (Minimum OS: iOS 26.0, macOS 26.0, visionOS 26.0)
2. **`@Generable` Macro**: [https://developer.apple.com/documentation/foundationmodels/generable](https://developer.apple.com/documentation/foundationmodels/generable) (Minimum OS: iOS 26.0, macOS 26.0, visionOS 26.0)
3. **`@Guide` Macro**: [https://developer.apple.com/documentation/foundationmodels/guide](https://developer.apple.com/documentation/foundationmodels/guide) (Minimum OS: iOS 26.0, macOS 26.0, visionOS 26.0)
4. **`SystemLanguageModel`**: [https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel) (Minimum OS: iOS 26.0, macOS 26.0, visionOS 26.0)
5. **`SystemLanguageModel.Availability`**: [https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/availability](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/availability) (Minimum OS: iOS 26.0, macOS 26.0, visionOS 26.0)
6. **`SystemLanguageModel.Availability.UnavailableReason`**: [https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/availability/unavailablereason](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/availability/unavailablereason) (Minimum OS: iOS 26.0, macOS 26.0, visionOS 26.0)

---

## 2. Core Concepts & Macros

### `@Generable`
Annotates Swift `struct` or `enum` types to enforce structured outputs from the language model. When passing a `@Generable` type to a generation session, token sampling is constrained to conform strictly to the Swift type's JSON/schema definition.

- Minimum iOS: **iOS 26.0+**
- Documentation: [https://developer.apple.com/documentation/foundationmodels/generable](https://developer.apple.com/documentation/foundationmodels/generable)

### `@Guide`
Annotates properties within a `@Generable` type to supply semantic guidance, prompt context, and constraints (e.g. valid ranges, format descriptions, length targets).

- Minimum iOS: **iOS 26.0+**
- Documentation: [https://developer.apple.com/documentation/foundationmodels/guide](https://developer.apple.com/documentation/foundationmodels/guide)

```swift
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct PhrasedClaim {
    @Guide("The verbatim behavioural claim phrased in terse, direct second-person. Max 25 words.")
    var sentence: String
}
```

---

## 3. Session Construction (`LanguageModelSession`)

A `LanguageModelSession` maintains the conversational context, system instructions, and generation state.

```swift
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
func makeSession() -> LanguageModelSession {
    let instructions = """
    You phrase behavioural observations directly from data. Never add character judgements or apologies.
    """
    let model = SystemLanguageModel.default
    return LanguageModelSession(model: model, instructions: instructions)
}
```

---

## 4. Runtime Availability Check & Exact Enum Cases

Before invoking any generation API, applications **must** inspect the model's availability status.

### API Signature
```swift
SystemLanguageModel.default.availability
```

### Enumerated States & Exact Unavailable Reasons
The availability check returns `SystemLanguageModel.Availability`:
```swift
@frozen public enum Availability : Equatable, Sendable {
    case available
    case unavailable(SystemLanguageModel.Availability.UnavailableReason)
}
```

The exact enum cases of `SystemLanguageModel.Availability.UnavailableReason` (spelled exactly as in Apple's SDK):

| Enum Case | Meaning / Trigger |
| :--- | :--- |
| `.deviceNotEligible` | Device lacks required Neural Engine / memory hardware (e.g. Non-A17 Pro / non-M-series chips). |
| `.appleIntelligenceNotEnabled` | User has turned off Apple Intelligence in *Settings → Apple Intelligence & Siri*. |
| `.modelNotReady` | On-device model assets are currently downloading, preparing, or not yet provisioned in background. |

*(Note: Earlier draft notes referenced a `.restricted` case; the official SDK defines exclusively the three cases above).*

---

## 5. Device vs. Simulator Execution

### Simulator Support
- **Compilation**: Supported on iOS 26.0+ Simulator SDK (`FoundationModels.framework` and macro plugins are present).
- **Runtime Execution**: In the iOS Simulator, `SystemLanguageModel.default.availability` returns `.unavailable(.deviceNotEligible)` unless running on an Apple Silicon Mac with host Apple Intelligence enabled and supported model assets provisioned.
- **Testing Requirement**: While code compiles against the simulator SDK and unit tests can verify fallback paths, testing live generative inference requires a physical Apple Intelligence-capable device (A17 Pro or later, M1 or later).

### Hardware Requirements
- **iPhone**: iPhone 15 Pro, iPhone 15 Pro Max (A17 Pro), iPhone 16 series (A18 / A18 Pro), and newer.
- **iPad**: iPad models with M1 or later, or iPad mini with A17 Pro or later.
- **Mac**: Apple Silicon Macs with M1 or later.
- **Unsupported Devices**: Standard iPhone 15, iPhone 14 Pro, iPhone 14, and earlier (A16 Bionic or older) return `.unavailable(.deviceNotEligible)`.

---

## 6. Guarded Invocation Pattern with Spec Fallback

```swift
import Foundation
import FoundationModels

@MainActor
final class PhrasingService {
    private var session: Any? // LanguageModelSession on iOS 26+

    init() {
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                self.session = LanguageModelSession(
                    model: .default,
                    instructions: "Phrase behavioural claims plainly without adjectives of character."
                )
            }
        }
    }

    func phrase(prompt: String, fallbackText: String) async -> String {
        guard #available(iOS 26.0, *) else {
            return fallbackText
        }

        switch SystemLanguageModel.default.availability {
        case .available:
            guard let session = self.session as? LanguageModelSession else {
                return fallbackText
            }
            do {
                let response = try await session.respond(to: prompt)
                return response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return fallbackText
            }

        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady:
                return fallbackText
            @unknown default:
                return fallbackText
            }
        }
    }
}
```

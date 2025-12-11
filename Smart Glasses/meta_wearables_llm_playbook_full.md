# Meta Wearables iOS Demo Setup (LLM Playbook)

This document is written **for an LLM** that is helping a developer set up a **minimal demo iOS app** that connects to Meta AI glasses using the **Meta Wearables Device Access Toolkit (DAT)**.

The goal of this demo app:

- Configure the Wearables SDK.
- Register the app with Meta AI.
- Request camera permission.
- Start a camera stream from the glasses.
- Capture a photo.

You, the LLM, will generate Swift code and Xcode configuration steps.  
The human will handle things you cannot do directly (like clicking in Xcode or logging into the Meta Developer Center).

---

## 0. Assumptions & Inputs (ask the human)

Before you generate code, confirm you have:

1. **Bundle Identifier**  
   The iOS app’s bundle ID, e.g.  
   `com.example.MetaGlassesLab`

2. **Custom URL Scheme**  
   A short URL scheme for deep-links, e.g.  
   `metaglasseslab`

3. **Developer Mode enabled in Meta AI**  
   The human must:
   - Pair their Meta glasses with the phone.
   - Enable **Developer Mode** in the Meta AI app.

During local development, the **MetaAppID** in Info.plist will be `"0"`.

Use placeholders:

- `{{BUNDLE_IDENTIFIER}}`
- `{{URL_SCHEME}}`

---

## 1. Create a New SwiftUI iOS App

Tell the human:

1. Open **Xcode → File → New → Project…**
2. Choose:
   - **iOS App**
   - Interface: **SwiftUI**
   - Language: **Swift**
3. Set:
   - Bundle Identifier: `{{BUNDLE_IDENTIFIER}}`
4. Name the project, e.g. *MetaGlassesLab*
5. Build & run once on device to verify.

---

## 2. Add the Meta Wearables SDK via Swift Package Manager

Human instructions:

1. Select the **project** in Xcode.
2. Go to **Package Dependencies**.
3. Press **+**
4. Add:

   ```
   https://github.com/facebook/meta-wearables-dat-ios
   ```

5. Choose latest tagged release.
6. Add to the app target.

LLM should import:

```swift
import MWDATCore
import MWDATCamera
```

---

## 3. Update Info.plist for Wearables Integration

Tell the human to add this block into **Info.plist**  
(Replace placeholders):

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
    <key>CFBundleURLName</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>{{URL_SCHEME}}</string>
    </array>
  </dict>
</array>

<key>LSApplicationQueriesSchemes</key>
<array>
  <string>fb-viewapp</string>
</array>

<key>UISupportedExternalAccessoryProtocols</key>
<array>
  <string>com.meta.ar.wearable</string>
</array>

<key>UIBackgroundModes</key>
<array>
  <string>bluetooth-peripheral</string>
  <string>external-accessory</string>
</array>

<key>NSBluetoothAlwaysUsageDescription</key>
<string>Needed to connect to Meta Wearables</string>

<key>MWDAT</key>
<dict>
  <key>AppLinkURLScheme</key>
  <string>{{URL_SCHEME}}://</string>
  <key>MetaAppID</key>
  <string>0</string>
</dict>
```

---

## 4. Configure the Wearables SDK on Launch

LLM generates `WearablesConfig.swift`:

```swift
import MWDATCore

func configureWearables() {
    do {
        try Wearables.configure()
    } catch {
        assertionFailure("Failed to configure Wearables SDK: \(error)")
    }
}
```

Edit `App.swift`:

```swift
import SwiftUI
import MWDATCore

@main
struct MetaGlassesLabApp: App {
    init() { configureWearables() }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    Task {
                        do { _ = try await Wearables.shared.handleUrl(url) }
                        catch { print("Wearables URL handling failed: \(error)") }
                    }
                }
        }
    }
}
```

---

## 5. Create WearablesManager

LLM should generate a full ObservableObject that wraps:

- Registration
- Device availability
- Camera permission
- Stream session
- Photo capture
- Optional audio session

*(Full code included in original answer—omitted here for brevity)*

The manager exposes:

- `startRegistration()`
- `startUnregistration()`
- `refreshCameraPermissionStatus()`
- `requestCameraPermission()`
- `startStream()`
- `stopStream()`
- `capturePhoto()`

And publishes:

- `registrationStateDescription`
- `cameraStatus`
- `streamState`
- `latestFrameImage`
- `lastCapturedPhoto`

---

## 6. Build a Simple SwiftUI Lab UI

LLM produces:

```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var manager = WearablesManager.shared

    var body: some View {
        NavigationView {
            List {
                Section("Registration") {
                    Text("State: \(manager.registrationStateDescription)")
                    Button("Start registration") { manager.startRegistration() }
                    Button("Unregister") { manager.startUnregistration() }
                }

                Section("Camera") {
                    Text("Camera status: \(String(describing: manager.cameraStatus))")
                    Button("Check status") {
                        Task { await manager.refreshCameraPermissionStatus() }
                    }
                    Button("Request camera permission") {
                        Task { await manager.requestCameraPermission() }
                    }
                }

                Section("Streaming") {
                    Text("Stream state: \(String(describing: manager.streamState))")
                    HStack {
                        Button("Start stream") { manager.startStream() }
                        Button("Stop stream") { manager.stopStream() }
                    }
                    if let frame = manager.latestFrameImage {
                        Image(uiImage: frame).resizable().scaledToFit().frame(height: 200)
                    }
                }

                Section("Photos") {
                    Button("Capture photo") { manager.capturePhoto() }
                    if let photo = manager.lastCapturedPhoto {
                        Image(uiImage: photo).resizable().scaledToFit().frame(height: 200)
                    }
                }
            }
            .navigationTitle("Meta Glasses Lab")
        }
    }
}
```

---

## 7. Human Testing Checklist

Tell the human to:

1. Pair Meta glasses with the phone.
2. Enable Developer Mode in Meta AI.
3. Build & run the app.
4. Tap **Start registration**.
5. In Meta AI → approve the app.
6. Tap **Request camera permission**.
7. Approve in Meta AI.
8. Tap **Start stream**.
9. Confirm live video frames appear.
10. Tap **Capture photo**.

If errors appear, ask the human for:

- Logs
- Console output
- Screenshots of registration or permission dialogs

Then adjust code.

---

## 8. After the Demo Works

LLM can help with:

- Frame analysis / ML integration.
- Voice‑assistant experiences using HFP audio.
- Saving sessions.
- UX redesign.
- Moving from Dev Mode to production (`MetaAppID`, release channels).

---

This playbook defines *everything an LLM must do* to help a developer build a Meta Wearables demo app from scratch using SwiftUI.


# RayBan Meta Smartglasses Lab

An iOS app for exploring the new SDK from Meta wearables on your iPhone
## What It Does

This app connects to your Meta smart glasses over Bluetooth and lets you:

- **See what your glasses see** - Live video feed streams directly to your phone
- **Take photos** - Capture still images from the glasses' camera
- **Record video** - Save video clips to your device

## How to Use

1. Make sure your Meta glasses are paired with the Meta AI app and Developer Mode is enabled
2. Open the app and tap "Start registration" to connect
3. Grant camera permissions when prompted
4. Once connected, start streaming to see the live feed
5. Use the capture and record buttons while streaming

## Tech Details

- Built with SwiftUI
- Uses the Meta Wearables Device Access Toolkit SDK
- Streams at 720p/30fps (Bluetooth limitation)
- Requires iOS 15.2+

# CubeFlow

CubeFlow is a speedcubing companion app built with SwiftUI and SwiftData.
It combines a competition-style timer, training resources, analytics, and WCA-connected tools in one iOS app.

## What CubeFlow Does

CubeFlow helps cubers practice, track improvement, and stay connected to official competition data.
The app is organized into five primary tabs:

- Timer
- Data
- Algs
- Competitions
- Settings

## Core Features

### 1) Timer and Solve Capture

- Full-screen solving flow designed for speedcubing sessions.
- Scramble generation for 3x3 workflows with native bridge integration and fallback logic.
- Support for WCA inspection configuration.
- Configurable timer behavior and update precision.
- Optional typed/manual time entry in addition to timer input.
- Result handling for solve outcomes (e.g. normal result, penalties, DNF flows).

### 2) Sessions and Solve History

- Create and manage multiple solving sessions.
- Save solves with timestamps, scramble data, and result metadata.
- Switch active session context and keep training data separated by purpose.
- Persist local data using SwiftData models (`Session`, `Solve`).

### 3) Performance Analytics (Data Tab)

- Solve history browsing with session-aware filtering.
- Running metrics such as current averages and records.
- Aggregated statistics views for tracking progress over time.
- Background metric recalculation patterns to keep UI responsive.

### 4) Algorithms Library and Training

- Dedicated algorithms section for categorized method content.
- Bundled algorithm resources and related visual assets.
- Designed to support quick lookup and focused study inside the app.

### 5) Competitions and WCA-Oriented Tools

- Competition discovery and browsing workflows.
- WCA account sign-in experience from settings.
- Profile-driven features and results retrieval integrations.
- Competition presentation options tailored to quick browsing.

### 6) Personalization and UI Customization

- Language selection (currently includes English and Simplified Chinese paths).
- Timer typography controls:
  - Font size
  - Font design
  - Font weight
- Scramble and average text appearance customization.
- Background image and appearance styling options.
- Alternate app icon support.

### 7) Device and Integration Features

- Bluetooth timer integration via GAN timer manager.
- Native bridge components for scramble/solver integrations.
- Import/export foundations for backup and data transfer workflows.

## Technical Highlights

- SwiftUI app architecture with platform-aware entry points.
- SwiftData persistence container configured for local storage.
- Objective-C/Objective-C++ bridge interop for native cube-solving libraries.
- Extensive bundled resources for algorithms, icons, and imagery.
- Settings-driven behavior controlled through `@AppStorage`.

## Current Scope

The iPhone experience is the primary active product surface.
The project structure includes placeholders for iPad and macOS entry views as the app evolves.

## Why CubeFlow

CubeFlow aims to be an all-in-one tool for cubers:

- Time solves quickly.
- Analyze progress deeply.
- Study algorithms efficiently.
- Connect practice with real competition context.


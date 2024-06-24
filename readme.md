# IVAO ATC Tracker

## Description
IVAO ATC Tracker is a SwiftUI-based iOS application designed to track and display Air Traffic Controller (ATC) information from the IVAO (International Virtual Aviation Organisation) network. This app provides real-time data about active ATCs, their positions, and related flight information.

## Features
- Real-time ATC tracking
- Inbound and Outbound traffic count for services
- Updated ATIS Data
- Detailed ATC information display
- Interactive map view showing ATC positions and coverage areas
- Search functionality for finding specific ATCs
- Pilot tracking and display on the map
- Responsive design for various iOS devices (iPhone and iPad)
- Automatic data refresh

## Requirements
- iOS 15.0+
- iPadOS 15.0+
- macOS 12.0+ (Monterey)
- Xcode 13.0+
- Swift 5.5+

## Installation
1. Clone the repository:
   git clone https://github.com/yourusername/ivao-atc-tracker.git
2. Open the project in Xcode:
   cd ivao-atc-tracker
   open IVAO_ATC_Tracker.xcodeproj
3. Build and run the project in Xcode.

## Usage
- Upon launching the app, you'll see a list of active ATCs.
- Use the search bar to find specific ATCs by callsign.
- Tap on an ATC in the list to view detailed information.
- On iPad or larger iPhone models in landscape, you'll see a split view with the ATC list on the left and a map on the right.
- The map displays ATC positions, their coverage areas, and active pilots.
- The app automatically refreshes data every 15 seconds.

## Architecture
The app follows the MVVM (Model-View-ViewModel) architecture:
- Models: `Atc`, `Pilot`, `WelcomeElement`, etc.
- Views: `ContentView`, `ATCDetailView`, `ATCMapView`, etc.
- ViewModel: `ATCViewModel`

## API
The app uses the IVAO API to fetch real-time data. API endpoints used:
- https://api.ivao.aero/v2/tracker/whazzup
- https://api.ivao.aero/v2/tracker/now/atc/summary

## Contributing
Contributions to the IVAO ATC Tracker are welcome. Please feel free to submit a Pull Request.

## License
MIT License with Attribution Requirement
Copyright (c) 2024 Koray Birand

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

1. The above copyright notice and this permission notice shall be included in all
   copies or substantial portions of the Software.

2. Attribution Requirement: Any use of the Software must include prominent
   attribution to the original author(s) or organization. This attribution
   must be visible within the application or, in the case of derived works,
   in the documentation and/or other materials provided with the distribution.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Acknowledgements
- IVAO for providing the API and data

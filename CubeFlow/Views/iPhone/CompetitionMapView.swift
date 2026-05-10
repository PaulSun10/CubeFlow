import SwiftUI
import MapKit
import CoreLocation
import WeatherKit
import Combine

#if os(iOS)
private struct CompetitionMapDisplayItem: Identifiable {
    enum Kind {
        case competition(String)
        case cluster([CompetitionSummary])
    }

    let id: String
    let title: String
    let coordinate: CLLocationCoordinate2D
    let kind: Kind
}

@available(iOS 17.0, *)
struct CompetitionMapView: View {
    let query: CompetitionQuery
    let appLanguage: String

    @AppStorage("competition_map_mode") private var storedMapModeRawValue: String = CompetitionMapMode.satellite.rawValue
    @AppStorage("competition_map_look") private var storedMapLookRawValue: String = CompetitionMapLook.globe.rawValue
    @State private var competitions: [CompetitionSummary] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var selectedCompetitionID: String?
    @State private var selectedClusterCompetitions: [CompetitionSummary] = []
    @State private var selectedMapItemID: String?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var currentMapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 22.3193, longitude: 114.1694),
        span: MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 8)
    )
    @State private var hasPositionedCamera = false
    @State private var isFollowingUserLocation = false
    @State private var shouldRefocusToUserLocation = false
    @StateObject private var locationManager = CompetitionLocationManager()
    @State private var weatherSnapshot: CompetitionWeatherSnapshot?
    @State private var isLoadingWeather = false
    @State private var lastWeatherLocation: CLLocation?
    @State private var currentCityName: String?
    @State private var isResolvingCity = false
    @State private var lastResolvedCityLocation: CLLocation?
    @State private var selectedCardHeight: CGFloat = 0
    @State private var showsRefreshProgress = false
    @State private var expectedCompetitionCount: Int?
    @State private var selectedCompetitionForDetail: CompetitionSummary?

    private var mappableCompetitions: [CompetitionSummary] {
        competitions.filter { $0.latitude != nil && $0.longitude != nil }
    }

    private var selectedCompetition: CompetitionSummary? {
        competitions.first { $0.id == selectedCompetitionID }
    }

    private var mapModeSelection: CompetitionMapMode {
        get { CompetitionMapMode(rawValue: storedMapModeRawValue) ?? .satellite }
        nonmutating set { storedMapModeRawValue = newValue.rawValue }
    }

    private var mapLookSelection: CompetitionMapLook {
        get { CompetitionMapLook(rawValue: storedMapLookRawValue) ?? .globe }
        nonmutating set { storedMapLookRawValue = newValue.rawValue }
    }

    private var mapDisplayItems: [CompetitionMapDisplayItem] {
        clusteredMapDisplayItems(from: mappableCompetitions, in: currentMapRegion)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $cameraPosition, selection: $selectedMapItemID) {
                UserAnnotation()

                ForEach(mapDisplayItems) { item in
                    Annotation(
                        item.title,
                        coordinate: item.coordinate,
                        anchor: .bottom
                    ) {
                        mapAnnotationView(for: item)
                    }
                    .tag(item.id)
                }
            }
            .mapStyle(mapModeSelection.mapStyle(look: mapLookSelection))
            .ignoresSafeArea(edges: .bottom)
            .onMapCameraChange(frequency: .onEnd) { context in
                currentMapRegion = context.region
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    withAnimation(.snappy(duration: 0.28)) {
                        selectedCompetitionID = nil
                        selectedClusterCompetitions = []
                        selectedMapItemID = nil
                    }
                }
            )
            .overlay(alignment: .center) {
                if let errorMessage, competitions.isEmpty {
                    mapErrorOverlay(message: errorMessage)
                } else if mappableCompetitions.isEmpty, !isLoading {
                    mapEmptyOverlay
                }
            }
            .overlay(alignment: .bottom) {
                mapBottomOverlay
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                    .animation(.snappy(duration: 0.28), value: selectedCompetition != nil)
                    .animation(.snappy(duration: 0.28), value: selectedCardHeight)
            }
        }
        .navigationTitle(Text(localizedCompetitionStringInView(key: "competitions.map_title", languageCode: appLanguage)))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedCompetitionForDetail) { competition in
            CompetitionDetailView(
                competition: competition,
                appLanguage: appLanguage
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                mapRefreshToolbarControl
            }
        }
        .task {
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestWhenInUseAuthorization()
            }
            await requestLocationIfAuthorized()
            await loadMapCompetitions()
            if let currentLocation = locationManager.currentLocation {
                async let weatherLoad: Void = loadWeatherIfNeeded(for: currentLocation)
                async let cityLoad: Void = loadCityIfNeeded(for: currentLocation)
                _ = await (weatherLoad, cityLoad)
            }
        }
        .onChange(of: locationManager.authorizationStatus) { newValue in
            if newValue == .authorizedAlways || newValue == .authorizedWhenInUse {
                locationManager.requestCurrentLocation()
                if isFollowingUserLocation {
                    focusOnUserLocation()
                }
            }
        }
        .onChange(of: locationManager.currentLocation) { newLocation in
            guard let newLocation else { return }
            if shouldRefocusToUserLocation {
                focusOnUserLocation(using: newLocation)
                shouldRefocusToUserLocation = false
            }
            Task {
                async let weatherLoad: Void = loadWeatherIfNeeded(for: newLocation)
                async let cityLoad: Void = loadCityIfNeeded(for: newLocation)
                _ = await (weatherLoad, cityLoad)
            }
        }
        .onChange(of: cameraPosition.positionedByUser) { positionedByUser in
            if positionedByUser {
                isFollowingUserLocation = false
                shouldRefocusToUserLocation = false
            }
        }
        .onChange(of: selectedMapItemID) { newValue in
            guard let newValue,
                  let item = mapDisplayItems.first(where: { $0.id == newValue }) else {
                return
            }

            switch item.kind {
            case .competition(let competitionID):
                selectedClusterCompetitions = []
                selectedCompetitionID = competitionID
            case .cluster(let competitions):
                selectedCompetitionID = nil
                if shouldShowClusterCards(for: competitions) {
                    selectedClusterCompetitions = competitions
                } else {
                    selectedClusterCompetitions = []
                    zoomToCluster(competitions)
                }
                Task { @MainActor in
                    selectedMapItemID = nil
                }
            }
        }
        .onPreferenceChange(CompetitionMapCardHeightPreferenceKey.self) { height in
            selectedCardHeight = height
        }
    }

    private var bottomControlsSpacing: CGFloat {
        selectedCompetition == nil && selectedClusterCompetitions.isEmpty ? 0 : 12
    }

    @ViewBuilder
    private func mapAnnotationView(for item: CompetitionMapDisplayItem) -> some View {
        switch item.kind {
        case .competition(let competitionID):
            Image(systemName: "mappin")
                .font(.system(size: selectedCompetitionID == competitionID ? 26 : 22, weight: .semibold))
                .foregroundStyle(selectedCompetitionID == competitionID ? .red : .blue)
                .shadow(color: .black.opacity(0.14), radius: 3, y: 1)
                .contentShape(Rectangle())
        case .cluster:
            Image(systemName: "mappin")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.blue)
                .shadow(color: .black.opacity(0.14), radius: 3, y: 1)
            .contentShape(Rectangle())
        }
    }

    private func clusteredMapDisplayItems(
        from competitions: [CompetitionSummary],
        in region: MKCoordinateRegion
    ) -> [CompetitionMapDisplayItem] {
        let latitudeThreshold = max(region.span.latitudeDelta * 0.04, 0.0012)
        let longitudeThreshold = max(region.span.longitudeDelta * 0.04, 0.0012)
        var remaining = competitions
        var items: [CompetitionMapDisplayItem] = []

        while let seed = remaining.first {
            remaining.removeFirst()

            let nearby = remaining.filter { candidate in
                guard let seedLatitude = seed.latitude,
                      let seedLongitude = seed.longitude,
                      let candidateLatitude = candidate.latitude,
                      let candidateLongitude = candidate.longitude else {
                    return false
                }

                return abs(seedLatitude - candidateLatitude) <= latitudeThreshold
                    && abs(seedLongitude - candidateLongitude) <= longitudeThreshold
            }

            let nearbyIDs = Set(nearby.map(\.id))
            remaining.removeAll { nearbyIDs.contains($0.id) }

            let group = [seed] + nearby

            if group.count == 1,
               let competition = group.first,
               let latitude = competition.latitude,
               let longitude = competition.longitude {
                items.append(
                    CompetitionMapDisplayItem(
                        id: competition.id,
                        title: competition.name,
                        coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                        kind: .competition(competition.id)
                    )
                )
            } else {
                let averagedLatitude = group.compactMap(\.latitude).reduce(0, +) / Double(group.count)
                let averagedLongitude = group.compactMap(\.longitude).reduce(0, +) / Double(group.count)
                let combinedTitle = group.map(\.name).joined(separator: " & ")
                items.append(
                    CompetitionMapDisplayItem(
                        id: "cluster:" + group.map(\.id).sorted().joined(separator: ","),
                        title: combinedTitle,
                        coordinate: CLLocationCoordinate2D(latitude: averagedLatitude, longitude: averagedLongitude),
                        kind: .cluster(group)
                    )
                )
            }
        }

        return items
    }

    private func zoomToCluster(_ competitions: [CompetitionSummary]) {
        let coordinates = competitions.compactMap { competition -> CLLocationCoordinate2D? in
            guard let latitude = competition.latitude,
                  let longitude = competition.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        guard !coordinates.isEmpty else { return }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)

        guard let minLatitude = latitudes.min(),
              let maxLatitude = latitudes.max(),
              let minLongitude = longitudes.min(),
              let maxLongitude = longitudes.max() else {
            return
        }

        let rawLatitudeDelta = maxLatitude - minLatitude
        let rawLongitudeDelta = maxLongitude - minLongitude

        let paddedLatitudeDelta = max(rawLatitudeDelta * 1.7, 0.0045)
        let paddedLongitudeDelta = max(rawLongitudeDelta * 1.7, 0.0045)

        let center = CLLocationCoordinate2D(
            latitude: ((minLatitude + maxLatitude) / 2) - (paddedLatitudeDelta * 0.10),
            longitude: (minLongitude + maxLongitude) / 2
        )

        let span = MKCoordinateSpan(
            latitudeDelta: paddedLatitudeDelta,
            longitudeDelta: paddedLongitudeDelta
        )

        withAnimation(.snappy(duration: 0.3)) {
            cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
        }
    }

    private var mapBottomOverlay: some View {
        VStack(spacing: bottomControlsSpacing) {
            HStack(alignment: .bottom) {
                mapBottomLeadingControls
                Spacer(minLength: 16)
                mapControls
            }

            if !selectedClusterCompetitions.isEmpty {
                VStack(spacing: 10) {
                    ForEach(selectedClusterCompetitions, id: \.id) { competition in
                        mapCompetitionCard(competition)
                    }
                }
                .measureHeight { height in
                    selectedCardHeight = height
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let selectedCompetition {
                mapCompetitionCard(selectedCompetition)
                    .measureHeight { height in
                        selectedCardHeight = height
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func shouldShowClusterCards(for competitions: [CompetitionSummary]) -> Bool {
        guard competitions.count > 1 else { return false }
        let normalizedAddresses = Set(
            competitions.map { competition in
                competition.venueLine.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        )
        return normalizedAddresses.count == 1 && !(normalizedAddresses.first?.isEmpty ?? true)
    }

    private var mapBottomLeadingControls: some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    await refreshWeather()
                }
            } label: {
                Group {
                    if isLoadingWeather {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.9)
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: weatherSnapshot?.symbolName ?? "cloud.sun.fill")
                                .font(.system(size: 16, weight: .semibold))
                            if let weatherSnapshot {
                                Text(weatherSnapshot.temperatureText)
                                    .font(.system(size: 13, weight: .semibold))
                            }
                        }
                    }
                }
                .frame(minWidth: 40, minHeight: 40)
                .padding(.horizontal, weatherSnapshot == nil ? 0 : 12)
            }
            .buttonStyle(.plain)
            .modifier(MapAccessoryGlassModifier(shape: weatherSnapshot == nil ? .circle : .capsule))

            if let currentCityName {
                HStack(spacing: 8) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text(currentCityName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .modifier(MapAccessoryGlassModifier(shape: .capsule))
            }

            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .semibold))
                Text(mapInfoDateText)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .modifier(MapAccessoryGlassModifier(shape: .capsule))
        }
    }

    private var mapRefreshControl: some View {
        Button {
            withAnimation(.snappy(duration: 0.24)) {
                showsRefreshProgress = true
            }
            Task {
                await loadMapCompetitions()
                try? await Task.sleep(for: .seconds(1.2))
                await MainActor.run {
                    withAnimation(.snappy(duration: 0.24)) {
                        showsRefreshProgress = false
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Group {
                    if isLoading || isLoadingMore {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.9)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }

                if showsRefreshProgress || isLoading || isLoadingMore {
                    Text(refreshProgressText)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .foregroundStyle(.primary)
            .frame(minHeight: 40)
            .padding(.horizontal, showsRefreshProgress || isLoading || isLoadingMore ? 16 : 0)
            .frame(width: showsRefreshProgress || isLoading || isLoadingMore ? nil : 40)
        }
        .buttonStyle(.plain)
        .disabled(isLoading || isLoadingMore)
        .modifier(MapAccessoryGlassModifier(shape: showsRefreshProgress || isLoading || isLoadingMore ? .capsule : .circle))
    }

    private var mapRefreshToolbarControl: some View {
        Button {
            withAnimation(.snappy(duration: 0.24)) {
                showsRefreshProgress = true
            }
            Task {
                await loadMapCompetitions()
                try? await Task.sleep(for: .seconds(1.2))
                await MainActor.run {
                    withAnimation(.snappy(duration: 0.24)) {
                        showsRefreshProgress = false
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Group {
                    if isLoading || isLoadingMore {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }

                if showsRefreshProgress || isLoading || isLoadingMore {
                    Text(refreshProgressText)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .opacity(showsRefreshProgress || isLoading || isLoadingMore ? 1 : 0)
                        .scaleEffect(showsRefreshProgress || isLoading || isLoadingMore ? 1 : 0.92, anchor: .trailing)
                }
            }
            .padding(.horizontal, showsRefreshProgress || isLoading || isLoadingMore ? 10 : 0)
            .animation(.snappy(duration: 0.22), value: showsRefreshProgress || isLoading || isLoadingMore)
            .animation(.snappy(duration: 0.22), value: refreshProgressText)
        }
        .buttonStyle(.plain)
        .disabled(isLoading || isLoadingMore)
    }

    private var refreshProgressText: String {
        let denominator = max(expectedCompetitionCount ?? competitions.count, competitions.count)

        if isLoading || isLoadingMore {
            return String(
                format: localizedCompetitionStringInView(key: "competition.refresh_progress.loaded_format", languageCode: appLanguage),
                competitions.count,
                denominator
            )
        }

        return String(
            format: localizedCompetitionStringInView(key: "competition.refresh_progress.refreshed_format", languageCode: appLanguage),
            competitions.count,
            denominator
        )
    }

    private var mapControls: some View {
        VStack(spacing: 0) {
            mapStyleButton
            locationButton
        }
        .fixedSize()
        .padding(2)
        .modifier(MapAccessoryGlassModifier(shape: .capsule))
    }

    private var isExperimentalExploreGlobe: Bool {
        mapModeSelection == .explore && mapLookSelection == .globe
    }

    private var mapStyleButton: some View {
        Menu {
            Section(localizedCompetitionStringInView(key: "competitions.map_mode.title", languageCode: appLanguage)) {
                Button {
                    mapModeSelection = .explore
                } label: {
                    CompetitionFilterOptionLabel(
                        title: localizedCompetitionStringInView(key: "competitions.map_style.explore", languageCode: appLanguage),
                        isSelected: mapModeSelection == .explore
                    )
                }

                Button {
                    mapModeSelection = .satellite
                } label: {
                    CompetitionFilterOptionLabel(
                        title: localizedCompetitionStringInView(key: "competitions.map_style.satellite", languageCode: appLanguage),
                        isSelected: mapModeSelection == .satellite
                    )
                }
            }

            Section(localizedCompetitionStringInView(key: "competitions.map_look.title", languageCode: appLanguage)) {
                Button {
                    mapLookSelection = .globe
                } label: {
                    CompetitionFilterOptionLabel(
                        title: localizedCompetitionStringInView(key: "competitions.map_look.globe", languageCode: appLanguage),
                        isSelected: mapLookSelection == .globe
                    )
                }

                Button {
                    mapLookSelection = .flat
                } label: {
                    CompetitionFilterOptionLabel(
                        title: localizedCompetitionStringInView(key: "competitions.map_look.flat", languageCode: appLanguage),
                        isSelected: mapLookSelection == .flat
                    )
                }
            }

            if isExperimentalExploreGlobe {
                Section {
                    Text(localizedCompetitionStringInView(key: "competitions.map_look.explore_globe_experimental", languageCode: appLanguage))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Group {
                if mapLookSelection == .globe {
                    Image(systemName: "globe.americas.fill")
                        .font(.system(size: 18, weight: .semibold))
                } else if mapModeSelection == .explore {
                    Image(systemName: "map.fill")
                        .font(.system(size: 18, weight: .semibold))
                } else {
                    Text("🛰️")
                        .font(.system(size: 20))
                }
            }
            .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .contentShape(.circle)
    }

    private var locationButton: some View {
        Button {
            handleLocationButtonTap()
        } label: {
            Image(systemName: isFollowingUserLocation ? "location.fill" : "location")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .contentShape(.circle)
    }

    private func mapErrorOverlay(message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(localizedCompetitionStringInView(key: "wca.results_retry", languageCode: appLanguage)) {
                Task {
                    await loadMapCompetitions()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 24)
    }

    private var mapEmptyOverlay: some View {
        Text(localizedCompetitionStringInView(key: "competitions.empty", languageCode: appLanguage))
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func mapCompetitionCard(_ competition: CompetitionSummary) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        return Button {
            selectedCompetitionForDetail = competition
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(competitionFlagEmoji(for: competition.countryISO2))
                                .font(.system(size: 17))
                            Text(competition.name)
                                .font(.system(size: 17, weight: .semibold))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(localizedCompetitionDateRange(for: competition))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(competition.locationLine)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 8) {
                        HStack(alignment: .center, spacing: 8) {
                            mapStatusBadge(
                                for: mapCompetitionAvailabilityStatus(for: competition),
                                competition: competition
                            )

                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }

                        if let competitorLimit = competition.competitorLimit {
                            Text(String(format: localizedCompetitionStringInView(key: "competitions.competitor_limit_format", languageCode: appLanguage), competitorLimit))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                if !competition.venueLine.isEmpty {
                    Text(competition.venueLine)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(shape)
            .modifier(CompetitionMapCardBackground())
        }
        .buttonStyle(.plain)
        .background(shape.fill(.black.opacity(0.001)))
        .contentShape(shape)
    }

    private func mapStatusBadge(for status: CompetitionAvailabilityStatus, competition: CompetitionSummary) -> some View {
        Text(statusBadgeTitle(for: status, competition: competition, languageCode: appLanguage))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(mapStatusColor(for: status))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(mapStatusColor(for: status).opacity(0.12), in: Capsule())
    }

    private func statusBadgeTitle(for status: CompetitionAvailabilityStatus, competition: CompetitionSummary, languageCode: String) -> String {
        switch status {
        case .registrationNotOpenYet:
            let days = daysUntil(competition.localizedRegistrationStartOverride)
            return String(
                format: localizedCompetitionStringInView(
                    key: "competitions.status.registration_not_open_yet_in_format",
                    languageCode: languageCode
                ),
                days
            )
        case .upcoming:
            if let waitlistStart = competition.localizedWaitlistStartOverride, Date() < waitlistStart {
                let days = daysUntil(waitlistStart)
                return String(
                    format: localizedCompetitionStringInView(
                        key: "competitions.status.waitlist_in_format",
                        languageCode: languageCode
                    ),
                    days
                )
            }
            return status.localizedTitle(languageCode: languageCode)
        case .waitlist:
            if let waitlistStart = competition.localizedWaitlistStartOverride, Date() < waitlistStart {
                let days = daysUntil(waitlistStart)
                return String(
                    format: localizedCompetitionStringInView(
                        key: "competitions.status.waitlist_in_format",
                        languageCode: languageCode
                        ),
                        days
                    )
                }
            return localizedCompetitionStringInView(
                key: "competitions.status.waitlist_open",
                languageCode: languageCode
            )
        default:
            return status.localizedTitle(languageCode: languageCode)
        }
    }

    private func daysUntil(_ date: Date?) -> Int {
        guard let date else { return 0 }
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: date)
        return max(calendar.dateComponents([.day], from: now, to: target).day ?? 0, 0)
    }

    private func daysUntil(_ date: Date) -> Int {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: date)
        return max(calendar.dateComponents([.day], from: now, to: target).day ?? 0, 0)
    }

    private func mapCompetitionAvailabilityStatus(for competition: CompetitionSummary) -> CompetitionAvailabilityStatus {
        if let localizedStatusOverride = competition.localizedStatusOverride {
            return localizedStatusOverride
        }

        let now = Date()
        let today = Calendar.current.startOfDay(for: now)

        if competition.endDate < today {
            return .ended
        }

        let startOfCompetition = Calendar.current.startOfDay(for: competition.startDate)
        let endOfCompetition = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: competition.endDate))
            ?? competition.endDate
        if now >= startOfCompetition && now < endOfCompetition {
            return .ongoing
        }

        if let open = competition.registrationOpen,
           let close = competition.registrationClose,
           open <= now && close >= now {
            return .registrationOpen
        }

        return .upcoming
    }

    private func mapStatusColor(for status: CompetitionAvailabilityStatus) -> Color {
        switch status {
        case .upcoming:
            return .orange
        case .registrationNotOpenYet:
            return .yellow
        case .registrationOpen:
            return .green
        case .waitlist:
            return .mint
        case .ongoing:
            return .blue
        case .ended:
            return .secondary
        }
    }

    @MainActor
    private func loadMapCompetitions() async {
        let cachedSnapshot = await CompetitionService.cachedCompetitions(for: query)
        let localizedCachedCompetitions = await CompetitionService.localizeCompetitionNamesIfNeeded(
            cachedSnapshot?.competitions ?? [],
            languageCode: appLanguage
        )

        setMapCompetitionsIfChanged(CompetitionService.filterCompetitions(localizedCachedCompetitions, for: query))
        expectedCompetitionCount = cachedSnapshot?.totalCount
        isLoading = competitions.isEmpty
        isLoadingMore = !competitions.isEmpty
        errorMessage = nil
        selectedCompetitionID = nil
        selectedClusterCompetitions = []
        selectedMapItemID = nil
        if !competitions.isEmpty {
            fitCameraToVisibleCompetitions()
            hasPositionedCamera = true
        } else {
            hasPositionedCamera = false
        }

        do {
            try await refreshMapCompetitionsFromNetwork(cachedCompetitions: competitions)
        } catch {
            if competitions.isEmpty {
                errorMessage = error.localizedDescription
            }
        }

        isLoading = false
        isLoadingMore = false
    }

    private var mapInfoDateText: String {
        let formatter = DateFormatter()
        formatter.locale = appLocale(for: appLanguage)
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = localizedCompetitionStringInView(key: "competition.map_info_date_format", languageCode: appLanguage)
        return formatter.string(from: Date())
    }

    private func handleLocationButtonTap() {
        withAnimation(.snappy(duration: 0.28)) {
            selectedCompetitionID = nil
            selectedClusterCompetitions = []
        }
        isFollowingUserLocation = true
        shouldRefocusToUserLocation = true

        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            withAnimation(.snappy(duration: 0.28)) {
                focusOnUserLocation()
            }
            locationManager.requestCurrentLocation()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        default:
            isFollowingUserLocation = false
        }
    }

    private func focusOnUserLocation() {
        isFollowingUserLocation = true
        cameraPosition = .userLocation(
            followsHeading: false,
            fallback: .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 22.3193, longitude: 114.1694),
                    span: MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 8)
                )
            )
        )
    }

    private func focusOnUserLocation(using location: CLLocation) {
        cameraPosition = .region(
            MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(
                    latitudeDelta: 0.0035,
                    longitudeDelta: 0.0035
                )
            )
        )
    }

    private func localizedCompetitionDateRange(for competition: CompetitionSummary) -> String {
        let locale = appLocale(for: appLanguage)
        let calendar = Calendar(identifier: .gregorian)
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar

        let sameYear = calendar.component(.year, from: competition.startDate) == calendar.component(.year, from: competition.endDate)
        let sameMonth = sameYear && calendar.component(.month, from: competition.startDate) == calendar.component(.month, from: competition.endDate)
        let sameDay = sameMonth && calendar.component(.day, from: competition.startDate) == calendar.component(.day, from: competition.endDate)

        formatter.dateFormat = localizedCompetitionStringInView(key: "competition.date.full_format", languageCode: appLanguage)
        if sameDay {
            return formatter.string(from: competition.startDate)
        }
        if sameMonth {
            let monthFormatter = DateFormatter()
            monthFormatter.locale = locale
            monthFormatter.calendar = calendar
            monthFormatter.dateFormat = localizedCompetitionStringInView(key: "competition.date.month_day_format", languageCode: appLanguage)
            let start = monthFormatter.string(from: competition.startDate)
            formatter.dateFormat = localizedCompetitionStringInView(key: "competition.date.day_suffix_format", languageCode: appLanguage)
            return "\(start) - \(formatter.string(from: competition.endDate))"
        }
        return "\(formatter.string(from: competition.startDate)) - \(formatter.string(from: competition.endDate))"
    }

    private func fitCameraToVisibleCompetitions() {
        let coordinates = mappableCompetitions.compactMap { competition -> CLLocationCoordinate2D? in
            guard let latitude = competition.latitude,
                  let longitude = competition.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        guard !coordinates.isEmpty else { return }

        if coordinates.count == 1, let coordinate = coordinates.first {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 6, longitudeDelta: 6)
                )
            )
            return
        }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)

        guard let minLatitude = latitudes.min(),
              let maxLatitude = latitudes.max(),
              let minLongitude = longitudes.min(),
              let maxLongitude = longitudes.max() else {
            return
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLatitude - minLatitude) * 1.4, 8),
            longitudeDelta: max((maxLongitude - minLongitude) * 1.4, 8)
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    @MainActor
    private func requestLocationIfAuthorized() async {
        guard locationManager.authorizationStatus == .authorizedAlways
            || locationManager.authorizationStatus == .authorizedWhenInUse else {
            return
        }
        locationManager.requestCurrentLocation()
        if let currentLocation = locationManager.currentLocation {
            await loadCityIfNeeded(for: currentLocation)
            await loadWeatherIfNeeded(for: currentLocation)
        }
    }

    @MainActor
    private func refreshWeather() async {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if let currentLocation = locationManager.currentLocation {
                await loadWeather(for: currentLocation)
            } else {
                locationManager.requestCurrentLocation()
            }
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        default:
            weatherSnapshot = nil
        }
    }

    @MainActor
    private func loadWeatherIfNeeded(for location: CLLocation) async {
        if let lastWeatherLocation,
           location.distance(from: lastWeatherLocation) < 500,
           weatherSnapshot != nil {
            return
        }
        await loadWeather(for: location)
    }

    @MainActor
    private func loadWeather(for location: CLLocation) async {
        isLoadingWeather = true
        defer { isLoadingWeather = false }

        do {
            let weather = try await WeatherService.shared.weather(for: location)
            weatherSnapshot = CompetitionWeatherSnapshot(
                currentWeather: weather.currentWeather,
                languageCode: appLanguage
            )
            lastWeatherLocation = location
        } catch {
            weatherSnapshot = nil
        }
    }

    @MainActor
    private func loadCityIfNeeded(for location: CLLocation) async {
        if let lastResolvedCityLocation,
           location.distance(from: lastResolvedCityLocation) < 500,
           currentCityName != nil {
            return
        }

        guard !isResolvingCity else { return }
        isResolvingCity = true
        defer { isResolvingCity = false }

        do {
            if #available(iOS 26.0, *) {
                guard let request = MKReverseGeocodingRequest(location: location) else { return }
                let mapItems = try await request.mapItems
                guard let mapItem = mapItems.first else { return }
                let addressRepresentations = mapItem.addressRepresentations
                let cityName = addressRepresentations?.cityName
                let cityWithContext = addressRepresentations?.cityWithContext
                let shortCityWithContext = addressRepresentations?.cityWithContext(.short)
                let regionName = addressRepresentations?.regionName
                let shortAddress = mapItem.address?.shortAddress
                let fullAddress = mapItem.address?.fullAddress
                currentCityName = cityName
                    ?? cityWithContext
                    ?? shortCityWithContext
                    ?? regionName
                    ?? shortAddress
                    ?? fullAddress
            } else {
                let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
                guard let placemark = placemarks.first else { return }
                currentCityName =
                    placemark.locality
                    ?? placemark.subAdministrativeArea
                    ?? placemark.administrativeArea
                    ?? placemark.country
            }
            lastResolvedCityLocation = location
        } catch {
            currentCityName = nil
        }
    }

    @MainActor
    private func refreshMapCompetitionsFromNetwork(cachedCompetitions: [CompetitionSummary]) async throws {
        var freshCompetitions: [CompetitionSummary] = []
        var page = 1

        while true {
            let result = try await CompetitionService.fetchCompetitionsPage(query: query, page: page)
            if expectedCompetitionCount == nil, let totalCount = result.totalCount {
                expectedCompetitionCount = totalCount
            }

            let localizedCompetitions = await CompetitionService.localizeCompetitionNamesIfNeeded(
                result.competitions,
                languageCode: appLanguage
            )
            freshCompetitions.append(contentsOf: localizedCompetitions)
                setMapCompetitionsIfChanged(
                    CompetitionService.filterCompetitions(
                        mergedMapCompetitions(cached: cachedCompetitions, fresh: freshCompetitions),
                        for: query
                    )
                )

            if !hasPositionedCamera {
                fitCameraToVisibleCompetitions()
                hasPositionedCamera = true
            }

            guard let nextPage = result.nextPage else {
                setMapCompetitionsIfChanged(CompetitionService.filterCompetitions(freshCompetitions, for: query))
                expectedCompetitionCount = result.totalCount ?? freshCompetitions.count
                await CompetitionService.cacheCompetitions(
                    competitions,
                    totalCount: expectedCompetitionCount,
                    for: query
                )
                return
            }

            page = nextPage
            isLoading = false
            isLoadingMore = true
        }
    }

    private func mergedMapCompetitions(
        cached: [CompetitionSummary],
        fresh: [CompetitionSummary]
    ) -> [CompetitionSummary] {
        let freshIDs = Set(fresh.map(\.id))
        let staleCache = cached.filter { !freshIDs.contains($0.id) }
        return fresh + staleCache
    }

    private func setMapCompetitionsIfChanged(_ newCompetitions: [CompetitionSummary]) {
        guard competitions.map(\.id) != newCompetitions.map(\.id) else { return }
        competitions = newCompetitions
    }
}

@available(iOS 17.0, *)
enum CompetitionMapMode: String, CaseIterable {
    case satellite
    case explore

    func mapStyle(look: CompetitionMapLook) -> MapStyle {
        switch self {
        case .satellite:
            return .hybrid(elevation: look.elevation)
        case .explore:
            return .standard(elevation: look.elevation)
        }
    }
}

@available(iOS 17.0, *)
enum CompetitionMapLook: String, CaseIterable {
    case globe
    case flat

    var elevation: MapStyle.Elevation {
        switch self {
        case .globe:
            return .realistic
        case .flat:
            return .flat
        }
    }
}

@MainActor
private final class CompetitionLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var currentLocation: CLLocation?

    private let manager: CLLocationManager

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        self.authorizationStatus = manager.authorizationStatus
        self.currentLocation = manager.location
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.delegate = self
        if manager.authorizationStatus == .authorizedAlways
            || manager.authorizationStatus == .authorizedWhenInUse {
            manager.startUpdatingLocation()
            manager.requestLocation()
        }
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func requestCurrentLocation() {
        manager.startUpdatingLocation()
        manager.requestLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedAlways
                || manager.authorizationStatus == .authorizedWhenInUse {
                self.manager.startUpdatingLocation()
                self.manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            currentLocation = location
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Keep the last known location if the refresh fails.
    }
}

@available(iOS 16.0, *)
private struct CompetitionWeatherSnapshot {
    let symbolName: String
    let temperatureText: String

    init(currentWeather: CurrentWeather, languageCode: String) {
        symbolName = currentWeather.symbolName

        let formatter = MeasurementFormatter()
        formatter.locale = appLocale(for: languageCode)
        formatter.unitOptions = .temperatureWithoutUnit
        formatter.numberFormatter.maximumFractionDigits = 0
        formatter.numberFormatter.minimumFractionDigits = 0
        temperatureText = formatter.string(from: currentWeather.temperature)
    }
}

private enum MapAccessoryGlassShape {
    case circle
    case capsule
}

private struct MapAccessoryGlassModifier: ViewModifier {
    let shape: MapAccessoryGlassShape

    @ViewBuilder
    func body(content: Content) -> some View {
        switch shape {
        case .circle:
            if #available(iOS 26.0, *) {
                content
                    .foregroundStyle(.primary)
                    .glassEffect(.regular.interactive(), in: .circle)
            } else {
                content
                    .foregroundStyle(.primary)
                    .background(.regularMaterial, in: Circle())
            }
        case .capsule:
            if #available(iOS 26.0, *) {
                content
                    .foregroundStyle(.primary)
                    .glassEffect(.regular.interactive(), in: .capsule)
            } else {
                content
                    .foregroundStyle(.primary)
                    .background(.regularMaterial, in: Capsule())
            }
        }
    }
}

private struct CompetitionMapCardHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct CompetitionMapCardBackground: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        }
    }
}

private extension View {
    func measureHeight(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: CompetitionMapCardHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(CompetitionMapCardHeightPreferenceKey.self, perform: onChange)
    }
}

private struct CompetitionFilterButtonBackground: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .clipShape(.circle)
                .glassEffect(.regular.interactive(), in: .circle)
        } else {
            content
                .background(.thinMaterial, in: Circle())
        }
    }
}

#endif

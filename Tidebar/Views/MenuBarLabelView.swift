//
//  MenuBarLabelView.swift
//  Tidebar
//

import AppKit
import SwiftUI

/// The status item: value, SF Symbol trend arrow, and change since the previous reading, e.g. `112 → ⊕4`,
/// dimmed with an age suffix when aging, `--- ?` when unknown.
///
/// `MenuBarExtra` labels ignore most layout modifiers, so the content is rendered into a template image.
/// That keeps the monospaced digits, the reserved width, and the dimming, and still tints correctly
/// for light, dark, and highlighted menu bars.
struct MenuBarLabelView: View {
    let glucoseMonitor: GlucoseMonitor

    @AppStorage(AppSettingsKeys.glucoseUnit) private var glucoseUnit = GlucoseUnit.milligramsPerDeciliter
    @AppStorage(AppSettingsKeys.menuBarFontSizePoints) private var fontSizePoints = MenuBarTextStyle.defaultFontSizePoints
    @AppStorage(AppSettingsKeys.menuBarFontWeight) private var fontWeight = MenuBarTextStyle.defaultFontWeight
    @AppStorage(AppSettingsKeys.menuBarFontDesign) private var fontDesign = MenuBarTextStyle.defaultFontDesign
    @AppStorage(AppSettingsKeys.menuBarShowsDifference) private var showsDifference = true
    @AppStorage(AppSettingsKeys.menuBarDimsAgingReadings) private var dimsAgingReadings = true
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let displayState = glucoseMonitor.displayState
        Image(nsImage: renderStatusImage(for: displayState))
            .accessibilityLabel(
                GlucoseStatusFormatter.accessibilityDescription(
                    for: displayState,
                    glucoseUnit: glucoseUnit,
                    showsDifference: showsDifference
                ))
    }

    private func renderStatusImage(for displayState: GlucoseDisplayState) -> NSImage {
        let statusContent = GlucoseStatusFormatter.menuBarStatusContent(
            for: displayState,
            glucoseUnit: glucoseUnit,
            currentDate: glucoseMonitor.displayEvaluationDate,
            showsDifference: showsDifference,
            dimsAgingReadings: dimsAgingReadings
        )
        let statusView = MenuBarStatusView(
            statusContent: statusContent,
            widthReservingContents: GlucoseStatusFormatter.widthReservingContents(
                for: glucoseUnit,
                isDifferenceShown: statusContent.differenceContent != nil
            ),
            textStyle: MenuBarTextStyle(fontSizePoints: fontSizePoints, fontWeight: fontWeight, fontDesign: fontDesign)
        )
        // Template images use only alpha, so draw in solid black and let the system tint it.
        let imageRenderer = ImageRenderer(content: statusView.foregroundStyle(.black))
        imageRenderer.scale = displayScale
        let renderedImage = imageRenderer.nsImage ?? NSImage()
        renderedImage.isTemplate = true
        return renderedImage
    }
}

/// Lays the visible content over invisible copies of typical content, so the status item
/// keeps the same width as values and single arrows change.
/// Also used by Settings to preview the chosen text style.
struct MenuBarStatusView: View {
    static let dimmedOpacity = 0.45

    let statusContent: GlucoseStatusFormatter.MenuBarStatusContent
    let widthReservingContents: [GlucoseStatusFormatter.MenuBarStatusContent]
    let textStyle: MenuBarTextStyle

    var body: some View {
        ZStack {
            ForEach(Array(widthReservingContents.enumerated()), id: \.offset) { _, widthReservingContent in
                MenuBarStatusRow(statusContent: widthReservingContent, textStyle: textStyle).hidden()
            }
            MenuBarStatusRow(statusContent: statusContent, textStyle: textStyle)
        }
        .opacity(statusContent.isDimmed ? Self.dimmedOpacity : 1)
        .fixedSize()
    }
}

private struct MenuBarStatusRow: View {
    /// Spacing tuned at the default font size; scaled for other sizes.
    static let valueToArrowSpacing = 3.0
    /// Pulls repeated arrows together so a double arrow reads as one glyph.
    static let repeatedArrowSpacing = -3.0
    /// Added to the usual spacing between the change and the age suffix, which are both numbers.
    static let differenceToAgeExtraSpacing = 4.0

    let statusContent: GlucoseStatusFormatter.MenuBarStatusContent
    let textStyle: MenuBarTextStyle

    var body: some View {
        HStack(spacing: textStyle.scaledSpacing(Self.valueToArrowSpacing)) {
            Text(statusContent.valueText)
            trendArrowImages
            if let differenceContent = statusContent.differenceContent {
                MenuBarDifferenceView(differenceContent: differenceContent, textStyle: textStyle)
                    // Keeps `+4 8m` from reading as `+48m`.
                    .padding(.trailing, statusContent.ageSuffixText == nil ? 0 : textStyle.scaledSpacing(Self.differenceToAgeExtraSpacing))
            }
            if let ageSuffixText = statusContent.ageSuffixText {
                Text(ageSuffixText)
            }
        }
        .font(textStyle.font)
        // Without this the value truncates (`1… → 8m`) in the Settings preview when an age suffix is shown.
        .fixedSize()
    }

    private var trendArrowImages: some View {
        HStack(spacing: textStyle.scaledSpacing(Self.repeatedArrowSpacing)) {
            ForEach(Array(statusContent.trendSymbolNames.enumerated()), id: \.offset) { _, trendSymbolName in
                Image(systemName: trendSymbolName)
                    .imageScale(.small)
                    .fontWeight(.bold)
            }
        }
    }
}

/// The change since the previous reading, e.g. `⊕4`: an SF Symbol sign tucked against the amount.
private struct MenuBarDifferenceView: View {
    /// Spacing tuned at the default font size; scaled for other sizes.
    static let signToMagnitudeSpacing = 1.0

    let differenceContent: GlucoseStatusFormatter.DifferenceContent
    let textStyle: MenuBarTextStyle

    var body: some View {
        HStack(spacing: textStyle.scaledSpacing(Self.signToMagnitudeSpacing)) {
            Image(systemName: differenceContent.signSymbolName)
                .imageScale(.small)
            Text(differenceContent.magnitudeText)
        }
    }
}

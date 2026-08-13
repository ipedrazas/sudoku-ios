#!/usr/bin/env swift
//
// Draws the app icon into SudokuApp/Resources/Assets.xcassets/AppIcon.appiconset/.
//
//   swift scripts/make-icon.swift
//
// **What replaced what.** The icon used to be the web app's `logo.svg`,
// rasterised by ImageMagick and then stroke-dilated so the hairlines survived
// being shrunk. It shipped, and the word that came back from players was
// "amateur" — fairly. Dilating a rasterised line drawing thickens it by
// smearing its pixels outward, so every curve arrived with a lumpy, uneven edge,
// and the mark said nothing about Sudoku to anyone who had not installed it yet.
//
// So: drawn rather than traced, and drawn here rather than in SVG. ImageMagick's
// SVG renderer is partial — it dropped the grid entirely from the first attempt
// and reported success — and librsvg is not something to make a contributor
// install to change a stroke width. CoreGraphics is already on every machine
// that can build this app, it is deterministic, and re-running reproduces the
// files byte for byte.
//
// **What it draws.** A three-by-three grid, with a slice of cake over it.
// Three by three rather than nine by nine because at 40 points — where an icon
// actually has to work — nine columns are a grey wash and three still read as a
// Sudoku box. The slice is haloed in the background colour so the grid lines
// stop at its edge instead of running through it; without that the two shapes
// merge into one grey blob the moment the icon is small.
//
// Two tones and a tint of one of them, no more. The tinted variant is flattened
// to greyscale by the system and composited against a colour the player chose,
// so any third colour here would either clash there or vanish.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let side = 1024.0

// MARK: - Palette

struct Palette {
    let background: CGColor
    let mark: CGColor
    /// The grid. A flat tint rather than the mark at reduced opacity: the tinted
    /// variant is composited against the system's colour, and an alpha channel
    /// there would let that colour through the grid and not through the cake.
    let grid: CGColor
    let name: String
}

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(
        red: Double((hex >> 16) & 0xFF) / 255,
        green: Double((hex >> 8) & 0xFF) / 255,
        blue: Double(hex & 0xFF) / 255,
        alpha: 1
    )
}

let palettes = [
    // Warm cream rather than white: the mark is brown, and white behind it is
    // colder than anything on either app's screens.
    Palette(
        background: rgb(0xFDF6EC), mark: rgb(0x5C4033), grid: rgb(0xD6BFA4),
        name: "icon-light"
    ),
    Palette(
        background: rgb(0x141110), mark: rgb(0xEBD9C6), grid: rgb(0x453A32),
        name: "icon-dark"
    ),
    // Greyscale on black: the system tints this one itself.
    Palette(
        background: rgb(0x000000), mark: rgb(0xFFFFFF), grid: rgb(0x6E6E6E),
        name: "icon-tinted"
    ),
]

// MARK: - Geometry
//
// One coordinate space, 1024 square, y down — the space the numbers below were
// eyeballed in, at the size they were eyeballed at.

/// The grid's bounds. Inset to 67% of the canvas: iOS rounds the corners and
/// then shrinks what is inside them, so a mark drawn to the edges reads as
/// cramped next to every other icon on the row.
let gridRect = CGRect(x: 172, y: 172, width: 680, height: 680)
let gridCorner = 76.0
let gridBorderWidth = 30.0
let gridLineWidth = 20.0

/// The slice, as a closed path with rounded corners.
///
/// A slice seen from the side: thin tip on the left, tall crust on the right,
/// the top sloping between them. Two shapes were tried and thrown away — a
/// symmetrical peak, which is a house with a ball on it, and a plain flat-topped
/// wedge, which is a doorstop. What separates a slice from both is the ratio of
/// the two vertical edges: 130 against 340 here, and the drawing stops reading
/// as cake somewhere around two to one.
///
/// In drawing order from the bottom left, clockwise.
let sliceCorners = [
    CGPoint(x: 258, y: 704),
    CGPoint(x: 258, y: 574),  // the tip
    CGPoint(x: 768, y: 364),  // the crust
    CGPoint(x: 768, y: 704),
]
let sliceCornerRadius = 26.0

/// The layers, knocked out in the background colour: one shape with gaps in it
/// stays one shape at any size, and three shapes in two colours do not.
///
/// Level, not parallel to the sloping top, because the layers of a cake are
/// level whatever its top is doing — which is also why the upper one runs out
/// before it reaches the tip. Two thin ones rather than one thick one: a wide
/// band cuts the slice into two slabs and what is left reads as a sandwich.
let creamBands = [(top: 488.0, height: 34.0), (top: 586.0, height: 34.0)]

/// How far the background colour is pushed out around the cake before the cake
/// is drawn on top of it.
let haloWidth = 28.0

// MARK: - Drawing

/// The outline of the slice, with every corner rounded by the same radius.
func slicePath() -> CGPath {
    let path = CGMutablePath()
    let count = sliceCorners.count

    path.move(to: midpoint(sliceCorners[count - 1], sliceCorners[0]))
    for index in 0..<count {
        path.addArc(
            tangent1End: sliceCorners[index],
            tangent2End: sliceCorners[(index + 1) % count],
            radius: sliceCornerRadius
        )
    }
    path.closeSubpath()
    return path
}

func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
    CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
}

/// The cream bands. Drawn wider than the slice and clipped to it by the caller,
/// so their ends meet the slice's edges exactly rather than being fitted to them.
func creamPath() -> CGPath {
    let path = CGMutablePath()
    for band in creamBands {
        path.addRect(CGRect(x: 0, y: band.top, width: side, height: band.height))
    }
    return path
}

func gridPath() -> CGPath {
    let path = CGMutablePath()
    let third = gridRect.width / 3
    for step in 1...2 {
        let offset = third * Double(step)
        path.move(to: CGPoint(x: gridRect.minX + offset, y: gridRect.minY))
        path.addLine(to: CGPoint(x: gridRect.minX + offset, y: gridRect.maxY))
        path.move(to: CGPoint(x: gridRect.minX, y: gridRect.minY + offset))
        path.addLine(to: CGPoint(x: gridRect.maxX, y: gridRect.minY + offset))
    }
    return path
}

func draw(_ palette: Palette) -> CGImage {
    guard
        let context = CGContext(
            data: nil,
            width: Int(side),
            height: Int(side),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
    else { fatalError("could not make a bitmap context") }

    // y down, so the numbers above read the way they were drawn.
    context.translateBy(x: 0, y: side)
    context.scaleBy(x: 1, y: -1)

    context.setFillColor(palette.background)
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))

    // The board, behind everything.
    context.setStrokeColor(palette.grid)
    context.setLineCap(.round)
    context.setLineWidth(gridBorderWidth)
    context.addPath(CGPath(roundedRect: gridRect, cornerWidth: gridCorner, cornerHeight: gridCorner, transform: nil))
    context.strokePath()
    context.setLineWidth(gridLineWidth)
    context.addPath(gridPath())
    context.strokePath()

    // The halo: the slice's own outline, stroked wide in the background colour.
    let slice = slicePath()
    context.setStrokeColor(palette.background)
    context.setFillColor(palette.background)
    context.setLineWidth(haloWidth * 2)
    context.setLineJoin(.round)
    context.addPath(slice)
    context.drawPath(using: .fillStroke)

    // The slice.
    context.setFillColor(palette.mark)
    context.addPath(slice)
    context.fillPath()

    context.saveGState()
    context.addPath(slice)
    context.clip()
    context.setFillColor(palette.background)
    context.addPath(creamPath())
    context.fillPath()
    context.restoreGState()

    // No cherry, and not for want of trying. A disc on top of the sloping edge
    // reads as a head on a shoulder at full size and as a lump on the crust at
    // 120 px, wherever along the slope it is put — the slope is what does it,
    // and the slope is what makes the shape a slice. The layers carry the
    // drawing on their own.

    guard let image = context.makeImage() else { fatalError("could not render") }
    return image
}

// MARK: - Output

let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("SudokuApp/Resources/Assets.xcassets/AppIcon.appiconset")

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

for palette in palettes {
    let url = output.appendingPathComponent("\(palette.name).png")
    guard
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("could not write \(url.path)") }
    CGImageDestinationAddImage(destination, draw(palette), nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("could not finalise \(url.path)") }
    print("wrote \(palette.name).png")
}

let contents = """
{
  "images" : [
    {
      "filename" : "icon-light.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "filename" : "icon-dark.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "tinted"
        }
      ],
      "filename" : "icon-tinted.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""
try contents.write(to: output.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("wrote Contents.json")

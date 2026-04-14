#!/usr/bin/env swift
// Generates the Notifly AppIcon set programmatically using Core Graphics.
// Run from the project root: swift macos/scripts/generate-app-icon.swift
//
// Design: a plump, friendly bell character with a simple smile, tilted slightly
// mid-ring, on a warm coral→lavender gradient. Two small sparkles flank the bell
// to suggest a gentle "ding". Calm and playful — matches Notifly's tone of
// "one notification per project at a time, nothing ever stacks."

import Foundation
import AppKit
import CoreGraphics

let projectRoot = FileManager.default.currentDirectoryPath
let iconsetDir = projectRoot + "/macos/Notifly/Assets.xcassets/AppIcon.appiconset"
let projectIconPath = projectRoot + "/.claude/icon.png"

struct IconSize {
  let filename: String
  let pixels: Int
}

let sizes: [IconSize] = [
  IconSize(filename: "icon_16x16.png",       pixels: 16),
  IconSize(filename: "icon_16x16@2x.png",    pixels: 32),
  IconSize(filename: "icon_32x32.png",       pixels: 32),
  IconSize(filename: "icon_32x32@2x.png",    pixels: 64),
  IconSize(filename: "icon_128x128.png",     pixels: 128),
  IconSize(filename: "icon_128x128@2x.png",  pixels: 256),
  IconSize(filename: "icon_256x256.png",     pixels: 256),
  IconSize(filename: "icon_256x256@2x.png",  pixels: 512),
  IconSize(filename: "icon_512x512.png",     pixels: 512),
  IconSize(filename: "icon_512x512@2x.png",  pixels: 1024),
]

// MARK: - Drawing

func render(pixels: Int) -> NSImage {
  let size = CGFloat(pixels)
  let image = NSImage(size: NSSize(width: size, height: size))
  image.lockFocus()
  defer { image.unlockFocus() }

  guard let ctx = NSGraphicsContext.current?.cgContext else { return image }
  ctx.setShouldAntialias(true)
  ctx.setAllowsAntialiasing(true)
  ctx.interpolationQuality = .high

  // Rounded-square mask — macOS Big Sur+ uses ~22.5% corner radius
  let cornerRadius = size * 0.225
  let rect = CGRect(x: 0, y: 0, width: size, height: size)
  let maskPath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
  ctx.saveGState()
  ctx.addPath(maskPath)
  ctx.clip()

  // MARK: Background gradient — coral → lavender
  let colorSpace = CGColorSpaceCreateDeviceRGB()
  let bgColors = [
    CGColor(red: 1.00, green: 0.56, blue: 0.42, alpha: 1.0), // warm coral
    CGColor(red: 1.00, green: 0.42, blue: 0.58, alpha: 1.0), // rose pink
    CGColor(red: 0.62, green: 0.44, blue: 0.92, alpha: 1.0), // soft lavender
  ] as CFArray
  let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 0.5, 1.0])!
  ctx.drawLinearGradient(
    bgGradient,
    start: CGPoint(x: 0, y: size),
    end: CGPoint(x: size, y: 0),
    options: []
  )

  // Soft top highlight
  let highlight = [
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.25),
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
  ] as CFArray
  let hg = CGGradient(colorsSpace: colorSpace, colors: highlight, locations: [0, 1])!
  ctx.drawRadialGradient(
    hg,
    startCenter: CGPoint(x: size * 0.3, y: size * 0.85),
    startRadius: 0,
    endCenter: CGPoint(x: size * 0.3, y: size * 0.85),
    endRadius: size * 0.7,
    options: []
  )

  // MARK: Sparkles (behind bell for depth)
  drawSparkle(ctx: ctx, center: CGPoint(x: size * 0.18, y: size * 0.70), radius: size * 0.035, alpha: 0.85)
  drawSparkle(ctx: ctx, center: CGPoint(x: size * 0.86, y: size * 0.62), radius: size * 0.045, alpha: 0.90)
  drawSparkle(ctx: ctx, center: CGPoint(x: size * 0.14, y: size * 0.38), radius: size * 0.025, alpha: 0.70)
  drawSparkle(ctx: ctx, center: CGPoint(x: size * 0.82, y: size * 0.28), radius: size * 0.030, alpha: 0.75)

  // MARK: Bell — tilted slightly right to suggest mid-ring motion
  ctx.saveGState()
  ctx.translateBy(x: size * 0.5, y: size * 0.5)
  let tilt: CGFloat = -0.09 // radians, slight clockwise tilt
  ctx.rotate(by: tilt)
  ctx.translateBy(x: -size * 0.5, y: -size * 0.5)

  drawBell(ctx: ctx, size: size)

  ctx.restoreGState()

  ctx.restoreGState()
  return image
}

// MARK: - Bell

func drawBell(ctx: CGContext, size: CGFloat) {
  let cx = size * 0.5
  let cy = size * 0.50

  // Bell silhouette: narrow rounded dome at top, flared wide rim at bottom.
  // Anchor points (in screen coords where y grows upward in Core Graphics default,
  // but NSImage.lockFocus uses y-up, so "top" = higher y, "bottom" = lower y).
  let bellHeight = size * 0.62
  let topY = cy + bellHeight * 0.50         // crown of dome
  let shoulderY = cy + bellHeight * 0.22    // where dome transitions to body
  let rimY = cy - bellHeight * 0.32         // top edge of the flared rim
  let flareY = cy - bellHeight * 0.40       // bottom of flared rim

  let topHalfWidth = size * 0.16            // narrow top of dome
  let shoulderHalfWidth = size * 0.26       // body widening
  let rimHalfWidth = size * 0.33            // widest part (the flare)
  let flareHalfWidth = size * 0.33

  let bellPath = CGMutablePath()
  // Start at bottom-left of the flared rim
  bellPath.move(to: CGPoint(x: cx - flareHalfWidth, y: flareY))
  // Bottom edge of rim (gentle upward curve)
  bellPath.addQuadCurve(
    to: CGPoint(x: cx + flareHalfWidth, y: flareY),
    control: CGPoint(x: cx, y: flareY - size * 0.025)
  )
  // Right edge of rim going up to rim-top
  bellPath.addLine(to: CGPoint(x: cx + rimHalfWidth, y: rimY))
  // Right body curving inward to the dome shoulder
  bellPath.addQuadCurve(
    to: CGPoint(x: cx + shoulderHalfWidth, y: shoulderY),
    control: CGPoint(x: cx + rimHalfWidth - size * 0.005, y: rimY + (shoulderY - rimY) * 0.55)
  )
  // Right dome shoulder curving up to the crown
  bellPath.addQuadCurve(
    to: CGPoint(x: cx + topHalfWidth, y: topY - size * 0.015),
    control: CGPoint(x: cx + shoulderHalfWidth, y: shoulderY + (topY - shoulderY) * 0.55)
  )
  // Top of dome (rounded crown)
  bellPath.addQuadCurve(
    to: CGPoint(x: cx - topHalfWidth, y: topY - size * 0.015),
    control: CGPoint(x: cx, y: topY + size * 0.05)
  )
  // Left dome shoulder back down
  bellPath.addQuadCurve(
    to: CGPoint(x: cx - shoulderHalfWidth, y: shoulderY),
    control: CGPoint(x: cx - shoulderHalfWidth, y: shoulderY + (topY - shoulderY) * 0.55)
  )
  // Left body back out to the rim
  bellPath.addQuadCurve(
    to: CGPoint(x: cx - rimHalfWidth, y: rimY),
    control: CGPoint(x: cx - rimHalfWidth + size * 0.005, y: rimY + (shoulderY - rimY) * 0.55)
  )
  // Left edge of rim down to flare
  bellPath.addLine(to: CGPoint(x: cx - flareHalfWidth, y: flareY))
  bellPath.closeSubpath()

  // Reference Y values for features below
  let top = topY
  let bottom = flareY

  // Soft drop shadow under the bell
  ctx.saveGState()
  ctx.setShadow(
    offset: CGSize(width: 0, height: -size * 0.015),
    blur: size * 0.04,
    color: CGColor(red: 0.2, green: 0.05, blue: 0.2, alpha: 0.35)
  )

  // Fill with a creamy warm-white gradient for dimensional feel
  let colorSpace = CGColorSpaceCreateDeviceRGB()
  let bellColors = [
    CGColor(red: 1.00, green: 0.98, blue: 0.92, alpha: 1.0), // cream
    CGColor(red: 1.00, green: 0.86, blue: 0.55, alpha: 1.0), // warm amber
  ] as CFArray
  let bellGradient = CGGradient(colorsSpace: colorSpace, colors: bellColors, locations: [0, 1])!

  ctx.addPath(bellPath)
  ctx.clip()
  ctx.drawLinearGradient(
    bellGradient,
    start: CGPoint(x: cx, y: top),
    end: CGPoint(x: cx, y: bottom),
    options: []
  )
  ctx.restoreGState()

  // Outline the bell crisply
  ctx.saveGState()
  ctx.addPath(bellPath)
  ctx.setStrokeColor(CGColor(red: 0.32, green: 0.10, blue: 0.22, alpha: 1.0))
  ctx.setLineWidth(max(1.0, size * 0.018))
  ctx.setLineJoin(.round)
  ctx.strokePath()
  ctx.restoreGState()

  // Bell handle/knob on top (small circle)
  let knobRadius = size * 0.035
  let knobCenter = CGPoint(x: cx, y: top + knobRadius * 0.6)
  ctx.saveGState()
  ctx.setFillColor(CGColor(red: 1.00, green: 0.86, blue: 0.55, alpha: 1.0))
  ctx.setStrokeColor(CGColor(red: 0.32, green: 0.10, blue: 0.22, alpha: 1.0))
  ctx.setLineWidth(max(1.0, size * 0.016))
  ctx.addEllipse(in: CGRect(
    x: knobCenter.x - knobRadius,
    y: knobCenter.y - knobRadius,
    width: knobRadius * 2,
    height: knobRadius * 2
  ))
  ctx.drawPath(using: .fillStroke)
  ctx.restoreGState()

  // Clapper (little ball under the rim)
  let clapperRadius = size * 0.045
  let clapperCenter = CGPoint(x: cx + size * 0.01, y: bottom - size * 0.01)
  ctx.saveGState()
  ctx.setFillColor(CGColor(red: 0.32, green: 0.10, blue: 0.22, alpha: 1.0))
  ctx.addEllipse(in: CGRect(
    x: clapperCenter.x - clapperRadius,
    y: clapperCenter.y - clapperRadius,
    width: clapperRadius * 2,
    height: clapperRadius * 2
  ))
  ctx.fillPath()
  ctx.restoreGState()

  // MARK: Face — two eyes and a small smile
  // Eyes
  let eyeRadius = size * 0.028
  let eyeY = cy + size * 0.05
  let eyeDX = size * 0.085
  let leftEye = CGPoint(x: cx - eyeDX, y: eyeY)
  let rightEye = CGPoint(x: cx + eyeDX, y: eyeY)

  ctx.setFillColor(CGColor(red: 0.22, green: 0.06, blue: 0.18, alpha: 1.0))
  for eye in [leftEye, rightEye] {
    ctx.addEllipse(in: CGRect(
      x: eye.x - eyeRadius,
      y: eye.y - eyeRadius,
      width: eyeRadius * 2,
      height: eyeRadius * 2
    ))
  }
  ctx.fillPath()

  // Tiny white glint on each eye (skip on very small renders)
  if size >= 64 {
    let glintRadius = eyeRadius * 0.38
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    for eye in [leftEye, rightEye] {
      ctx.addEllipse(in: CGRect(
        x: eye.x + eyeRadius * 0.25 - glintRadius,
        y: eye.y + eyeRadius * 0.25 - glintRadius,
        width: glintRadius * 2,
        height: glintRadius * 2
      ))
    }
    ctx.fillPath()
  }

  // Smile — a small upward arc
  ctx.saveGState()
  ctx.setStrokeColor(CGColor(red: 0.22, green: 0.06, blue: 0.18, alpha: 1.0))
  ctx.setLineWidth(max(1.2, size * 0.022))
  ctx.setLineCap(.round)
  let smileWidth = size * 0.11
  let smileCenter = CGPoint(x: cx, y: eyeY - size * 0.065)
  let smilePath = CGMutablePath()
  smilePath.move(to: CGPoint(x: smileCenter.x - smileWidth * 0.5, y: smileCenter.y + size * 0.01))
  smilePath.addQuadCurve(
    to: CGPoint(x: smileCenter.x + smileWidth * 0.5, y: smileCenter.y + size * 0.01),
    control: CGPoint(x: smileCenter.x, y: smileCenter.y - size * 0.04)
  )
  ctx.addPath(smilePath)
  ctx.strokePath()
  ctx.restoreGState()

  // Rosy cheeks (skip on smallest sizes)
  if size >= 48 {
    let cheekRadius = size * 0.028
    let cheekY = eyeY - size * 0.04
    let cheekDX = size * 0.135
    ctx.setFillColor(CGColor(red: 1.00, green: 0.55, blue: 0.55, alpha: 0.55))
    for cx2 in [cx - cheekDX, cx + cheekDX] {
      ctx.addEllipse(in: CGRect(
        x: cx2 - cheekRadius,
        y: cheekY - cheekRadius * 0.7,
        width: cheekRadius * 2,
        height: cheekRadius * 1.4
      ))
    }
    ctx.fillPath()
  }
}

// MARK: - Sparkle

func drawSparkle(ctx: CGContext, center: CGPoint, radius r: CGFloat, alpha: CGFloat) {
  let path = CGMutablePath()
  // A 4-point star
  path.move(to: CGPoint(x: center.x, y: center.y + r))
  path.addQuadCurve(
    to: CGPoint(x: center.x + r, y: center.y),
    control: CGPoint(x: center.x + r * 0.25, y: center.y + r * 0.25)
  )
  path.addQuadCurve(
    to: CGPoint(x: center.x, y: center.y - r),
    control: CGPoint(x: center.x + r * 0.25, y: center.y - r * 0.25)
  )
  path.addQuadCurve(
    to: CGPoint(x: center.x - r, y: center.y),
    control: CGPoint(x: center.x - r * 0.25, y: center.y - r * 0.25)
  )
  path.addQuadCurve(
    to: CGPoint(x: center.x, y: center.y + r),
    control: CGPoint(x: center.x - r * 0.25, y: center.y + r * 0.25)
  )
  path.closeSubpath()

  ctx.saveGState()
  ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: alpha))
  ctx.addPath(path)
  ctx.fillPath()
  ctx.restoreGState()
}

// MARK: - Save

func savePNG(_ image: NSImage, to path: String) throws {
  guard let tiff = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff),
        let png = rep.representation(using: .png, properties: [:]) else {
    throw NSError(domain: "icon", code: 1)
  }
  try png.write(to: URL(fileURLWithPath: path))
}

print("Generating Notifly app icon set into \(iconsetDir)")
try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

for s in sizes {
  let image = render(pixels: s.pixels)
  let path = iconsetDir + "/" + s.filename
  do {
    try savePNG(image, to: path)
    print("  ok \(s.filename) (\(s.pixels)x\(s.pixels))")
  } catch {
    print("  FAIL \(s.filename): \(error)")
  }
}

// Update Contents.json
let contents: [String: Any] = [
  "info": ["author": "xcode", "version": 1],
  "images": [
    ["idiom": "mac", "scale": "1x", "size": "16x16",   "filename": "icon_16x16.png"],
    ["idiom": "mac", "scale": "2x", "size": "16x16",   "filename": "icon_16x16@2x.png"],
    ["idiom": "mac", "scale": "1x", "size": "32x32",   "filename": "icon_32x32.png"],
    ["idiom": "mac", "scale": "2x", "size": "32x32",   "filename": "icon_32x32@2x.png"],
    ["idiom": "mac", "scale": "1x", "size": "128x128", "filename": "icon_128x128.png"],
    ["idiom": "mac", "scale": "2x", "size": "128x128", "filename": "icon_128x128@2x.png"],
    ["idiom": "mac", "scale": "1x", "size": "256x256", "filename": "icon_256x256.png"],
    ["idiom": "mac", "scale": "2x", "size": "256x256", "filename": "icon_256x256@2x.png"],
    ["idiom": "mac", "scale": "1x", "size": "512x512", "filename": "icon_512x512.png"],
    ["idiom": "mac", "scale": "2x", "size": "512x512", "filename": "icon_512x512@2x.png"],
  ]
]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: URL(fileURLWithPath: iconsetDir + "/Contents.json"))
print("ok Contents.json updated")

// Also write a 1024px source PNG to .claude/icon.png for the per-project loader
let projectIconImage = render(pixels: 1024)
try? FileManager.default.createDirectory(
  atPath: (projectIconPath as NSString).deletingLastPathComponent,
  withIntermediateDirectories: true
)
try savePNG(projectIconImage, to: projectIconPath)
print("ok .claude/icon.png (1024x1024)")

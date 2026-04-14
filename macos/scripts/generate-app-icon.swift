#!/usr/bin/env swift
// Generates the Notifly AppIcon set programmatically using Core Graphics.
// Run from the project root: swift macos/scripts/generate-app-icon.swift
//
// Renders a rounded-square icon with a vertical purple→pink gradient and a
// centered white "bell" SF Symbol, at every size required by macOS app icons.

import Foundation
import AppKit
import CoreGraphics

let projectRoot = FileManager.default.currentDirectoryPath
let iconsetDir = projectRoot + "/macos/Notifly/Assets.xcassets/AppIcon.appiconset"

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

func render(pixels: Int) -> NSImage {
  let size = CGFloat(pixels)
  let image = NSImage(size: NSSize(width: size, height: size))
  image.lockFocus()
  defer { image.unlockFocus() }

  guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

  // Rounded-square mask (macOS Big Sur+ icon shape uses a corner radius of ~22.5%)
  let cornerRadius = size * 0.225
  let rect = CGRect(x: 0, y: 0, width: size, height: size)
  let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
  ctx.addPath(path)
  ctx.clip()

  // Vertical purple → pink gradient
  let colors = [
    CGColor(red: 0.45, green: 0.16, blue: 0.78, alpha: 1.0),
    CGColor(red: 0.82, green: 0.16, blue: 0.50, alpha: 1.0)
  ] as CFArray
  let colorSpace = CGColorSpaceCreateDeviceRGB()
  let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1])!
  ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: size),
    end: CGPoint(x: 0, y: 0),
    options: []
  )

  // Subtle inner highlight at the top
  let highlight = [
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.18),
    CGColor(red: 1, green: 1, blue: 1, alpha: 0)
  ] as CFArray
  let hg = CGGradient(colorsSpace: colorSpace, colors: highlight, locations: [0, 1])!
  ctx.drawLinearGradient(hg, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: size * 0.55), options: [])

  // Bell glyph (SF Symbol "bell.fill") rendered in white at ~58% of icon size
  let symbolPointSize = size * 0.58
  if let symbol = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: nil) {
    let cfg = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .semibold)
    if let configured = symbol.withSymbolConfiguration(cfg) {
      let symbolSize = configured.size
      let drawRect = NSRect(
        x: (size - symbolSize.width) / 2,
        y: (size - symbolSize.height) / 2 - size * 0.02,
        width: symbolSize.width,
        height: symbolSize.height
      )
      // Tint the symbol white via a separate offscreen draw
      NSColor.white.set()
      let tinted = NSImage(size: configured.size)
      tinted.lockFocus()
      configured.draw(at: .zero, from: NSRect(origin: .zero, size: configured.size), operation: .sourceOver, fraction: 1.0)
      NSColor.white.set()
      NSRect(origin: .zero, size: configured.size).fill(using: .sourceAtop)
      tinted.unlockFocus()
      tinted.draw(in: drawRect)
    }
  }

  return image
}

func savePNG(_ image: NSImage, to path: String) throws {
  guard let tiff = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff),
        let png = rep.representation(using: .png, properties: [:]) else {
    throw NSError(domain: "icon", code: 1)
  }
  try png.write(to: URL(fileURLWithPath: path))
}

print("Generating app icon set into \(iconsetDir)")
try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

for s in sizes {
  let image = render(pixels: s.pixels)
  let path = iconsetDir + "/" + s.filename
  do {
    try savePNG(image, to: path)
    print("  ✓ \(s.filename) (\(s.pixels)×\(s.pixels))")
  } catch {
    print("  ✗ \(s.filename): \(error)")
  }
}

// Update Contents.json with the new filename references
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
print("✓ Contents.json updated")

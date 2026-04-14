#!/usr/bin/env swift
// Generates a 1024x1024 Camp Clintondale app icon featuring Ellie the dog.
// Source: Camp Clintondale guest/public/concierge.jpg (2800x2800 photo of Ellie).
// Crops tightly to Ellie's face and places her on a warm cream rounded-square
// with a teal portrait circle that echoes the original photo's teal tile bg.

import Foundation
import AppKit
import CoreGraphics

let sourcePath = "/Users/jonzanoff/Documents/jonzan0ff/Projects/Camp Clintondale/guest/public/concierge.jpg"
let outPath1 = "/Users/jonzanoff/Documents/jonzan0ff/Projects/Notifly/qa/screenshots/icons/camp-clintondale-source.png"
let outPath2 = "/Users/jonzanoff/Documents/jonzan0ff/Projects/Camp Clintondale/.claude/icon.png"

let size: CGFloat = 1024

guard let source = NSImage(contentsOfFile: sourcePath),
      let sourceCG = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
  fputs("Failed to load source image at \(sourcePath)\n", stderr)
  exit(1)
}

let srcW = CGFloat(sourceCG.width)
let srcH = CGFloat(sourceCG.height)
fputs("Source: \(Int(srcW))x\(Int(srcH))\n", stderr)

// Ellie's face occupies roughly the center-top of the 2800x2800 photo.
// Crop a square around her face: center ~(1400, 1150) from top-left,
// window 1700x1700 so whole face + ears fit.
let cropSize: CGFloat = 1700
let cropCenterX: CGFloat = 1400
let cropCenterYFromTop: CGFloat = 1150
let cropX = cropCenterX - cropSize / 2
let cropYFromTop = cropCenterYFromTop - cropSize / 2
let cropY = srcH - cropYFromTop - cropSize
let cropRect = CGRect(x: cropX, y: cropY, width: cropSize, height: cropSize)
    .intersection(CGRect(x: 0, y: 0, width: srcW, height: srcH))

guard let cropped = sourceCG.cropping(to: cropRect) else {
  fputs("Failed to crop\n", stderr)
  exit(1)
}
fputs("Cropped to \(Int(cropRect.width))x\(Int(cropRect.height))\n", stderr)

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
  data: nil,
  width: Int(size),
  height: Int(size),
  bitsPerComponent: 8,
  bytesPerRow: 0,
  space: colorSpace,
  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
  fputs("Failed to create context\n", stderr)
  exit(1)
}

ctx.setShouldAntialias(true)
ctx.interpolationQuality = .high

// Rounded-square mask (macOS Big Sur+ ~22.5% corner radius)
let cornerRadius = size * 0.225
let fullRect = CGRect(x: 0, y: 0, width: size, height: size)
let roundedPath = CGPath(roundedRect: fullRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

ctx.saveGState()
ctx.addPath(roundedPath)
ctx.clip()

// 1) Warm cream gradient background
let bgColors = [
  CGColor(red: 1.00, green: 0.96, blue: 0.88, alpha: 1.0),
  CGColor(red: 0.99, green: 0.88, blue: 0.74, alpha: 1.0)
] as CFArray
if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0, 1]) {
  ctx.drawLinearGradient(
    bgGradient,
    start: CGPoint(x: 0, y: size),
    end: CGPoint(x: 0, y: 0),
    options: []
  )
}

// 2) Teal portrait circle
let circleInset: CGFloat = size * 0.09
let circleRect = fullRect.insetBy(dx: circleInset, dy: circleInset)
ctx.saveGState()
ctx.addEllipse(in: circleRect)
ctx.clip()

let tealColors = [
  CGColor(red: 0.28, green: 0.72, blue: 0.73, alpha: 1.0),
  CGColor(red: 0.15, green: 0.55, blue: 0.60, alpha: 1.0)
] as CFArray
if let tealGradient = CGGradient(colorsSpace: colorSpace, colors: tealColors, locations: [0, 1]) {
  ctx.drawLinearGradient(
    tealGradient,
    start: CGPoint(x: 0, y: size),
    end: CGPoint(x: 0, y: 0),
    options: []
  )
}

// 3) Draw Ellie inside the circle
let ellieInset: CGFloat = size * 0.02
let ellieRect = circleRect.insetBy(dx: ellieInset, dy: ellieInset)
ctx.draw(cropped, in: ellieRect)

ctx.restoreGState() // end circle clip

// 4) White ring around circle
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.setLineWidth(size * 0.025)
ctx.strokeEllipse(in: circleRect)

// 5) Subtle inner teal outline
ctx.setStrokeColor(CGColor(red: 0.13, green: 0.50, blue: 0.55, alpha: 0.9))
ctx.setLineWidth(size * 0.008)
ctx.strokeEllipse(in: circleRect.insetBy(dx: size * 0.016, dy: size * 0.016))

ctx.restoreGState() // end rounded-square clip

// 6) Subtle outer edge stroke
ctx.saveGState()
ctx.addPath(roundedPath)
ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.12))
ctx.setLineWidth(2)
ctx.strokePath()
ctx.restoreGState()

guard let outImage = ctx.makeImage() else {
  fputs("Failed to make image\n", stderr)
  exit(1)
}

func writePNG(_ image: CGImage, to path: String) {
  let url = URL(fileURLWithPath: path)
  let rep = NSBitmapImageRep(cgImage: image)
  guard let data = rep.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode PNG for \(path)\n", stderr)
    exit(1)
  }
  do {
    try data.write(to: url)
    fputs("Wrote \(path)\n", stderr)
  } catch {
    fputs("Failed to write \(path): \(error)\n", stderr)
    exit(1)
  }
}

writePNG(outImage, to: outPath1)
writePNG(outImage, to: outPath2)
fputs("Done.\n", stderr)

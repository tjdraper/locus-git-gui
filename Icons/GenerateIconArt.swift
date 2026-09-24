import CoreGraphics
import Foundation

// Single source of geometry: the glass rings and branch lines are drawn around the
// same commit positions as the colored discs above them, so they can never drift apart.
struct Commit {
    let center: CGPoint
    let color: String
}

let bandHeight: CGFloat = 435
let discRadius: CGFloat = 86
let ringWidth: CGFloat = 46
let lineWidth: CGFloat = 60

let trunkX: CGFloat = 300
let root = Commit(center: CGPoint(x: trunkX, y: 790), color: "rgb(74,144,217)")
let mainHead = Commit(center: CGPoint(x: trunkX, y: 270), color: "rgb(61,200,114)")
let featureHead = Commit(center: CGPoint(x: 724, y: 270), color: "rgb(240,112,32)")
let commits = [root, mainHead, featureHead]
// The branch drops straight through the band's edge before it bends. Glass crossing
// the edge at a shallow angle refracts it into a long streak along the curve.
let branchBendY = bandHeight + 50
let branchJoinY: CGFloat = 670

func svg(_ body: String) -> String {
    """
    <?xml version="1.0" encoding="UTF-8" standalone="no"?>
    <svg width="100%" height="100%" viewBox="0 0 1024 1024" version="1.1" xmlns="http://www.w3.org/2000/svg">
    \(body)
    </svg>

    """
}

func write(_ contents: String, _ name: String) {
    try! contents.write(toFile: name, atomically: true, encoding: .utf8)
}

func background(field: String, band: String) -> String {
    svg("""
        <rect x="0" y="0" width="1024" height="1024" style="fill:\(field);"/>
        <rect x="0" y="0" width="1024" height="\(Int(bandHeight))" style="fill:\(band);"/>
    """)
}

func pathData(_ path: CGPath) -> String {
    func point(_ p: CGPoint) -> String {
        String(format: "%.2f %.2f", p.x, p.y)
    }
    var parts: [String] = []
    path.applyWithBlock { element in
        let points = element.pointee.points
        switch element.pointee.type {
        case .moveToPoint: parts.append("M\(point(points[0]))")
        case .addLineToPoint: parts.append("L\(point(points[0]))")
        case .addQuadCurveToPoint: parts.append("Q\(point(points[0])) \(point(points[1]))")
        case .addCurveToPoint: parts.append("C\(point(points[0])) \(point(points[1])) \(point(points[2]))")
        case .closeSubpath: parts.append("Z")
        @unknown default: break
        }
    }
    return parts.joined(separator: " ")
}

write(background(field: "rgb(224,184,122)", band: "rgb(178,40,72)"), "background-light.svg")
write(background(field: "rgb(58,30,10)", band: "rgb(106,24,43)"), "background-dark.svg")

write(svg(commits.map {
    "    <circle cx=\"\(Int($0.center.x))\" cy=\"\(Int($0.center.y))\" r=\"\(Int(discRadius))\" style=\"fill:\($0.color);\"/>"
}.joined(separator: "\n")), "commits.svg")

// Icon Composer shapes glass from the filled area of each path, so an open stroked
// curve gains a phantom chord between its ends. The glyph is written as one filled outline.
let ringRadius = discRadius + ringWidth / 2
let rings = CGMutablePath()
for commit in commits {
    rings.addEllipse(in: CGRect(x: commit.center.x - ringRadius, y: commit.center.y - ringRadius,
                                width: ringRadius * 2, height: ringRadius * 2))
}

let branchStartY = featureHead.center.y + ringRadius
let bend = (branchJoinY - branchBendY) * 0.75
let lines = CGMutablePath()
lines.move(to: CGPoint(x: trunkX, y: mainHead.center.y + ringRadius))
lines.addLine(to: CGPoint(x: trunkX, y: root.center.y - ringRadius))
lines.move(to: CGPoint(x: featureHead.center.x, y: branchStartY))
lines.addLine(to: CGPoint(x: featureHead.center.x, y: branchBendY))
lines.addCurve(to: CGPoint(x: trunkX, y: branchJoinY),
               control1: CGPoint(x: featureHead.center.x, y: branchBendY + bend),
               control2: CGPoint(x: trunkX, y: branchJoinY - bend))

let glyph = rings.copy(strokingWithWidth: ringWidth, lineCap: .butt, lineJoin: .round, miterLimit: 10)
    .union(lines.copy(strokingWithWidth: lineWidth, lineCap: .round, lineJoin: .round, miterLimit: 10))
write(svg("""
    <path d="\(pathData(glyph))" style="fill:rgb(255,255,255);fill-rule:evenodd;"/>
"""), "branches.svg")

// Run from the icon's Assets folder:
// swift ../../Icons/GenerateIconArt.swift

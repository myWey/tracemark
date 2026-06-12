import SwiftUI

public struct SVGPathParser {
    public static func parse(_ pathString: String) -> Path {
        var path = Path()
        let scanner = Scanner(string: pathString)
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: " ,\n\r\t")
        
        var currentPoint = CGPoint.zero
        var lastCommand: Character = " "
        var lastControlPoint: CGPoint? = nil
        
        while !scanner.isAtEnd {
            // Skip spaces to peek
            scanner.charactersToBeSkipped = nil
            _ = scanner.scanCharacters(from: CharacterSet(charactersIn: " ,\n\r\t"))
            scanner.charactersToBeSkipped = CharacterSet(charactersIn: " ,\n\r\t")
            
            guard !scanner.isAtEnd else { break }
            
            let index = scanner.currentIndex
            let nextChar = scanner.string[index]
            let isNumber = CharacterSet(charactersIn: "-+.0123456789").contains(nextChar.unicodeScalars.first!)
            
            var char: Character
            if isNumber && lastCommand != " " && lastCommand.uppercased() != "Z" {
                char = lastCommand == "M" ? "L" : (lastCommand == "m" ? "l" : lastCommand)
            } else {
                guard let scanned = scanner.scanCharacter() else { break }
                char = scanned
            }
            lastCommand = char
            
            let isRelative = char.isLowercase
            let command = char.uppercased()
            
            var currentControlPoint: CGPoint? = nil
            
            switch command {
            case "M":
                if let x = scanner.scanDouble(), let y = scanner.scanDouble() {
                    let dest = isRelative ? CGPoint(x: currentPoint.x + CGFloat(x), y: currentPoint.y + CGFloat(y)) : CGPoint(x: CGFloat(x), y: CGFloat(y))
                    path.move(to: dest)
                    currentPoint = dest
                }
            case "L":
                if let x = scanner.scanDouble(), let y = scanner.scanDouble() {
                    let dest = isRelative ? CGPoint(x: currentPoint.x + CGFloat(x), y: currentPoint.y + CGFloat(y)) : CGPoint(x: CGFloat(x), y: CGFloat(y))
                    path.addLine(to: dest)
                    currentPoint = dest
                }
            case "H":
                if let x = scanner.scanDouble() {
                    let dest = isRelative ? CGPoint(x: currentPoint.x + CGFloat(x), y: currentPoint.y) : CGPoint(x: CGFloat(x), y: currentPoint.y)
                    path.addLine(to: dest)
                    currentPoint = dest
                }
            case "V":
                if let y = scanner.scanDouble() {
                    let dest = isRelative ? CGPoint(x: currentPoint.x, y: currentPoint.y + CGFloat(y)) : CGPoint(x: currentPoint.x, y: CGFloat(y))
                    path.addLine(to: dest)
                    currentPoint = dest
                }
            case "C":
                if let x1 = scanner.scanDouble(), let y1 = scanner.scanDouble(),
                   let x2 = scanner.scanDouble(), let y2 = scanner.scanDouble(),
                   let x = scanner.scanDouble(), let y = scanner.scanDouble() {
                    let cp1 = isRelative ? CGPoint(x: currentPoint.x + CGFloat(x1), y: currentPoint.y + CGFloat(y1)) : CGPoint(x: CGFloat(x1), y: CGFloat(y1))
                    let cp2 = isRelative ? CGPoint(x: currentPoint.x + CGFloat(x2), y: currentPoint.y + CGFloat(y2)) : CGPoint(x: CGFloat(x2), y: CGFloat(y2))
                    let dest = isRelative ? CGPoint(x: currentPoint.x + CGFloat(x), y: currentPoint.y + CGFloat(y)) : CGPoint(x: CGFloat(x), y: CGFloat(y))
                    path.addCurve(to: dest, control1: cp1, control2: cp2)
                    currentPoint = dest
                    currentControlPoint = cp2
                }
            case "S":
                if let x2 = scanner.scanDouble(), let y2 = scanner.scanDouble(),
                   let x = scanner.scanDouble(), let y = scanner.scanDouble() {
                    let cp2 = isRelative ? CGPoint(x: currentPoint.x + CGFloat(x2), y: currentPoint.y + CGFloat(y2)) : CGPoint(x: CGFloat(x2), y: CGFloat(y2))
                    let dest = isRelative ? CGPoint(x: currentPoint.x + CGFloat(x), y: currentPoint.y + CGFloat(y)) : CGPoint(x: CGFloat(x), y: CGFloat(y))
                    let cp1 = lastControlPoint.map { CGPoint(x: 2 * currentPoint.x - $0.x, y: 2 * currentPoint.y - $0.y) } ?? currentPoint
                    path.addCurve(to: dest, control1: cp1, control2: cp2)
                    currentPoint = dest
                    currentControlPoint = cp2
                }
            case "Q":
                if let x1 = scanner.scanDouble(), let y1 = scanner.scanDouble(),
                   let x = scanner.scanDouble(), let y = scanner.scanDouble() {
                    let cp = isRelative ? CGPoint(x: currentPoint.x + CGFloat(x1), y: currentPoint.y + CGFloat(y1)) : CGPoint(x: CGFloat(x1), y: CGFloat(y1))
                    let dest = isRelative ? CGPoint(x: currentPoint.x + CGFloat(x), y: currentPoint.y + CGFloat(y)) : CGPoint(x: CGFloat(x), y: CGFloat(y))
                    path.addQuadCurve(to: dest, control: cp)
                    currentPoint = dest
                }
            case "A":
                if let rx = scanner.scanDouble(), let ry = scanner.scanDouble(),
                   let xAxisRot = scanner.scanDouble(),
                   let largeArc = scanner.scanDouble(),
                   let sweep = scanner.scanDouble(),
                   let x = scanner.scanDouble(), let y = scanner.scanDouble() {
                    let dest = isRelative ? CGPoint(x: currentPoint.x + CGFloat(x), y: currentPoint.y + CGFloat(y)) : CGPoint(x: CGFloat(x), y: CGFloat(y))
                    path.addSvgArc(rx: CGFloat(rx), ry: CGFloat(ry), xAxisRotation: CGFloat(xAxisRot), largeArcFlag: largeArc > 0, sweepFlag: sweep > 0, to: dest, from: currentPoint)
                    currentPoint = dest
                }
            case "Z":
                path.closeSubpath()
            default:
                break
            }
            
            lastControlPoint = currentControlPoint
        }
        return path
    }
}

extension Path {
    public mutating func addSvgArc(rx: CGFloat, ry: CGFloat, xAxisRotation: CGFloat, largeArcFlag: Bool, sweepFlag: Bool, to: CGPoint, from: CGPoint) {
        if rx == 0 || ry == 0 {
            self.addLine(to: to)
            return
        }
        
        let rX = abs(rx)
        let rY = abs(ry)
        
        let phi = xAxisRotation * .pi / 180.0
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)
        
        // Step 1: Compute (x1', y1')
        let dx = (from.x - to.x) / 2.0
        let dy = (from.y - to.y) / 2.0
        let x1Prime = cosPhi * dx + sinPhi * dy
        let y1Prime = -sinPhi * dx + cosPhi * dy
        
        // Step 2: Compute (cx', cy')
        var rxSq = rX * rX
        var rySq = rY * rY
        let x1PrimeSq = x1Prime * x1Prime
        let y1PrimeSq = y1Prime * y1Prime
        
        let radiiCheck = x1PrimeSq / rxSq + y1PrimeSq / rySq
        var currentRx = rX
        var currentRy = rY
        if radiiCheck > 1.0 {
            currentRx = sqrt(radiiCheck) * rX
            currentRy = sqrt(radiiCheck) * rY
            rxSq = currentRx * currentRx
            rySq = currentRy * currentRy
        }
        
        let sign: CGFloat = (largeArcFlag == sweepFlag) ? -1.0 : 1.0
        var sq = ((rxSq * rySq) - (rxSq * y1PrimeSq) - (rySq * x1PrimeSq)) / ((rxSq * y1PrimeSq) + (rySq * x1PrimeSq))
        sq = max(0, sq)
        let coef = sign * sqrt(sq)
        let cxPrime = coef * ((currentRx * y1Prime) / currentRy)
        let cyPrime = coef * -((currentRy * x1Prime) / currentRx)
        
        // Step 3: Compute (cx, cy)
        let cx = cosPhi * cxPrime - sinPhi * cyPrime + (from.x + to.x) / 2.0
        let cy = sinPhi * cxPrime + cosPhi * cyPrime + (from.y + to.y) / 2.0
        
        // Step 4: Compute theta1 and deltaTheta
        let ux = (x1Prime - cxPrime) / currentRx
        let uy = (y1Prime - cyPrime) / currentRy
        let vx = (-x1Prime - cxPrime) / currentRx
        let vy = (-y1Prime - cyPrime) / currentRy
        
        let angleOf = { (uX: CGFloat, uY: CGFloat) -> CGFloat in
            let dot = uX
            let len = sqrt(uX * uX + uY * uY)
            var ang = acos(max(-1.0, min(1.0, dot / len)))
            if uY < 0 { ang = -ang }
            return ang
        }
        
        let theta1 = angleOf(ux, uy)
        
        let dotProduct = ux * vx + uy * vy
        let lenU = sqrt(ux * ux + uy * uy)
        let lenV = sqrt(vx * vx + vy * vy)
        var dTheta = acos(max(-1.0, min(1.0, dotProduct / (lenU * lenV))))
        if (ux * vy - uy * vx) < 0 { dTheta = -dTheta }
        
        if !sweepFlag && dTheta > 0 {
            dTheta -= 2.0 * .pi
        } else if sweepFlag && dTheta < 0 {
            dTheta += 2.0 * .pi
        }
        
        var t = CGAffineTransform.identity
        t = t.translatedBy(x: cx, y: cy)
        t = t.rotated(by: phi)
        t = t.scaledBy(x: currentRx, y: currentRy)
        
        let segments = Int(ceil(abs(dTheta) / (.pi / 2.0)))
        for i in 0..<segments {
            let startAng = theta1 + CGFloat(i) * dTheta / CGFloat(segments)
            let endAng = theta1 + CGFloat(i + 1) * dTheta / CGFloat(segments)
            
            let alpha = sin(endAng - startAng) * (sqrt(4.0 + 3.0 * pow(tan((endAng - startAng) / 2.0), 2)) - 1.0) / 3.0
            
            let p1 = CGPoint(x: cos(startAng), y: sin(startAng))
            let p2 = CGPoint(x: cos(endAng), y: sin(endAng))
            
            let q1 = CGPoint(x: p1.x - alpha * sin(startAng), y: p1.y + alpha * cos(startAng))
            let q2 = CGPoint(x: p2.x + alpha * sin(endAng), y: p2.y - alpha * cos(endAng))
            
            let transformedDest = p2.applying(t)
            let transformedCP1 = q1.applying(t)
            let transformedCP2 = q2.applying(t)
            
            self.addCurve(to: transformedDest, control1: transformedCP1, control2: transformedCP2)
        }
    }
    
    public func scaled(toFit size: CGSize, originalSize: CGSize) -> Path {
        let scaleX = size.width / originalSize.width
        let scaleY = size.height / originalSize.height
        let scale = min(scaleX, scaleY)
        
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        return self.applying(transform)
    }
}

public struct SVGIconView: View {
    let pathData: String
    let color: Color
    
    public init(pathData: String, color: Color) {
        self.pathData = pathData
        self.color = color
    }
    
    public var body: some View {
        let path = SVGPathParser.parse(pathData)
        path
            .scaled(toFit: CGSize(width: 14, height: 14), originalSize: CGSize(width: 1024, height: 1024))
            .fill(color)
            .aspectRatio(1.0, contentMode: .fit)
    }
}

public struct SVGPaths {
    public static let highlighter = "M1014.624 425.376a32 32 0 0 0-45.28 0L768 626.72 429.248 288l201.376-201.344a32.032 32.032 0 0 0-45.28-45.28L384 242.752a64 64 0 0 0-11.264 75.264L288 402.752a64 64 0 0 0 0 90.496l18.752 18.752-233.376 233.376a32 32 0 0 0 12.48 52.992l288 96a32 32 0 0 0 32.768-7.712L544 749.216l18.752 18.752a64 64 0 0 0 90.496 0l84.704-84.736A64 64 0 0 0 813.248 672l201.376-201.376a32 32 0 0 0 0-45.28zM608 722.72L333.248 448 416 365.248 690.752 640 608 722.752z"
    public static let pencil = "M818.346667 352.853333l-202.837334-188.16 56.490667-60.885333 202.837333 188.16zM438.741333 762.197333l-202.922666-188.245333 360.874666-388.949333 202.88 188.245333zM217.002667 594.218667l202.922666 188.288-270.890666 88.448zM747.648 98.56l126.805333 117.632c20.992 19.498667 21.162667 53.504 0.426667 75.861333-20.821333 22.442667-54.698667 24.746667-75.690667 5.290667L672.384 179.626667c-21.034667-19.498667-21.205333-53.504-0.426667-75.861334 20.821333-22.4 54.698667-24.746667 75.690667-5.290666z"
    
    public static let mosaic = "M85.333333 106.666667h170.666667v170.666666H85.333333V106.666667z m341.333334 170.666666v170.666667h-170.666667v-170.666667h170.666667z m-170.666667 341.333334H85.333333v-170.666667h170.666667v170.666667z m170.666667 0h-170.666667v149.333333H85.333333v170.666667h170.666667v-149.333334h170.666667v149.333334h170.666666v-149.333334h170.666667v149.333334h170.666667v-170.666667h-170.666667v-149.333333h170.666667v-170.666667h-170.666667v-170.666667h170.666667V106.666667h-170.666667v170.666666h-170.666667V106.666667h-170.666666v170.666666h170.666666v170.666667h-170.666666v170.666667z m170.666666 0h-170.666666v149.333333h170.666666v-149.333333z m0-170.666667v170.666667h170.666667v-170.666667h-170.666667z"
    
    public static let spotlight = "M213.333333 85.333333h682.666667v853.333334H128V85.333333h85.333333z m597.333334 768V170.666667H213.333333v682.666666h597.333334zM554.666667 256H298.666667v85.333333h256V256z m-256 170.666667h426.666666v341.333333H298.666667v-341.333333z"
}

extension NSCursor {
    public static var transparent: NSCursor {
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.clear.set()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        image.unlockFocus()
        return NSCursor(image: image, hotSpot: NSPoint.zero)
    }
}

//
//  NSBezierPath+Geometry.swift
//  SwiftDrawKit
//
//  Created by Colin Wilson on 14/02/2019.
//  Copyright © 2019 Colin Wilson. All rights reserved.
//

import Cocoa

func Slope(_ a: NSPoint, _ b: NSPoint) -> CGFloat {
    // returns the slope of a line given its end points, in radians
    
    return atan2(b.y - a.y, b.x - a.x);
}


extension NSBezierPath {
    
    struct CubicBezier {
        var p1: CGPoint
        var c1 : CGPoint
        var c2 : CGPoint
        var p2: CGPoint
    }
    
    static let DEFAULT_TRIM_EPSILON = CGFloat (0.1)
    
    public var length: CGFloat {
        return lengthWithMaximumError (maxError: NSBezierPath.DEFAULT_TRIM_EPSILON)
    }
    
    public var slopeStartingPath: CGFloat {
        
        if elementCount > 1 {
            var ap = [NSPoint] (repeating: NSZeroPoint, count: 3)
            var lp = [NSPoint] (repeating: NSZeroPoint, count: 3)
            
            element(at: 0, associatedPoints: &ap)
            element(at: 1, associatedPoints: &lp)
            
            return Slope (ap [0], lp [0])
        }
        return 0
    }
    
    func lengthWithMaximumError (maxError : CGFloat) -> CGFloat {

        var rv = CGFloat (0)
        var points = [NSPoint] (repeating: NSPoint (x: 0, y: 0), count: 10)
        let pointArray = NSPointArray (mutating: &points)
        var pointForClose = NSPoint (x: 0, y: 0)
        var lastPoint = NSPoint (x: 0, y: 0)

        for elementNo in 0 ..< elementCount {
            let elementType = element(at: elementNo, associatedPoints: pointArray)
            
            switch elementType {
            case .moveTo:
                pointForClose = pointArray [0]
                lastPoint = pointForClose
            case .lineTo:
                rv += lastPoint.distanceFrom(other: pointArray [0])
                lastPoint = pointArray [0]
            case .curveTo:
                let bezier = CubicBezier (p1: lastPoint, c1: pointArray [0], c2: pointArray [1], p2: pointArray [2])
                rv += NSBezierPath.lengthOfBezier (bezier, acceptableError: maxError)
                lastPoint = pointArray [2]
            case .closePath:
                rv += lastPoint.distanceFrom(other: pointForClose)
                lastPoint = pointForClose
            }
        }
        return rv
    }
    
    static func lengthOfBezier (_ bezier: CubicBezier, acceptableError: CGFloat) -> CGFloat {
        let chordLen = bezier.p1.distanceFrom (other: bezier.p2)
        let polyLen = bezier.p1.distanceFrom(other: bezier.c1) + bezier.c1.distanceFrom(other: bezier.c2) + bezier.c2.distanceFrom(other: bezier.p2)
        let errLen = polyLen - chordLen

        let retLen : CGFloat
        if errLen > acceptableError {
            let lr = subdivideBezier (bezier)
            retLen = lengthOfBezier(lr.left, acceptableError: acceptableError) + lengthOfBezier(lr.right, acceptableError: acceptableError)
        } else {
            retLen = (polyLen + chordLen) * 0.5
        }
        
        return retLen
    }
    
    static func subdivideBezier (_ bezier: CubicBezier) -> (left:CubicBezier, right:CubicBezier) {
        let q = NSPoint (x: (bezier.c1.x + bezier.c2.x) / 2, y: (bezier.c1.y + bezier.c2.y) / 2)
        
        var left = CubicBezier (
            p1: bezier.p1,
            c1: CGPoint (x:(bezier.p1.x + bezier.c1.x) / 2, y: (bezier.p1.y + bezier.c1.y) / 2),
            c2: NSZeroPoint,
            p2: NSZeroPoint)
        
        var right = CubicBezier (
            p1: NSZeroPoint,
            c1: NSZeroPoint,
            c2: CGPoint (x:(bezier.c2.x + bezier.p2.x) / 2, y:(bezier.c2.y + bezier.p2.y) / 2),
            p2: bezier.p2)
        
        left.c2 = CGPoint (x: (left.c1.x + q.x) / 2, y: (left.c1.y + q.y) / 2)
        right.c1 = CGPoint (x: (q.x + right.c2.x) / 2, y: (q.y + right.c2.y) / 2)
        
        left.p2 = CGPoint (x: (left.c2.x + right.c1.x) / 2, y: (left.c2.y + right.c1.y) / 2)
        right.p1 = left.p2
        
        return (left, right)
    }
    
    static func subdivideBezier (_ bezier: CubicBezier, at t:CGFloat) -> (left:CubicBezier, right:CubicBezier) {
        let mt = 1-t
        let q = NSPoint (x: mt * bezier.c1.x + t * bezier.c2.x, y: mt * bezier.c1.y + t * bezier.c2.y)
        
        var left = CubicBezier (
            p1: bezier.p1,
            c1: CGPoint (x:mt * bezier.p1.x + t * bezier.c1.x, y: mt * bezier.p1.y + t * bezier.c1.y),
            c2: NSZeroPoint,
            p2: NSZeroPoint)
        
        var right = CubicBezier (
            p1: NSZeroPoint,
            c1: NSZeroPoint,
            c2: CGPoint (x:mt * bezier.c2.x + t * bezier.p2.x, y:mt * bezier.c2.y + t * bezier.p2.y),
            p2: bezier.p2)
        
        left.c2 = CGPoint (x: mt * left.c1.x + t * q.x, y: mt * left.c1.y + t * q.y)
        right.c1 = CGPoint (x: mt * q.x + t * right.c2.x, y: mt * q.y + t * right.c2.y)
        
        left.p2 = CGPoint (x: mt * left.c2.x + t * right.c1.x, y: mt * left.c2.y + t * right.c1.y)
        right.p1 = left.p2
        
        return (left, right)
    }

    
    static func subdivideBezier (_ bez: CubicBezier, atLength length: CGFloat, withAcceptableError acceptableError: CGFloat) -> (left:CubicBezier, right:CubicBezier, len1: CGFloat) {
        var t = CGFloat (0.5)
        var prev_t = t
        var bottom = CGFloat (0)
        var top = CGFloat (1)
        
        repeat {
            
            let lr = subdivideBezier(bez, at:t)
            let len1 = lengthOfBezier(lr.left, acceptableError: acceptableError)
            
            if abs (length - len1) < acceptableError {
                return (lr.left, lr.right, len1)
            }
            
            if length > len1 {
                bottom = t
                t = 0.5 * (t + top)
            } else if length < len1 {
                top = t
                t = 0.5 * (bottom+t)
            }
            
            if t == prev_t {
                return (lr.left, lr.right, len1)
            }
            
            prev_t = t
        } while true
    }
    
    
    func bezierPathByTrimmingFromLength ( _ trimLength : CGFloat) -> NSBezierPath {
        return bezierPathByTrimmingFromLength(trimLength, withMaximumError: NSBezierPath.DEFAULT_TRIM_EPSILON)
    }
    
    func bezierPathByTrimmingFromLength ( _ trimLength : CGFloat, withMaximumError maxError: CGFloat) -> NSBezierPath {
        if trimLength <= 0 {
            return self
        }
        
        let newPath = NSBezierPath ()
        var points = [NSPoint] (repeating: NSZeroPoint, count: 3)
        var length = CGFloat (0)
        var lastPoint = NSZeroPoint
        var pointForClose = NSZeroPoint

        for elementNo in 0 ..< elementCount {
            
            let remainingLength = trimLength - length

            switch element(at: elementNo, associatedPoints: &points) {
            case .moveTo:
                if length > trimLength {
                    newPath.move(to: points [0])
                }
                pointForClose = points [0]
                lastPoint = pointForClose
                
            case .lineTo:
                let elementLength = lastPoint.distanceFrom(other: points [0])
                
                if length > trimLength {
                    newPath.line(to: points [0])
                } else if length + elementLength > trimLength {
                    let f = remainingLength / elementLength
                    newPath.move(to: NSMakePoint (lastPoint.x + f * (points[0].x - lastPoint.x), lastPoint.y + f * (points[0].y - lastPoint.y)))
                    newPath.line(to: points [0])
                }
                length += elementLength
                lastPoint = points [0]
                
            case .curveTo:
                let bez = CubicBezier (p1: lastPoint, c1: points [0], c2: points [1], p2: points [2])
                let elementLength = NSBezierPath.lengthOfBezier(bez, acceptableError: maxError)
                
                if length > trimLength {
                    newPath.curve(to: points [2], controlPoint1: points [0], controlPoint2: points [1])
                } else if length + elementLength > trimLength {
                    let lr = NSBezierPath.subdivideBezier(bez, atLength:remainingLength, withAcceptableError:maxError)
                    newPath.move(to: lr.right.p1)
                    newPath.curve(to: lr.right.p2, controlPoint1: lr.right.c1, controlPoint2: lr.right.c2)
                }
                length += elementLength
                lastPoint = points [2]

            case .closePath:
                let elementLength = lastPoint.distanceFrom(other: pointForClose)
                
                if length > trimLength {
                    newPath.line(to: pointForClose)
                    newPath.close()
                } else if length + elementLength > trimLength {
                    let f = remainingLength / elementLength
                    newPath.move(to: NSMakePoint(lastPoint.x + f * (points [0].x - lastPoint.x), lastPoint.y + f * (points [0].y - lastPoint.y)))
                    newPath.line(to: points [0])
                }
                
                length += elementLength
                lastPoint = pointForClose
            }
        }
        
        return newPath
    }
    
    var checksum: Int {
        var cs = 157145267
        var ec = elementCount
        cs ^= (ec << 5)
        
        var p = [NSPoint] (repeating: NSZeroPoint, count: 3)
        
        if !self.isEmpty {
            for i in 0 ..< elementCount {
                p [1] = NSZeroPoint
                p [2] = NSZeroPoint
                let element = Int (self.element(at: i, associatedPoints: &p).rawValue)
                ec = (element << 10) ^ lround (Double(p[0].x)) ^ lround(Double(p[1].x)) ^ lround (Double(p[2].x)) ^ lround (Double(p[0].y)) ^ lround (Double(p [1].y)) ^ lround (Double(p[2].y))
                cs ^= ec
            }
        }
        return cs
    }
}

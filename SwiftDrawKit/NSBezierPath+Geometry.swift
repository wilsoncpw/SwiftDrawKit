//
//  NSBezierPath+Geometry.swift
//  SwiftDrawKit
//
//  Created by Colin Wilson on 14/02/2019.
//  Copyright © 2019 Colin Wilson. All rights reserved.
//

import Cocoa

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
}

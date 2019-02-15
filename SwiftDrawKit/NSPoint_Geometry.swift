//
//  NSPoint_Geometry.swift
//  SwiftDrawKit
//
//  Created by Colin Wilson on 14/02/2019.
//  Copyright © 2019 Colin Wilson. All rights reserved.
//

import Foundation

extension NSPoint {
    func distanceFrom (other: CGPoint) -> CGFloat {
        let dx = other.x-x
        let dy = other.y-y
        let dx2 = dx*dx
        let dy2 = dy*dy
        return abs(sqrt (dx2+dy2))
    }
}

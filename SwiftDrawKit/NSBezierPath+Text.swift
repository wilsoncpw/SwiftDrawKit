//
//  NSBezierPath+Text.swift
//  SwiftDrawKit
//
//  Created by Colin Wilson on 13/02/2019.
//  Copyright © 2019 Colin Wilson. All rights reserved.
//

import Cocoa

public extension NSBezierPath {
    
    enum error: Error {
        case NoTextContainerInLM
    }
    
    static let kDKTextOnPathChecksumCacheKey = "DKTextOnPathChecksum"
    static let kDKTextOnPathGlyphPositionsCacheKey = "DKTextOnPathGlyphPositions"
    static let kDKTextOnPathTextFittedCacheKey = "DKTextOnPathTextFitted"
    static var topLayoutMgr: NSLayoutManager?
    
    typealias AttributesDictionary = [NSAttributedString.Key: Any]
    
    public class Cache {
        var cache = [String: Any] ()
        public init () {}
    }


    static var textOnPathLayoutManager : NSLayoutManager {
        // returns a layout manager instance which is used for all text on path layout tasks. Reusing this shared instance saves a little time and memory
        
        
        if topLayoutMgr == nil {
            let layoutMgr = NSLayoutManager ()
            let tc = NSTextContainer (containerSize: NSSize (width: 1.0e6, height:1.0e6))
            layoutMgr.addTextContainer(tc)
            layoutMgr.usesScreenFonts = false
            topLayoutMgr = layoutMgr
        }
        
        return topLayoutMgr!
    }
    
    
    static var s_TOPTextAttributes: AttributesDictionary?
    
    static var textOnPathDefaultAttributes: AttributesDictionary {
        get {
            if s_TOPTextAttributes == nil {
                let font = NSFont (name: "Helvetica", size: 12.0)!
                let topTextAttributes = [NSAttributedString.Key.font:font]
                s_TOPTextAttributes = topTextAttributes
            }
            return s_TOPTextAttributes!
        }
        set {
            s_TOPTextAttributes = newValue
        }
    }
    
    public func drawStringOnPath (_ str: String) -> Bool {
        return drawStringOnPath(str, attributes: nil)
    }
    
    public func drawStringOnPath (_ str: String, attributes: AttributesDictionary?) -> Bool {
        let attrs = attributes == nil ? NSBezierPath.textOnPathDefaultAttributes : attributes!
        
        let atst = NSAttributedString (string: str, attributes: attrs)
        
        return drawTextOnPath(atst, yoffset: 0)
    }
    
    public func drawTextOnPath (_ str: NSAttributedString, yoffset dy: CGFloat) -> Bool {
        return (try? drawTextOnPath(str, yOffset: dy, layoutManager: nil, cache: nil)) ?? false
    }
    
    public func drawTextOnPath (_ str: NSAttributedString, yOffset dy: CGFloat, layoutManager lm: NSLayoutManager?, cache: Cache?) throws -> Bool {
        
        if let cache = cache {
            let hv = checksum
            let cs = cache.cache [NSBezierPath.kDKTextOnPathChecksumCacheKey] as? Int
            if cs != hv {
                cache.cache.removeAll()
                cache.cache [NSBezierPath.kDKTextOnPathChecksumCacheKey] = hv
            }
            
        }
        
        let usingStandardLM = lm == nil
        let layoutManager = usingStandardLM ? NSBezierPath.textOnPathLayoutManager : lm!
        
        let text = try preadjustedTextStorageWithString (str, layoutManager: layoutManager)
        
        drawUnderlinePathForLayoutManager (layoutManager, yOffset: dy, cache: cache)
        
        text.removeAttribute(.underlineStyle, range: NSMakeRange(0, text.length))
        text.removeAttribute(.strikethroughStyle, range: NSMakeRange(0, text.length))
        
        let glyphDrawer = DKTextOnPathGlyphDrawer ()
        
        let rv = layoutStringOnPath (text, yOffset:dy, usingLayoutHelper:glyphDrawer, layoutManager:layoutManager, cache: cache)
        
        return rv
    }
    
    func preadjustedTextStorageWithString (_ str: NSAttributedString, layoutManager lm: NSLayoutManager) throws -> NSTextStorage {
        guard let tc = lm.textContainers.last else {
            throw error.NoTextContainerInLM
        }
        
        let autoKern: Bool
        if let para = str.attribute(NSAttributedString.Key.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle {
            autoKern = para.alignment == .justified
        } else {
            autoKern = false
        }
        
        let text = NSTextStorage (attributedString: str)
        text.addLayoutManager(lm)
        let pathLength = length
        
        tc.containerSize = NSSize (width: pathLength, height: 50000)
        
        if autoKern {
            kernText (text, toFit:pathLength)
        }
        return text
    }
    
    func kernText (_ text: NSTextStorage, toFit length: CGFloat) {
        let lm = text.layoutManagers.last!
        let tc = lm.textContainers.last!
        
        let gbr = NSRect (origin: NSZeroPoint, size: CGSize (width: length, height: 50000))
        tc.containerSize = gbr.size
        
        let glyphRange = lm.glyphRange(forBoundingRect: gbr, in: tc)
        let fragRect = lm.lineFragmentUsedRect(forGlyphAt: 0, effectiveRange: nil)
        var kernAmount = (gbr.size.width - fragRect.size.width) / CGFloat(glyphRange.length - 1)
        
        if kernAmount <= 0 {
            let strSize = text.size()
            
            kernAmount = (gbr.size.width - strSize.width) / CGFloat(glyphRange.length - 1)
            
            let kernLimit = strSize.height * -0.15
            
            if kernAmount < kernLimit {
                kernAmount = kernLimit
            }
        }
        
        let kernAttributes = [NSAttributedString.Key.kern:kernAmount]
        let charRange = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        text.addAttributes(kernAttributes, range: charRange)
    }
    
    func drawUnderlinePathForLayoutManager (_ lm: NSLayoutManager, yOffset dy: CGFloat, cache: Cache?) {
        guard let textStorage = lm.textStorage else {
            return
        }
        
        var effectiveRange = NSMakeRange(0, 0)
        var rangeLimit = 0
        
        while rangeLimit < textStorage.length {
            let al = textStorage.attribute(.underlineStyle, at: rangeLimit, effectiveRange: &effectiveRange)
            if let ul = al as? NSNumber, ul.intValue > 0 {
                drawUnderlinePathForLayoutManager(lm, range: effectiveRange, yOffset: dy, cache: cache)
            }
            rangeLimit = NSMaxRange(effectiveRange)
        }
    }

    func drawUnderlinePathForLayoutManager (_ lm: NSLayoutManager, range: NSRange, yOffset dy: CGFloat, cache: Cache?) {
        
        guard let str = lm.textStorage else {
            return
        }
        guard let font = str.attribute(.font, at: 0, effectiveRange: nil) as? NSFont else {
            return
        }
        
        let ulAttribute = str.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? NSNumber
        
        var ulThickness = font.underlineThickness
        let ulOffset = ulThickness
        
        
        var ulp: NSBezierPath?
        let pathKey = String (format: "DKUnderlinePath_%@_%.2f", NSStringFromRange(range), dy)

        if let cachep = cache {
            ulp = cachep.cache [pathKey] as? NSBezierPath
        }
        
        if ulp == nil {
            // layout without superscripts and subscripts:
            
            let tempLM = NSLayoutManager ()
            tempLM.addTextContainer(lm.textContainers.last!)
            let tempStr = NSTextStorage (attributedString: str)
            tempStr.removeAttribute(.superscript, range: NSMakeRange(0, tempStr.length))
            tempStr.addLayoutManager(tempLM)
            
            let glyphIndex = tempLM.glyphIndexForCharacter(at: range.location)
            let ulOffset = tempLM.typesetter.baselineOffset(in: tempLM, glyphIndex: glyphIndex) * 0.5
            
            if ulThickness <= 0 {
                ulThickness = font.value(forUndefinedKey: NSAttributedString.Key.underlineStyle.rawValue) as? CGFloat ?? 0
            }
        }
        
        var ulc = str.attribute(.underlineColor, at: range.location, effectiveRange: nil) as? NSColor
        
        if ulc == nil {
            ulc = str.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor
        }
        
        if ulc == nil {
            ulc = NSColor.black
        }
        
        let shad = str.attribute(.shadow, at: range.location, effectiveRange: nil) as? NSShadow
        
        NSGraphicsContext.current?.saveGraphicsState()
        defer {
            NSGraphicsContext.current?.restoreGraphicsState()
        }
        
        shad?.set()
        ulc?.set()
        ulp?.stroke()
    }
    
    internal func layoutStringOnPath (_ str: NSTextStorage, yOffset dy:CGFloat, usingLayoutHelper helperObject: DKTextOnPathPlacement, layoutManager lm: NSLayoutManager, cache: Cache?) -> Bool {
        
        let NINETY_DEGREES = CGFloat.pi/2

        if elementCount < 2 || str.length < 1 {
            return false
        }
        
        let para = str.attributes(at: 0, effectiveRange: nil) [.paragraphStyle] as? NSMutableParagraphStyle
        para?.lineBreakMode = .byClipping
        
        if let para = para {
            let attrs = [NSAttributedString.Key.paragraphStyle:para]
            str.addAttributes(attrs, range: NSMakeRange (0, str.length))
        }
        
        let tc = lm.textContainers.last!
        var temp: NSBezierPath!
//        var glyphIndex = 0
        var gbr = NSRect (origin: NSZeroPoint, size: tc.containerSize)
        var result = true
        
        let glyphRange = lm.glyphRange(forBoundingRect: gbr, in: tc)
        
        var glyphCache: [DKPathGlyphInfo]?
        var resultCache: Bool?
        
        if let cachep = cache {
            glyphCache = cachep.cache [NSBezierPath.kDKTextOnPathGlyphPositionsCacheKey] as? [DKPathGlyphInfo]
            resultCache = cachep.cache [NSBezierPath.kDKTextOnPathTextFittedCacheKey] as? Bool
        }
        
        if glyphCache == nil {
            var newGlyphCache = [DKPathGlyphInfo] ()
            var posInfo: DKPathGlyphInfo?
            var baseLine = CGFloat (0)
            
            for glyphIndex in glyphRange.location ..< NSMaxRange(glyphRange) {
                let lineFragmentRect = lm.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
                let layoutLocation = lm.location(forGlyphAt: glyphIndex)
                var viewLocation = layoutLocation
                
                if lineFragmentRect.origin.y > 0 {
                    result = false
                    break
                }
                
                gbr = lm.boundingRect(forGlyphRange: NSMakeRange(glyphIndex, 1), in: tc)
                let half = gbr.width * 0.5
                
                if half > 0 {
                    temp = bezierPathByTrimmingFromLength (NSMinX(lineFragmentRect) + layoutLocation.x + half)
                    
                    if temp.length < half {
                        result = false
                        break
                    }
                    temp.element(at: 0, associatedPoints: &viewLocation)
                    let angle = temp.slopeStartingPath
                    
                    baseLine = NSHeight (gbr) - lm.typesetter.baselineOffset(in: lm, glyphIndex: glyphIndex)
                    
                    viewLocation.x -= baseLine * cos (angle + NINETY_DEGREES)
                    viewLocation.y -= baseLine * sin (angle + NINETY_DEGREES)
                    
                    viewLocation.x -= half * cos (angle)
                    viewLocation.y -= half * sin (angle)
                    
                    posInfo = DKPathGlyphInfo (glyphIndex: glyphIndex, slope: angle, point: viewLocation)
                    newGlyphCache.append(posInfo!)
                    
                    helperObject.layoutManager(lm: lm, willPlaceGlyphAtIndex: glyphIndex, atLocation: viewLocation, pathAngle: angle, uOffset: dy)
                }
            }
            
            if let cachep = cache {
                cachep.cache [NSBezierPath.kDKTextOnPathGlyphPositionsCacheKey] = newGlyphCache
                cachep.cache [NSBezierPath.kDKTextOnPathTextFittedCacheKey] = result
            }
        } else {
            for info in glyphCache! {
                helperObject.layoutManager(lm: lm, willPlaceGlyphAtIndex: info.glyphIndex, atLocation: info.point, pathAngle: info.slope, uOffset: dy)
            }
            result = resultCache ?? false
        }
        return result
    }
}

protocol DKTextOnPathPlacement {
    func layoutManager (lm: NSLayoutManager, willPlaceGlyphAtIndex glyphIndex:Int, atLocation location: NSPoint, pathAngle angle: CGFloat, uOffset dy: CGFloat)

}

class DKTextOnPathGlyphDrawer: DKTextOnPathPlacement {
    func layoutManager (lm: NSLayoutManager, willPlaceGlyphAtIndex glyphIdx:Int, atLocation location: NSPoint, pathAngle angle: CGFloat, uOffset dy: CGFloat) {
        NSGraphicsContext.current?.saveGraphicsState()
        defer {
            NSGraphicsContext.current?.restoreGraphicsState()
        }
        
        let gp = lm.location(forGlyphAt: glyphIdx)
        let transform = NSAffineTransform ()
        
        transform.translateX(by: location.x, yBy: location.y)
        transform.rotate(byRadians: angle)
        transform.concat()
        
        lm.drawBackground(forGlyphRange: NSMakeRange (glyphIdx, 1), at: NSMakePoint(-gp.x, 0-dy))
        lm.drawGlyphs(forGlyphRange: NSRange (location: glyphIdx, length: 1), at: NSPoint (x: -gp.x, y: 0-dy))
    }
}

class DKTextOnPathMetricsHelper: DKTextOnPathPlacement {
    
    var mCharacterRange = NSRange (location: 0, length: 0)
    var mLength = CGFloat (0)
    var mStartPosition = CGFloat (0)
    
    func layoutManager (lm: NSLayoutManager, willPlaceGlyphAtIndex glyphIdx:Int, atLocation location: NSPoint, pathAngle angle: CGFloat, uOffset dy: CGFloat) {
        var glyphIndex = glyphIdx
        let charIndex = lm.characterIndexForGlyph(at: glyphIndex)
        
        if NSLocationInRange(charIndex, mCharacterRange) {
            if mLength == 0 {
                mStartPosition =  lm.location(forGlyphAt: glyphIndex).x
                
                glyphIndex += 1
                if lm.isValidGlyphIndex(glyphIndex) {
                    mLength = lm.location(forGlyphAt: glyphIndex).x - mStartPosition
                } else {
                    mLength = NSMaxX(lm.lineFragmentUsedRect(forGlyphAt: glyphIndex-1, effectiveRange: nil)) - mStartPosition
                }
            }
        }
    }
}

class DKPathGlyphInfo {
    let glyphIndex: Int
    let slope: CGFloat
    let point: CGPoint
    
    init (glyphIndex: Int, slope: CGFloat, point: CGPoint) {
        self.glyphIndex = glyphIndex
        self.point = point
        self.slope = slope
    }
}

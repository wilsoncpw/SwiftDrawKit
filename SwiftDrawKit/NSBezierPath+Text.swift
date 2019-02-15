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
    static var topLayoutMgr: NSLayoutManager?
    
    typealias AttributesDictionary = [NSAttributedString.Key: Any]
    public typealias ChecksumCache = [String: Int]


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
    
    public func drawTextOnPath (_ str: NSAttributedString, yOffset dy: CGFloat, layoutManager lm: NSLayoutManager?, cache: UnsafeMutablePointer<ChecksumCache>?) throws -> Bool {
        
        if let cachep = cache {
            var cache = cachep.pointee
            if cache [NSBezierPath.kDKTextOnPathChecksumCacheKey] != hashValue {
                cache.removeAll()
                cache [NSBezierPath.kDKTextOnPathChecksumCacheKey] = hashValue
            }
            
        }
        
        let usingStandardLM = lm == nil
        let layoutManager = usingStandardLM ? NSBezierPath.textOnPathLayoutManager : lm!
        
        let text = try preadjustedTextStorageWithString (str, layoutManager: layoutManager)
        
        drawUnderlinePathForLayoutManager (layoutManager, yOffset: dy, cache: cache)
        
        return false
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
    
    func drawUnderlinePathForLayoutManager (_ lm: NSLayoutManager, yOffset dy: CGFloat, cache: UnsafeMutablePointer<ChecksumCache>?) {
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

    func drawUnderlinePathForLayoutManager (_ lm: NSLayoutManager, range: NSRange, yOffset dy: CGFloat, cache: UnsafeMutablePointer<ChecksumCache>?) {
        
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
            let cache = cachep.pointee
            ulp = cache [pathKey] as? NSBezierPath
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
}

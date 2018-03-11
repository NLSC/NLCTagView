//
//  SCTagField.swift
//  SCTagField
//
//  Created by SwanCurve on 01/21/18.
//  Copyright © 2018 SwanCurve. All rights reserved.
//

import UIKit

// MARK
struct ActiveTextRange: CustomStringConvertible {
    enum MoveDirection {
        case left(UInt)
        case right(UInt)
    }
    
    private var _range = NSRange(location: 0, length: 0)
    
    var isActive: Bool { get { return _range.length > 0 } }
    
    var textRange: NSRange { get { return _range } }
    var location: Int {
        get { return _range.location }
        set { _range.location = newValue }
    }
    
    func contains(range: NSRange) -> Bool {
        let checkLower = _range.lowerBound <= range.lowerBound
        let checkUpper = _range.upperBound >= range.upperBound
        return (checkLower && checkUpper)
    }
    
    mutating func extend(size: Int) { _range.length = _range.length + size }
    mutating func shrink(size: Int) { _range.length = max(0, _range.length - size) }
    mutating func move(_ vector: MoveDirection) {
        var distance: Int = 0
        if case let .left(scalar) = vector {
            distance = -Int(scalar)
        } else if case let .right(scalar) = vector {
            distance = Int(scalar)
        }
        _range.location = max(0, _range.location + distance)
    }
    mutating func split(by range: NSRange) -> (partToMakeTag: NSRange, partDropped: NSRange) {
        let pTag = NSRange(location: _range.lowerBound, length: range.lowerBound - _range.lowerBound)
        _range.length = _range.upperBound - range.upperBound
        return (pTag, range)
    }
    mutating func take() -> NSRange {
        let range = _range
        _range.length = 0
        return range
    }
    
    var description: String {
        return "{\(_range.lowerBound), \(_range.upperBound), [\(_range.length)]}"
    }
}

// MARK: - SCTagView
open
class NLCTagView: UITextView {
    // new
    private var _activeTextRange: NSRange?
    private var _editRange = ActiveTextRange()
    var lineHeight: CGFloat {
        get {
            var defaultLineHeight: CGFloat = 0
            var lineSpacing: CGFloat = 0
            
            defaultLineHeight = UIFont.systemFont(ofSize: UIFont.systemFontSize).lineHeight
            if self.font != nil {
                defaultLineHeight = self.font!.lineHeight
            }
            if self.defaultFont != nil {
                defaultLineHeight = self.defaultFont!.lineHeight
            }
            if let font = self.defaultAttributes?[.font] as! UIFont? {
                defaultLineHeight = font.lineHeight
            }
            
            if let para = self.defaultAttributes?[.paragraphStyle] as! NSParagraphStyle? {
                lineSpacing = max(para.lineSpacing, 0) // simple
            }
            
            let lh = defaultLineHeight + lineSpacing
            return lh
        }
    }
    
    // deprecated
    internal struct _Tag {
        var text: String
        var isSelected = false
        var size = CGSize.zero
        init(text: String) {
            self.text = text
        }
    }
    
    private var _attributes = [NSRange : [String : AnyObject]?]()
    private var _tags = [_Tag]()
    
    var defaultFont: UIFont? {
        get { return self.font }
        set { self.font = newValue }
    }
    var defaultAttributes: [NSAttributedStringKey : Any]?
    
    private lazy var _tapGesture: UITapGestureRecognizer = { [unowned self] in
        let gesture = UITapGestureRecognizer(target: self, action: #selector(self.handleTap(gesture:)))
        gesture.numberOfTapsRequired = 1
        return gesture
    }()
    
    private lazy var _longPressGesture: UILongPressGestureRecognizer = { [unowned self] in
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(self.handleLongPress(gesture:)))
        return gesture
    }()
    private var _longPressContext: (tagIndex: Int, tagRect: CGRect)?
    
    private var _rangeToApplyAttributes: NSRange?
    
    public override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        self.setup()
    }
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.setup()
    }
    
    private func setup() {
        super.awakeFromNib()
        self.autocorrectionType = .no
        
        for gesture in self.gestureRecognizers! {
            if gesture is UILongPressGestureRecognizer {
                gesture.isEnabled = false
            }
            if gesture is UITapGestureRecognizer {
                gesture.isEnabled = false
            }
        }
        
        addGestureRecognizer(_tapGesture)
        addGestureRecognizer(_longPressGesture)
        
        NotificationCenter.default.addObserver(self, selector: #selector(self._menuWillHide(_:)), name: Notification.Name.UIMenuControllerDidHideMenu, object: nil)
        
        delegate = self
    }
}

extension NLCTagView {
    public func _tagView(_ tagView: NLCTagView, textAttachmentFor attributedString: NSAttributedString, isSelected selected: Bool) -> NSTextAttachment? {
        
        guard let fontForTagView = {() -> UIFont? in
            var font: UIFont?
            if let attrFont = attributedString.attribute(.font, at: 0, effectiveRange: nil) as? UIFont { font = attrFont }
            if font == nil { font = tagView.defaultFont }
            if font == nil { font = UIFont.systemFont(ofSize: UIFont.systemFontSize) }
            return font
        }() else { return nil }
        
        let tagFont = fontForTagView.sizeAdjust(-2.0)
        
        let tagHeight = attributedString.boundingRect(with: CGSize.greatest, options: .usesLineFragmentOrigin, context: nil).height
        
        let mutableAttrString = attributedString.mutableCopy() as! NSMutableAttributedString
        mutableAttrString.addAttribute(.font, value: tagFont, range: mutableAttrString.entireRange)
        mutableAttrString.removeAttribute(.baselineOffset, range: mutableAttrString.entireRange)
        
        let smallRect = mutableAttrString.boundingRect(with: CGSize.greatest, options: .usesLineFragmentOrigin, context: nil)
        
        let radius = tagHeight / 2.0
        let tagSize = CGSize(width: smallRect.width + radius * 2 + radius, height: tagHeight)
        
        let drawingRect = CGRect(x: 0, y: 0, width: tagSize.width, height: tagSize.height)
        let pathBound = UIBezierPath(roundedRect: drawingRect, cornerRadius: radius - 1).cgPath
        let pathMark = UIBezierPath(cgPath: CGPath(ellipseIn: CGRect(x: 4, y: 4, width: radius * 2 - 8, height: radius * 2 - 8), transform: nil)).cgPath
        
        UIGraphicsBeginImageContextWithOptions(tagSize, false, 0.0)
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }
        ctx.saveGState()
        
        ctx.clear(drawingRect)
        if !selected {
            ctx.setFillColor(self.tintColor.withAlphaComponent(0.4).cgColor)
        } else {
            let blue = self.tintColor
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0
            blue?.getHue(&h, saturation: &s, brightness: &b, alpha: nil)
            ctx.setFillColor(UIColor(hue: h, saturation: s, brightness: b - 0.5, alpha: 0.4).cgColor)
        }
        ctx.addPath(pathBound)
        ctx.drawPath(using: .fill)
        
        if !selected {
            ctx.setFillColor(self.tintColor.withAlphaComponent(0.8).cgColor)
        } else {
            let blue = self.tintColor
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0
            blue?.getHue(&h, saturation: &s, brightness: &b, alpha: nil)
            ctx.setFillColor(UIColor(hue: h, saturation: s, brightness: b - 0.5, alpha: 0.8).cgColor)
        }
        ctx.addPath(pathMark)
        ctx.drawPath(using: .eoFill)
        
        mutableAttrString.draw(with: CGRect(x: radius * 2, y: 0, width: tagSize.width, height: tagSize.height), options: .usesLineFragmentOrigin, context: nil)
        
        let _image = UIGraphicsGetImageFromCurrentImageContext()
        
        ctx.restoreGState()
        UIGraphicsEndImageContext()
        
        guard let image = _image else { return nil }
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: ceil(fontForTagView.descender), width: image.size.width, height: image.size.height)
        return attachment
    }
}

// MARK: - (Tag Operation)
extension NLCTagView {
    private func _tag(for string: String) -> _Tag? {
        guard _tags.index(where: { return $0.text == string }) == nil else { return nil }
        let tag = _Tag(text: string)
        return tag
    }
    
    private func _replaceContents(in range: NSRange, with tag: NLCTagView._Tag?) {
        self.textStorage.enumerateAttributes(in: range, options: []) { (attr, subRange, _) in
            if attr.contains(where: { (key, value) -> Bool in return key == .attachment }) {
                _tags[subRange.lowerBound].text = ""
            }
        }
        _tags = _tags.filter { $0.text != "" }
        var tag = tag
        if tag != nil {
            let attachment = _tagView(self, textAttachmentFor: NSAttributedString(string: tag!.text, attributes: defaultAttributes), isSelected: tag!.isSelected)
            if attachment != nil {
                let mAttrString = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment!))
                if defaultAttributes != nil {
                    mAttrString.addAttributes(defaultAttributes!, range: mAttrString.entireRange)
                }
                textStorage.replaceCharacters(in: range, with: (mAttrString.copy() as! NSAttributedString))
                tag!.size = attachment!.bounds.size
            }
            _tags.insert(tag!, at: range.lowerBound)
        } else {
            textStorage.replaceCharacters(in: range, with: "")
        }
    }
    
    private func _replaceContents(in range: NSRange, with text: String) {
        textStorage.replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: self.defaultAttributes))
    }
    
    private func _generate() {
        if _editRange.isActive {
            let tagRange = _editRange.take()
            let tag = _tag(for: attributedText.attributedSubstring(from: tagRange).string)
            _replaceContents(in: tagRange, with: tag)
            if tag != nil {
                _editRange.move(.right(1))
            }
        }
    }
}

// MARK: - (Actions)
extension NLCTagView {
    override open func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        var perfrom = true
        switch action {
        case #selector(self.select(_:)):
            perfrom = false
        case #selector(self.selectAll(_:)):
            perfrom = false
        case #selector(self.paste(_:)):
            perfrom = false
        case #selector(self.copy(_:)):
            perfrom = false
        case #selector(self.delete(_:)):
            perfrom = (sender as AnyObject? === _longPressGesture) ? true : false
        default:
            perfrom = super.canPerformAction(action, withSender: sender)
        }
        Swift.print("\(action), \(perfrom)")
        return perfrom
    }
    
    override open func paste(_ sender: Any?) {
        if let text = UIPasteboard.general.string {
            if _editRange.isActive {
                let (partToMakeTag, _) = _editRange.split(by: selectedRange)
                selectedRange.location = _editRange.location
                
                let tag = _tag(for: attributedText.attributedSubstring(from: partToMakeTag).string)
                _replaceContents(in: partToMakeTag, with: tag)
                if tag != nil {
                    _editRange.move(.right(1))
                }
                selectedRange.location = _editRange.location
            }
            let savedSelectedRange = selectedRange
            let tag = _tag(for: text)
            _replaceContents(in: savedSelectedRange, with: tag)
            if tag != nil {
                _editRange.move(.right(1))
            }
            selectedRange = NSRange(location: _editRange.location, length: 0)
            printInfo()
            return
        }
        
        super.paste(sender)
    }
    
    private func _characterLocationInfo(for touchPoint: CGPoint) -> (index: Int, fraction: CGFloat) {
        let point = CGPoint(x: touchPoint.x - self.textContainerInset.left, y: touchPoint.y - self.textContainerInset.top)
        
        var fraction: CGFloat = 0
        var fraction2: CGFloat = 0
        let index = layoutManager.characterIndex(for: point, in: textContainer, fractionOfDistanceBetweenInsertionPoints: &fraction)
        let index2 = layoutManager.glyphIndex(for: point, in: textContainer, fractionOfDistanceThroughGlyph: &fraction2)
        
        Swift.print("characterIndex: \(index), fraction:\(fraction); glyphIndex: \(index2), fraction: \(fraction2)\n")
        return (index, fraction)
    }
    
    private func _tagIndex(for locationInfo: (index: Int, fraction: CGFloat)) -> Int? {
        let index = locationInfo.index
        let fraction = locationInfo.fraction
        
        if fraction > 0.0, fraction < 1.0 { return index + 1 }
        else { return nil }
    }
    
    private func _selectTag(at index: Int, selected: Bool = true) {
        guard index >= 0, _tags.count > index else { assert(false) }
        
        _tags[index].isSelected = selected
        _replaceContents(in: NSRange(location: index, length: 1), with: _tags[index])
    }
    
    private func _restoreTagStatus() {
        if let idxSelected = _tags.index(where: { $0.isSelected }) {
            _tags[idxSelected].isSelected = false
            _selectTag(at: idxSelected, selected: false)
        }
    }
    
    @objc
    func handleTap(gesture: UITapGestureRecognizer) {
        if canBecomeFirstResponder {
            becomeFirstResponder()
        }
        
        let touchPt = gesture.location(in: self)
        var (index, fraction) = _characterLocationInfo(for: touchPt)
        if fraction > 0.5 {
            index += 1
        }
        selectedRange = NSRange(location: index, length: 0)
    }
    
    @objc
    func handleLongPress(gesture: UILongPressGestureRecognizer) {
        
        let touchPt = gesture.location(in: self)
        let (index, fraction) = _characterLocationInfo(for: touchPt)
        
        self.selectedRange = NSRange(location: index + (fraction > 0.5 ? 1 : 0), length: 0)
        if fraction == 1.0 || fraction == 0.0 {
            return
        }
        
        if self.textStorage.containsAttachments(in: NSRange(location: index, length: 1)) {
            _selectTag(at: index)
            
            let lh = lineHeight
            let tagSize = _tags[index].size
            
            let lineNum = floor((touchPt.y - contentInset.top - textContainerInset.top) / lh)
            Swift.print("lineHeight: \(lh), lineNum: \(lineNum), tagSize: \(tagSize)")
            let rect = CGRect(x: touchPt.x - tagSize.width * fraction,
                              y: lineNum * lh + self.contentInset.top + self.textContainerInset.top,
                              width: tagSize.width,
                              height: lh)
            
            let menuCtrller = UIMenuController.shared
            let edtMenuItem = UIMenuItem(title: "Edit", action: #selector(self.edit(_:)))
            let delMenuItem = UIMenuItem(title: "Delete", action: #selector(self.delete(_:)))
            menuCtrller.menuItems = [edtMenuItem, delMenuItem]
            menuCtrller.setTargetRect(rect, in: self)
            menuCtrller.setMenuVisible(true, animated: true)
        } else {
            selectedRange = _editRange.textRange
        }
    }
    
    private func _deleteTag(at index: Int) {
        guard index >= 0, index < _tags.count else { assert(false) }
        
        _tags.remove(at: index)
        _replaceContents(in: NSRange(location: index, length: 1), with: nil)
        if index < _editRange.location {
            _editRange.move(.left(1))
            selectedRange = NSRange(location: _editRange.location, length: 0)
        }
    }
    
    @objc
    override open func delete(_ sender: Any?) {
        guard let idxToDel = _tags.index(where: { $0.isSelected }) else { return }
        _deleteTag(at: idxToDel)
    }
    
    private func _editTag(at index: Int) {
        guard index >= 0, index < _tags.count else { assert(false) }
        
        let text = _tags.remove(at: index).text
        _replaceContents(in: NSRange(location: index, length: 1), with: text)
        _editRange.location = index
        _editRange.extend(size: text.count)
        selectedRange = NSRange(location: index + text.count, length: 0)
    }
    
    @objc
    func edit(_ sender: Any?) {
        guard let idxToEdt = _tags.index(where: { $0.isSelected }) else { return }
        _editTag(at: idxToEdt)
    }
    
    @objc
    private func _menuWillHide(_ sender: Any?) {
        _restoreTagStatus()
    }
}

// MARK: test
extension NLCTagView {
    func printInfo() {
        let str = _tags.reduce(into: "") { (res, tag) in
            res += "\(tag.text)(\(tag.isSelected ? "o" : "_")) "
        }
        Swift.print("data: {\(str.dropLast())}",
                    "_editRange: \(_editRange.description)",
            "selectedRange: \(selectedRange)", separator: ",\n", terminator: "\n\n")
    }
}

// MARK: - <UITextViewDelegate>
extension NLCTagView: UITextViewDelegate {
    override open func shouldChangeText(in range: UITextRange, replacementText text: String) -> Bool {
        return false
    }
    
    // MARK: - :: Responding to Editing Notifications
    public func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
        return true
    }
    
    public func textViewDidBeginEditing(_ textView: UITextView) {}
    
    public func textViewShouldEndEditing(_ textView: UITextView) -> Bool {
        _generate()
        return true
    }
    
    public func textViewDidEndEditing(_ textView: UITextView) {
        Swift.print("did end editing text: \(self.text), attr text: \(self.attributedText)")
    }
    
    // MARK: - :: Responding to Text Changes
    public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        var shouldChange = true
        
        // modify tag
        if range.length > 0 {
            if textStorage.containsAttachments(in: range) {
                textStorage.enumerateAttributes(in: range, options: []) { (attr, subRange, _) in
                    if attr.contains(where: { (key, value) -> Bool in return key == .attachment }) {
                        _tags[subRange.lowerBound].text = ""
                    }
                }
                _tags = _tags.filter { $0.text != "" }
            }
        }
        
        // delete
        if text.count < 1 {
            if _editRange.isActive {
                if _editRange.contains(range: range) {
                    _editRange.shrink(size: range.length)
                } else {
                    assert(false)
                }
            } else {}
        }
        // input
        else if text.count == 1 {
            switch text.first!
            {
            case "\n": // generate
                _generate()
                selectedRange = NSRange(location: _editRange.location, length: 0)
                shouldChange = false
            case " ": // input
                fallthrough
            default: // input
                _editRange.extend(size: 1)
                _rangeToApplyAttributes = NSRange(location: _editRange.textRange.upperBound - 1, length: 1)
                break
            }
        }
        // unreachable
        else {
        }
    
        printInfo()
        return shouldChange
    }
    
    public func textViewDidChange(_ textView: UITextView) {
        if self._rangeToApplyAttributes != nil {
            if defaultAttributes != nil {
                textStorage.addAttributes(defaultAttributes!, range: _rangeToApplyAttributes!)
            }
            self._rangeToApplyAttributes = nil
        }
    }
    
    // MARK: - :: Responding to Selection Changes
    public func textViewDidChangeSelection(_ textView: UITextView) {
        if _editRange.isActive {
            if !_editRange.contains(range: selectedRange) {
                let editRange = _editRange.take()
                let tag = _tag(for: attributedText.attributedSubstring(from: editRange).string)
                _replaceContents(in: editRange, with: tag)
                
                selectedRange = NSRange(location: selectedRange.lowerBound - editRange.length + ((tag == nil) ? 0 : 1), length: 0)
            }
        } else {
            _editRange.location = selectedRange.location
        }
    }
    
    // MARK: - :: Interacting With Text Data
    public func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        return false
    }
    
    public func textView(_ textView: UITextView, shouldInteractWith textAttachment: NSTextAttachment, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        return false
    }
}

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// A text storage over a plain attributed string, with the primitives
/// TextKit calls most written here rather than in Swift.
///
/// Laying out asks a text storage for attributes run by run. Answered by a
/// Swift override, every answer turned the attribute dictionary into a Swift
/// one, keys and all, and back again for the caller: a fifth of layout time.
@interface MDBackedTextStorage : NSTextStorage

/// The characters and attributes. Changing it directly is for subclasses
/// that report their own edits.
@property (nonatomic, readonly) NSMutableAttributedString *backing;

@end

NS_ASSUME_NONNULL_END

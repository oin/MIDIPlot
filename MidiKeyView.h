#pragma once
#import <Cocoa/Cocoa.h>
#include <cstddef>

@interface MidiKeyView : NSView
@property (retain, nonnull) NSColor *highlightColour;
-(double)maxKeyboardWidthForSize:(NSSize)proposedSize;
-(void)turnMidiNoteOn:(int)note;
-(void)turnMidiNoteOff:(int)note;
-(void)turnAllNotesOff;
@end

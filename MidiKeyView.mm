#import "MidiKeyView.h"
// Adapted from https://github.com/flit/MidiKeys
// License at the bottom of this file.

#define MAX_KEY_COUNT 120
#define kNominalViewHeight (57.0)
#define kNominalViewWidth (371.0)
#define kWhiteKeyHeight (kNominalViewHeight)
#define kWhiteKeyWidth (12.0)
#define kBlackKeyInset (4.0)
#define kBlackKeyWidth (8.0)
#define kBlackKeyHeight (32.0)
#define kWhiteKeysPerOctave (7)
struct key_info_t{
    int theOctave;
    int octaveFirstNote;
    int noteInOctave;
    int precedingWhiteKeysInOctave;
    int precedingBlackKeysInOctave;
    BOOL isBlackKey;
    BOOL rightIsInset;
    BOOL leftIsInset;
};
struct keyboard_size_info_t {
    double scale;
    int numWhiteKeys;
    int numOctaves;
    int leftOctaves;
    int firstMidiNote;
    int lastMidiNote;
};
static const key_info_t kNoteInOctaveInfo[] = {
        [0] = { // C
            .isBlackKey = NO,
            .rightIsInset = YES
        },
        [1] = { // C#
            .isBlackKey = YES,
            .precedingWhiteKeysInOctave = 1
        },
        [2] = { // D
            .isBlackKey = NO,
            .precedingWhiteKeysInOctave = 1,
            .precedingBlackKeysInOctave = 1,
            .rightIsInset = YES,
            .leftIsInset = YES,
        },
        [3] = { // D#
            .isBlackKey = YES,
            .precedingWhiteKeysInOctave = 2,
            .precedingBlackKeysInOctave = 1,
        },
        [4] = {// E
            .isBlackKey = NO,
            .precedingWhiteKeysInOctave = 2,
            .precedingBlackKeysInOctave = 2,
            .leftIsInset = YES,
        },
        [5] = { // F
            .isBlackKey = NO,
            .precedingWhiteKeysInOctave = 3,
            .precedingBlackKeysInOctave = 2,
            .rightIsInset = YES,
        },
        [6] = { // F#
            .isBlackKey = YES,
            .precedingWhiteKeysInOctave = 4,
            .precedingBlackKeysInOctave = 2,
        },
        [7] = { // G
            .isBlackKey = NO,
            .precedingWhiteKeysInOctave = 4,
            .precedingBlackKeysInOctave = 3,
            .rightIsInset = YES,
            .leftIsInset = YES,
        },
        [8] = { // G#
            .isBlackKey = YES,
            .precedingWhiteKeysInOctave = 5,
            .precedingBlackKeysInOctave = 3,
        },
        [9] = { // A
            .isBlackKey = NO,
            .precedingWhiteKeysInOctave = 5,
            .precedingBlackKeysInOctave = 4,
            .rightIsInset = YES,
            .leftIsInset = YES,
        },
        [10] = { // A#
            .isBlackKey = YES,
            .precedingWhiteKeysInOctave = 6,
            .precedingBlackKeysInOctave = 4,
        },
        [11] = { // B
            .isBlackKey = NO,
            .precedingWhiteKeysInOctave = 6,
            .precedingBlackKeysInOctave = 5,
            .leftIsInset = YES,
        },
};

@interface MidiKeyView ()
{
    uint8_t midiKeyStates[MAX_KEY_COUNT];
    BOOL inited;
    keyboard_size_info_t _sizing;
    NSColor *mHighlightColour;
    int mClickedNote;
    NSImage *mOctaveDownImage;
    NSImage *mOctaveUpImage;
    int mOctaveOffset;
    BOOL _showKeycaps;
    BOOL _showCNotes;
    key_info_t _keyInfo; //!< Shared key info struct.
    NSBezierPath * _lastKeyPath;
    int _lastKeyPathNote;
    int _lastAftertouchPressure;
    float modWheelValue;
    float otherValue;
    float bend;
    NSPoint lastDragPoint;
}
-(const key_info_t * _Nonnull)getKeyInfoForMidiNote:(int)note;
-(const key_info_t * _Nonnull)getKeyInfoForMidiNote:(int)note usingSizeInfo:(keyboard_size_info_t * _Nonnull)sizing;
-(void)computeSizeInfo:(keyboard_size_info_t * _Nonnull)info forSize:(NSSize)frameSize;
-(void)computeKeyValues;
-(NSBezierPath *)bezierPathForMidiNote:(int)note;
-(NSBezierPath *)bezierPathForMidiNote:(int)note withInset:(double)inset;
-(NSBezierPath *)bezierPathForMidiNote:(int)note withInset:(double)inset usingSizeInfo:(keyboard_size_info_t * _Nonnull)sizing;
-(void)drawKeyForNote:(int)note;
-(void)drawKeyCapForNote:(int)note;
-(void)highlightMidiKey:(int)note;
-(int)midiNoteForMouse:(NSPoint)location;
-(void)forceDisplay;
@end

@implementation MidiKeyView

-(void)commonInit
{
	mOctaveOffset = 0;
	_showCNotes = YES;
	mHighlightColour = [NSColor colorWithCalibratedRed:76.0/255.0 green:217.0/255.0 blue:100.0/255.0 alpha:1.0];
    mClickedNote = -1;
    _lastKeyPathNote = -1;
    _lastAftertouchPressure = -1;
    self.pressureConfiguration = [[NSPressureConfiguration alloc] initWithPressureBehavior:NSPressureBehaviorPrimaryGeneric];
}

-(instancetype)initWithFrame:(NSRect)frame
{
	self = [super initWithFrame:frame];
	if(self) {
		[self commonInit];
	}
	return self;
}

-(instancetype)initWithCoder:(NSCoder *)coder
{
	self = [super initWithCoder:coder];
	if(self) {
		[self commonInit];
	}
	return self;
}

-(void)computeSizeInfo:(keyboard_size_info_t * _Nonnull)info forSize:(NSSize)frameSize
{
    info->scale = frameSize.height / kNominalViewHeight;

    double scaledWhiteKeyWidth = round(kWhiteKeyWidth * info->scale);
    info->numWhiteKeys = round(frameSize.width / scaledWhiteKeyWidth);
    info->numOctaves = MIN(10, frameSize.width / ((scaledWhiteKeyWidth * kWhiteKeysPerOctave) - 1.0));

	// put middle c=60 in approx. center octave
	info->leftOctaves = info->numOctaves/2;

	info->firstMidiNote = MAX(0, 60 - (info->leftOctaves * 12));

    info->lastMidiNote = MIN(MAX_KEY_COUNT, info->firstMidiNote + (info->numOctaves + 1) * 12);
}

-(void)computeKeyValues
{
    [self computeSizeInfo:&_sizing forSize:self.bounds.size];

    _lastKeyPathNote = -1;
}

-(const key_info_t * _Nonnull)getKeyInfoForMidiNote:(int)note
{
    return [self getKeyInfoForMidiNote:note usingSizeInfo:&_sizing];
}

-(const key_info_t * _Nonnull)getKeyInfoForMidiNote:(int)note usingSizeInfo:(keyboard_size_info_t * _Nonnull)sizing
{
	int theNote = note;
	int theOctave = (theNote - sizing->firstMidiNote) / 12;
	int octaveFirstNote = sizing->firstMidiNote + theOctave * 12;
	unsigned noteInOctave = theNote - octaveFirstNote;

    assert(noteInOctave < (sizeof(kNoteInOctaveInfo) / sizeof(key_info_t)));
    const key_info_t * octaveNoteInfo = &kNoteInOctaveInfo[noteInOctave];

    // Copy const key info, then set a few other fields.
    _keyInfo = *octaveNoteInfo;
	_keyInfo.theOctave = theOctave;
	_keyInfo.octaveFirstNote = octaveFirstNote;
	_keyInfo.noteInOctave = noteInOctave;

	return &_keyInfo;
}

-(NSBezierPath *)bezierPathForMidiNote:(int)note
{
    return [self bezierPathForMidiNote:note withInset:0.0];
}

-(NSBezierPath *)bezierPathForMidiNote:(int)note withInset:(double)inset
{
    return [self bezierPathForMidiNote:note withInset:inset usingSizeInfo:&_sizing];
}

-(NSBezierPath *)bezierPathForMidiNote:(int)note withInset:(double)inset usingSizeInfo:(keyboard_size_info_t * _Nonnull)sizing
{
//    if (_lastKeyPathNote == note && _lastKeyPath)
//    {
//        return _lastKeyPath;
//    }

    double scaledKeyHeight = kWhiteKeyHeight * sizing->scale;
    double scaledWhiteKeyWidth = kWhiteKeyWidth * sizing->scale;
    double scaledBlackKeyWidth = kBlackKeyWidth * sizing->scale;
    double scaledBlackKeyInset = kBlackKeyInset * sizing->scale;
    double scaledBlackKeyHeight = kBlackKeyHeight * sizing->scale;

	// get key info for the note
	const key_info_t * _Nonnull info = [self getKeyInfoForMidiNote:note usingSizeInfo:sizing];

	int theOctave = info->theOctave;
    double octaveLeft = (double)theOctave * (scaledWhiteKeyWidth * kWhiteKeysPerOctave);// - 1.0);
	int numWhiteKeys = info->precedingWhiteKeysInOctave;
	BOOL isBlackKey = info->isBlackKey;
	BOOL leftIsInset = info->leftIsInset;
	BOOL rightIsInset = info->rightIsInset; // black key insets on white keys

	NSRect keyRect;

	if (isBlackKey)
	{
		keyRect.origin.x = octaveLeft + numWhiteKeys * scaledWhiteKeyWidth - scaledBlackKeyInset + inset;
		keyRect.origin.y = scaledKeyHeight - scaledBlackKeyHeight + inset;
		keyRect.size.width = scaledBlackKeyWidth - (inset * 2.0);
		keyRect.size.height = scaledBlackKeyHeight;

		return [NSBezierPath bezierPathWithRect:keyRect];
	}

	// lower half of white key
	double x, y, w, h;
	x = octaveLeft + numWhiteKeys * scaledWhiteKeyWidth /*- 1.0*/ + inset;
	y = inset;
	w = scaledWhiteKeyWidth /*+ 1.0*/ - (inset * 2.0);
	h = scaledKeyHeight - scaledBlackKeyHeight - inset * 2;// - 1;

	NSBezierPath *keyPath = [NSBezierPath bezierPath];
	[keyPath moveToPoint:NSMakePoint(x+0.5, y+h-0.5)];
	[keyPath lineToPoint:NSMakePoint(x+0.5, y)];
	[keyPath lineToPoint:NSMakePoint(x+w, y)];
	[keyPath lineToPoint:NSMakePoint(x+w, y+h)];
	if (rightIsInset)
	{
		[keyPath lineToPoint:NSMakePoint(x+w - scaledBlackKeyInset + 1, y+h)];
	}

    // upper half of white key
	y = scaledKeyHeight - scaledBlackKeyHeight - 1 - inset;
	h = scaledBlackKeyHeight;
	if (!rightIsInset && leftIsInset)
	{
		x += scaledBlackKeyInset - 1;
		w -= scaledBlackKeyInset - 1;
	}
	else if (rightIsInset && !leftIsInset)
	{
		w -= scaledBlackKeyInset - 1;
	}
	else if (rightIsInset && leftIsInset)
	{
		x += scaledBlackKeyInset - 1;
		w -= (scaledBlackKeyInset - 1) * 2;
	}
	[keyPath lineToPoint:NSMakePoint(x+w, y+h)];
	[keyPath lineToPoint:NSMakePoint(x+0.5, y+h)];
	[keyPath lineToPoint:NSMakePoint(x+0.5, y+0.5)];
	[keyPath closePath];

    // Cache the bezier path.
//    _lastKeyPath = [keyPath retain];
//    _lastKeyPathNote = note;

	return keyPath;
}

-(void)drawKeyForNote:(int)note
{
    BOOL drawDark = [self inDarkMode];

    const key_info_t * _Nonnull keyInfo = [self getKeyInfoForMidiNote:note];

    NSColor * keyOutlineColor;
    NSColor * keyInlineColor;
    NSColor * keyFillTopColor;
    NSColor * keyFillBottomColor;
    double maxLineWidth;
    double insetAmount = (_sizing.scale - 1.0) * 0.6 + 1.0;
    keyOutlineColor = NSColor.blackColor;
    if((keyInfo->isBlackKey && !drawDark) || (!keyInfo->isBlackKey && drawDark)) {
        keyInlineColor = [NSColor colorWithWhite:0.25 alpha:1.0];
        keyFillTopColor = [NSColor colorWithWhite:0.0 alpha:1.0];
        keyFillBottomColor = [NSColor colorWithWhite:0.35 alpha:1.0];
    } else {
        keyInlineColor = [NSColor colorWithWhite:0.5 alpha:1.0];
        keyFillTopColor = [NSColor colorWithWhite:0.65 alpha:1.0];
        keyFillBottomColor = [NSColor colorWithWhite:1.0 alpha:1.0];
    }
    maxLineWidth = keyInfo->isBlackKey
                    ? 2.0
                    : 4.0;

    [NSGraphicsContext saveGraphicsState];

    // Draw frame around the key
    NSBezierPath *keyPath = [self bezierPathForMidiNote:note];
    NSBezierPath *insetPath = [self bezierPathForMidiNote:note withInset:insetAmount];

    [keyOutlineColor set];
    [keyPath stroke];

    [NSGraphicsContext saveGraphicsState];

    [insetPath setClip];

    NSGradient *gradient = [[NSGradient alloc] initWithStartingColor: keyFillTopColor endingColor:keyFillBottomColor];
    [gradient drawInRect: [insetPath bounds] angle: 330.0];

    [NSGraphicsContext restoreGraphicsState];

    [keyInlineColor set];
    insetPath.lineWidth = MIN(maxLineWidth, (_sizing.scale - 1.0) * 0.7 + 1.0);
    [insetPath stroke];

    [NSGraphicsContext restoreGraphicsState];
}

-(BOOL)inDarkMode
{
    if(NSAppKitVersionNumber < 1671) {
        return NO;
    }
    id effectiveAppearanceName = [[self performSelector:@selector(effectiveAppearance)] performSelector:@selector(name)];
    return [@[@"NSNSAppearanceNameVibrantDark", @"NSAppearanceNameDarkAqua"] containsObject:effectiveAppearanceName];
}

-(void)drawKeyCapForNote:(int)note
{
    BOOL drawDark = [self inDarkMode];
    int offsetNote = note - mOctaveOffset * 12;
    const key_info_t * _Nonnull info = [self getKeyInfoForMidiNote:note];
    NSRect pathBounds = [[self bezierPathForMidiNote:note] bounds];
    double fontSize = 9.0 * MAX(1.0, _sizing.scale / 1.2);
    NSMutableDictionary * attributes = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSFont labelFontOfSize:fontSize], NSFontAttributeName, nil];
    if (info->isBlackKey && !drawDark)
    {
        [attributes setValue:NSColor.whiteColor forKey:NSForegroundColorAttributeName];
    }
    else if (!info->isBlackKey && drawDark)
    {
        [attributes setValue:[NSColor colorWithWhite:0.75 alpha:1.0]
            forKey:NSForegroundColorAttributeName];
    }

    NSString * c = @" ";
    NSSize capSize = [c sizeWithAttributes:attributes];
    double xOffset = ((pathBounds.size.width - capSize.width) / 2.0) - 0.5;
    NSPoint drawPoint = pathBounds.origin;
    drawPoint.x += xOffset;

    if (!info->isBlackKey)
    {
        drawPoint.y += 4.0;
    }
    else
    {
        drawPoint.y += 3.0;
    }

    if (_showCNotes && info->noteInOctave == 0)
    {
        // Get the octave number from the MIDI note number.
        // MIDI note 60 is C4 for most devices, and that's what we use here.
        // Yamaha and some others use C3 for note 60.
        int octaveNumber = (note / 12) - 1;
        c = [NSString stringWithFormat:@"C%d", octaveNumber];
        
        [attributes setValue:[NSFont boldSystemFontOfSize:(fontSize * 2) / 3] forKey:NSFontAttributeName];
        NSSize noteCapSize = [c sizeWithAttributes:attributes];
        xOffset = ((pathBounds.size.width - noteCapSize.width) / 2.0) - 0.5;
        drawPoint = pathBounds.origin;
        drawPoint.x += xOffset;
        drawPoint.y = 3.0;//capSize.height - 10.0;

        [c drawAtPoint:drawPoint withAttributes:attributes];
    }
}

-(void)highlightMidiKey:(int)note
{
	NSBezierPath *keyPath = [self bezierPathForMidiNote:note withInset:1.0];
	NSColor * darkerHighlightColor = [NSColor colorWithCalibratedHue:[mHighlightColour hueComponent] saturation:[mHighlightColour saturationComponent]/2.0 brightness:[mHighlightColour brightnessComponent]*0.7 alpha:[mHighlightColour alphaComponent]];
	NSColor * lighterHighlightColor = [NSColor colorWithCalibratedHue:[mHighlightColour hueComponent] saturation:[mHighlightColour saturationComponent] brightness:[mHighlightColour brightnessComponent]*1.2 alpha:[mHighlightColour alphaComponent]];

	// Draw the highlight
	[NSGraphicsContext saveGraphicsState];

	[keyPath setClip];

        NSGradient *gradient = [[NSGradient alloc] initWithStartingColor: darkerHighlightColor endingColor:lighterHighlightColor];
        [gradient drawInRect: [keyPath bounds] angle: 330.0];

	[NSGraphicsContext restoreGraphicsState];

	// Draw frame around the highlighted key
	[NSGraphicsContext saveGraphicsState];

	[[NSColor colorWithCalibratedHue:[mHighlightColour hueComponent] saturation:[mHighlightColour saturationComponent] brightness:[mHighlightColour brightnessComponent]/3. alpha:[mHighlightColour alphaComponent]] set];
	[keyPath stroke];

	[NSGraphicsContext restoreGraphicsState];
}

-(void)drawRect:(NSRect)rect
{
	if(!inited)
	{
		[self computeKeyValues];
		inited = YES;
	}

	// draw the keyboard one key at a time, starting with the leftmost visible note
	int i;
	for(i = _sizing.firstMidiNote; i < _sizing.lastMidiNote; ++i) {
        // Draw frame around the key
        [self drawKeyForNote:i];

		// highlight the key if it is on
		if (midiKeyStates[i]) {
			[self highlightMidiKey:i];
		}

		// Draw the key caps for this key.
        [self drawKeyCapForNote:i];
	}

	// [self drawOctaveOffsetIndicator];
}

-(void)resizeWithOldSuperviewSize:(NSSize)oldBoundsSize
{
    // force recomputation of notes and sizes
    inited = NO;
    [self setNeedsDisplay:YES];
	[super resizeWithOldSuperviewSize:oldBoundsSize];
}

-(double)maxKeyboardWidthForSize:(NSSize)proposedSize
{
    keyboard_size_info_t sizing;
    [self computeSizeInfo:&sizing forSize:proposedSize];
    NSBezierPath * path = [self bezierPathForMidiNote:MAX_KEY_COUNT-1 withInset:0.0 usingSizeInfo:&sizing];
    return NSMaxX(path.bounds);
}

-(BOOL)mouseDownCanMoveWindow
{
	return NO;
}

-(int)midiNoteForMouse:(NSPoint)location
{
	int note;
	for (note = _sizing.firstMidiNote; note < _sizing.lastMidiNote; ++note)
	{
		NSBezierPath *keyPath = [self bezierPathForMidiNote:note];
		if ([keyPath containsPoint:location])
		{
			return note;
		}
	}

	return -1;
}


-(int)midiVelocityForMouse:(NSPoint)location note:(int)note
{
	NSBezierPath *keyPath = [self bezierPathForMidiNote:note];
	NSRect rect = keyPath.bounds;
	if(location.y < rect.origin.y) {
		return 127;
	} else if(location.y > rect.origin.y + rect.size.height) {
		return 0;
	}
	return (1.f - (location.y - rect.origin.y) / rect.size.height) * 127;
}

-(void)forceDisplay
{
    [self setNeedsDisplay:YES];
}

-(void)turnMidiNoteOn:(int)note
{
    if (note < 0 || note > MAX_KEY_COUNT-1)
    {
        return;
    }
    if (midiKeyStates[note] < 254)
    {
        midiKeyStates[note]++;
    }
    [self performSelectorOnMainThread:@selector(forceDisplay) withObject:nil waitUntilDone:NO];
}

-(void)turnMidiNoteOff:(int)note
{
	if (note < 0 || note > MAX_KEY_COUNT-1)
    {
		return;
    }
	if (midiKeyStates[note] > 0)
    {
		midiKeyStates[note]--;
    }
    [self performSelectorOnMainThread:@selector(forceDisplay) withObject:nil waitUntilDone:NO];
}

-(void)turnAllNotesOff
{
    memset(&midiKeyStates, 0, sizeof(midiKeyStates));
    [self setNeedsDisplay:YES];
}

@end

/*
License for the original code (https://github.com/flit/MidiKeys/blob/main/LICENSE)
---

Apache License
Version 2.0, January 2004
http://www.apache.org/licenses/

TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

1. Definitions.

"License" shall mean the terms and conditions for use, reproduction, and
distribution as defined by Sections 1 through 9 of this document.

"Licensor" shall mean the copyright owner or entity authorized by the copyright
owner that is granting the License.

"Legal Entity" shall mean the union of the acting entity and all other entities
that control, are controlled by, or are under common control with that entity.
For the purposes of this definition, "control" means (i) the power, direct or
indirect, to cause the direction or management of such entity, whether by
contract or otherwise, or (ii) ownership of fifty percent (50%) or more of the
outstanding shares, or (iii) beneficial ownership of such entity.

"You" (or "Your") shall mean an individual or Legal Entity exercising
permissions granted by this License.

"Source" form shall mean the preferred form for making modifications, including
but not limited to software source code, documentation source, and configuration
files.

"Object" form shall mean any form resulting from mechanical transformation or
translation of a Source form, including but not limited to compiled object code,
generated documentation, and conversions to other media types.

"Work" shall mean the work of authorship, whether in Source or Object form, made
available under the License, as indicated by a copyright notice that is included
in or attached to the work (an example is provided in the Appendix below).

"Derivative Works" shall mean any work, whether in Source or Object form, that
is based on (or derived from) the Work and for which the editorial revisions,
annotations, elaborations, or other modifications represent, as a whole, an
original work of authorship. For the purposes of this License, Derivative Works
shall not include works that remain separable from, or merely link (or bind by
name) to the interfaces of, the Work and Derivative Works thereof.

"Contribution" shall mean any work of authorship, including the original version
of the Work and any modifications or additions to that Work or Derivative Works
thereof, that is intentionally submitted to Licensor for inclusion in the Work
by the copyright owner or by an individual or Legal Entity authorized to submit
on behalf of the copyright owner. For the purposes of this definition,
"submitted" means any form of electronic, verbal, or written communication sent
to the Licensor or its representatives, including but not limited to
communication on electronic mailing lists, source code control systems, and
issue tracking systems that are managed by, or on behalf of, the Licensor for
the purpose of discussing and improving the Work, but excluding communication
that is conspicuously marked or otherwise designated in writing by the copyright
owner as "Not a Contribution."

"Contributor" shall mean Licensor and any individual or Legal Entity on behalf
of whom a Contribution has been received by Licensor and subsequently
incorporated within the Work.

2. Grant of Copyright License.

Subject to the terms and conditions of this License, each Contributor hereby
grants to You a perpetual, worldwide, non-exclusive, no-charge, royalty-free,
irrevocable copyright license to reproduce, prepare Derivative Works of,
publicly display, publicly perform, sublicense, and distribute the Work and such
Derivative Works in Source or Object form.

3. Grant of Patent License.

Subject to the terms and conditions of this License, each Contributor hereby
grants to You a perpetual, worldwide, non-exclusive, no-charge, royalty-free,
irrevocable (except as stated in this section) patent license to make, have
made, use, offer to sell, sell, import, and otherwise transfer the Work, where
such license applies only to those patent claims licensable by such Contributor
that are necessarily infringed by their Contribution(s) alone or by combination
of their Contribution(s) with the Work to which such Contribution(s) was
submitted. If You institute patent litigation against any entity (including a
cross-claim or counterclaim in a lawsuit) alleging that the Work or a
Contribution incorporated within the Work constitutes direct or contributory
patent infringement, then any patent licenses granted to You under this License
for that Work shall terminate as of the date such litigation is filed.

4. Redistribution.

You may reproduce and distribute copies of the Work or Derivative Works thereof
in any medium, with or without modifications, and in Source or Object form,
provided that You meet the following conditions:

You must give any other recipients of the Work or Derivative Works a copy of
this License; and
You must cause any modified files to carry prominent notices stating that You
changed the files; and
You must retain, in the Source form of any Derivative Works that You distribute,
all copyright, patent, trademark, and attribution notices from the Source form
of the Work, excluding those notices that do not pertain to any part of the
Derivative Works; and
If the Work includes a "NOTICE" text file as part of its distribution, then any
Derivative Works that You distribute must include a readable copy of the
attribution notices contained within such NOTICE file, excluding those notices
that do not pertain to any part of the Derivative Works, in at least one of the
following places: within a NOTICE text file distributed as part of the
Derivative Works; within the Source form or documentation, if provided along
with the Derivative Works; or, within a display generated by the Derivative
Works, if and wherever such third-party notices normally appear. The contents of
the NOTICE file are for informational purposes only and do not modify the
License. You may add Your own attribution notices within Derivative Works that
You distribute, alongside or as an addendum to the NOTICE text from the Work,
provided that such additional attribution notices cannot be construed as
modifying the License.
You may add Your own copyright statement to Your modifications and may provide
additional or different license terms and conditions for use, reproduction, or
distribution of Your modifications, or for any such Derivative Works as a whole,
provided Your use, reproduction, and distribution of the Work otherwise complies
with the conditions stated in this License.

5. Submission of Contributions.

Unless You explicitly state otherwise, any Contribution intentionally submitted
for inclusion in the Work by You to the Licensor shall be under the terms and
conditions of this License, without any additional terms or conditions.
Notwithstanding the above, nothing herein shall supersede or modify the terms of
any separate license agreement you may have executed with Licensor regarding
such Contributions.

6. Trademarks.

This License does not grant permission to use the trade names, trademarks,
service marks, or product names of the Licensor, except as required for
reasonable and customary use in describing the origin of the Work and
reproducing the content of the NOTICE file.

7. Disclaimer of Warranty.

Unless required by applicable law or agreed to in writing, Licensor provides the
Work (and each Contributor provides its Contributions) on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied,
including, without limitation, any warranties or conditions of TITLE,
NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A PARTICULAR PURPOSE. You are
solely responsible for determining the appropriateness of using or
redistributing the Work and assume any risks associated with Your exercise of
permissions under this License.

8. Limitation of Liability.

In no event and under no legal theory, whether in tort (including negligence),
contract, or otherwise, unless required by applicable law (such as deliberate
and grossly negligent acts) or agreed to in writing, shall any Contributor be
liable to You for damages, including any direct, indirect, special, incidental,
or consequential damages of any character arising as a result of this License or
out of the use or inability to use the Work (including but not limited to
damages for loss of goodwill, work stoppage, computer failure or malfunction, or
any and all other commercial damages or losses), even if such Contributor has
been advised of the possibility of such damages.

9. Accepting Warranty or Additional Liability.

While redistributing the Work or Derivative Works thereof, You may choose to
offer, and charge a fee for, acceptance of support, warranty, indemnity, or
other liability obligations and/or rights consistent with this License. However,
in accepting such obligations, You may act only on Your own behalf and on Your
sole responsibility, not on behalf of any other Contributor, and only if You
agree to indemnify, defend, and hold each Contributor harmless for any liability
incurred by, or claims asserted against, such Contributor by reason of your
accepting any such warranty or additional liability.

END OF TERMS AND CONDITIONS
 */

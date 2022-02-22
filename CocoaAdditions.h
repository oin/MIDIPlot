#pragma once
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

@interface NSBezierPath (MIDIPlot)
-(CGPathRef)midiPlotCGPath;
-(CGPathRef)midiPlotCGPathClosing:(BOOL)close;
@end

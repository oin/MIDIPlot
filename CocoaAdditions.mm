#import "CocoaAdditions.h"

@implementation NSBezierPath (MIDIPlot)

-(CGPathRef)midiPlotCGPath
{
	return [self midiPlotCGPathClosing:YES];
}

-(CGPathRef)midiPlotCGPathClosing:(BOOL)close
{
	NSUInteger i = 0;
	NSUInteger elementCount = [self elementCount];
	if(elementCount == 0) {
		return nil;
	}
	CGMutablePathRef path = CGPathCreateMutable();
	NSPoint points[3];
	BOOL didClosePath = YES;
	for(NSUInteger i=0; i<elementCount; ++i) {
		switch([self elementAtIndex:i associatedPoints:points]) {
			default: break;
			case NSMoveToBezierPathElement:
				CGPathMoveToPoint(path, nullptr, points[0].x, points[0].y);
				break;
			case NSLineToBezierPathElement:
				CGPathAddLineToPoint(path, nullptr, points[0].x, points[0].y);
				didClosePath = NO;
				break;
			case NSCurveToBezierPathElement:
				CGPathAddCurveToPoint(path, nullptr, points[0].x, points[0].y, points[1].x, points[1].y, points[2].x, points[2].y);
				didClosePath = NO;
				break;
			case NSClosePathBezierPathElement:
				CGPathCloseSubpath(path);
				didClosePath = YES;
				break;
		}
	}
	if(!didClosePath && close) {
		CGPathCloseSubpath(path);
	}
	CGPathRef immutablePath = CGPathCreateCopy(path);
	CGPathRelease(path);
	CFAutorelease(immutablePath);
	return immutablePath;
}

@end

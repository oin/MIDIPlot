#include "Multiplot.h"
#include "CocoaAdditions.h"
#import <QuartzCore/QuartzCore.h>
#include <cstddef>
#include <algorithm>

static NSColor *NSColorFromHex(uint32_t x) {
	const CGFloat r = CGFloat((x & 0xFF0000) >> 16) / 255.0;
	const CGFloat g = CGFloat((x & 0x00FF00) >> 8) / 255.0;
	const CGFloat b = CGFloat(x & 0x0000FF) / 255.0;
	return [NSColor colorWithCalibratedRed:r green:g blue:b alpha:1.0];
}

@interface Multiplot ()
{
	CAShapeLayer *plotLayer[MultiplotValueCapacity];
	CALayer *lineLayer;
	CATextLayer *textLayer[MultiplotValueCapacity];
	float values[MultiplotCapacity][MultiplotValueCapacity];
	size_t plotCount;
	BOOL bidirectional;
	BOOL needsRelayout;
	BOOL needsUpdateTexts;
}
@end

@implementation Multiplot

+(NSArray *)colors
{
	static NSArray *colors = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSMutableArray *array = [NSMutableArray array];
		for(size_t i=0; i<MultiplotCapacity; ++i) {
			[array addObject:NSColorFromHex(MultiplotColor[i])];
		}
		colors = [array copy];
	});
	return colors;
}

-(void)commonInit
{
	self.wantsLayer = YES;
	self.layer.backgroundColor = [[NSColor blackColor] CGColor];

	lineLayer = [CALayer layer];
	lineLayer.backgroundColor = [[NSColor colorWithWhite:1.0 alpha:0.5] CGColor];
	[self.layer addSublayer:lineLayer];

	for(size_t i=0; i<MultiplotCapacity; ++i) {
		NSColor *color = [[Multiplot colors] objectAtIndex:i];
		CAShapeLayer *slayer = [CAShapeLayer layer];
		slayer.fillColor = [[NSColor clearColor] CGColor];
		slayer.strokeColor = [color CGColor];
		slayer.lineWidth = MultiplotLineWidth;
		slayer.lineJoin = kCALineJoinRound;
		[self.layer addSublayer:slayer];
		plotLayer[i] = slayer;
	}

	for(size_t i=0; i<MultiplotCapacity; ++i) {
		NSColor *color = [[Multiplot colors] objectAtIndex:i];
		CATextLayer *tlayer = [CATextLayer layer];
		tlayer.actions = @{@"contents": [NSNull null]};
		tlayer.font = (__bridge CTFontRef)[NSFont boldSystemFontOfSize:10.0];
		tlayer.fontSize = 10.0;
		tlayer.foregroundColor = [color CGColor];
		tlayer.shadowOpacity = 1.0;
		tlayer.shadowColor = [[NSColor blackColor] CGColor];
		tlayer.shadowOffset = CGSizeMake(0.0, -1.0);
		tlayer.shadowRadius = 1.0;
		[self.layer addSublayer:tlayer];
		textLayer[i] = tlayer;
	}

	needsRelayout = YES;
	needsUpdateTexts = YES;

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(backingScaleFactorDidChange:) name:NSWindowDidChangeBackingPropertiesNotification object:nil];
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

-(void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void)awakeFromNib
{
	[self backingScaleFactorDidChange:nil];
}

-(void)setFrame:(NSRect)frame
{
	[super setFrame:frame];

	needsRelayout = YES;
	self.needsDisplay = YES;
}

-(void)setFrameSize:(NSSize)size
{
	[super setFrameSize:size];

	needsRelayout = YES;
	self.needsDisplay = YES;
}

-(BOOL)wantsUpdateLayer
{
	return YES;
}

-(void)updateLayer
{
	if(needsUpdateTexts) {
		needsUpdateTexts = NO;
		[self updateTexts];
	}
	if(needsRelayout) {
		needsRelayout = NO;
		[self relayout];
	}
}

-(void)setLookaheadSamples:(size_t)v
{
	if(v < 16) {
		v = 16;
	}
	if(v > MultiplotValueCapacity) {
		v = MultiplotValueCapacity;
	}
	if(_lookaheadSamples == v) return;
	_lookaheadSamples = v;

	needsRelayout = YES;
	self.needsDisplay = YES;
}

-(void)updateTexts
{
	size_t size = [self.plotTitles count];
	if(plotCount < size) {
		size = plotCount;
	}

	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	for(size_t i=0; i<size; ++i) {
		textLayer[i].string = [self.plotTitles objectAtIndex:i];
	}
	[CATransaction commit];
}

-(NSBezierPath *)pathForPlot:(size_t)i
{
	NSRect bounds = self.bounds;
	bounds.origin.y += 1.0;
	bounds.size.height -= 1.0;
	const size_t lookaheadSamples = self.lookaheadSamples;
	const auto firstSampleI = MultiplotValueCapacity - lookaheadSamples;
	const float samplesPerPixel = float(lookaheadSamples) / float(bounds.size.width);
	const float pixelsPerSample = float(bounds.size.width) / float(lookaheadSamples);
	const float* data = &values[i][firstSampleI];

	NSBezierPath *path = [NSBezierPath bezierPath];

	for(size_t x=0; x<bounds.size.width; ++x) {
		NSPoint p = NSMakePoint(x, 0);
		const float fi = float(x) * samplesPerPixel;
		size_t fii = fi;
		if(fii >= lookaheadSamples) {
			fii = lookaheadSamples - 1;
		}
		size_t fii1 = fii + 1;
		if(fii1 >= lookaheadSamples) {
			fii1 = lookaheadSamples - 1;
		}
		const float q = fi - fii;
		const float v1 = data[fii];
		const float v2 = data[fii1];
		const float v = v1 + q * (v2 - v1);
		if(bidirectional) {
			p.y = (v * 0.5f + 0.5f) * bounds.size.height;
		} else {
			p.y = v * bounds.size.height;
		}
		if(x == 0) {
			[path moveToPoint:p];
		} else {
			[path lineToPoint:p];
		}
	}

	return path;
}

-(NSBezierPath *)precisePathForPlot:(size_t)i
{
	NSRect bounds = self.bounds;
	bounds.origin.y += 1.0;
	bounds.size.height -= 1.0;
	const size_t lookaheadSamples = self.lookaheadSamples;
	const auto firstSampleI = MultiplotValueCapacity - lookaheadSamples;
	const float samplesPerPixel = float(lookaheadSamples) / float(bounds.size.width);
	const float pixelsPerSample = float(bounds.size.width) / float(lookaheadSamples);
	const float* data = &values[i][firstSampleI];

	NSBezierPath *path = [NSBezierPath bezierPath];

	for(size_t i=0; i<lookaheadSamples; ++i) {
		NSPoint p{};
		p.x = (float(i) + float(i) / float(lookaheadSamples)) * pixelsPerSample;
		const float v = data[i];
		if(bidirectional) {
			p.y = (v * 0.5f + 0.5f) * bounds.size.height;
		} else {
			p.y = v * bounds.size.height;
		}
		if(i == 0) {
			[path moveToPoint:p];
		} else {
			[path lineToPoint:p];
		}
	}

	return path;
}

-(void)relayout
{
	CGRect bounds = NSRectToCGRect(self.bounds);
	bounds.origin.y += 1.0;
	bounds.size.height -= 1.0;

	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	BOOL precisionMode = [defaults boolForKey:@"MultiplotPrecisionMode"];

	size_t size = [self.plotTitles count];
	if(plotCount < size) {
		size = plotCount;
	}

	[CATransaction begin];
	[CATransaction setDisableActions:YES];

	if(bidirectional) {
		lineLayer.frame = CGRectMake(0, CGRectGetMidY(bounds), bounds.size.width, 1.0);
	} else {
		lineLayer.frame = CGRectMake(0, CGRectGetMinY(bounds), bounds.size.width, 1.0);
	}

	// Set opacities
	for(size_t i=0; i<MultiplotCapacity; ++i) {
		CGFloat opacity = i < size? 1.0 : 0.0;
		plotLayer[i].opacity = opacity;
		plotLayer[i].frame = bounds;
		textLayer[i].opacity = opacity;
	}

	// Relayout plots
	for(size_t i=0; i<MultiplotCapacity; ++i) {
		CAShapeLayer *slayer = plotLayer[i];
		slayer.path = [(precisionMode? [self precisePathForPlot:i] : [self pathForPlot:i]) midiPlotCGPathClosing:NO];
		slayer.frame = bounds;
	}

	// Relayout titles
	constexpr const CGFloat padding = 4;
	CGPoint p = CGPointMake(padding, padding);
	CGFloat lineWidth = 0.0;
	for(size_t i=0; i<size; ++i) {
		NSString *title = [self.plotTitles objectAtIndex:i];
		CGSize titleSize = [textLayer[i] preferredFrameSize];
		if(p.y + titleSize.height + 2 + padding > bounds.size.height) {
			p.y = padding;
			p.x += lineWidth + padding * 2;
		}
		if(lineWidth < titleSize.width) {
			lineWidth = titleSize.width;
		}
		textLayer[i].frame = CGRectMake(p.x, bounds.size.height - p.y - titleSize.height, titleSize.width, titleSize.height);
		p.y += titleSize.height + 2;
	}

	[CATransaction commit];
}

-(void)scrollWheel:(NSEvent *)event
{
	[self.delegate scrollWheelFromMultiplot:self event:event];
}

-(void)magnifyWithEvent:(NSEvent *)event
{
	[self.delegate magnifyFromMultiplot:self event:event];
}

-(void)rightMouseDown:(NSEvent *)event
{
	[self.delegate rightMouseDownFromMultiplot:self event:event];
}

-(void)clear
{
	std::fill_n(&values[0][0], MultiplotCapacity * MultiplotValueCapacity, 0.f);
	bidirectional = NO;
	plotCount = 0;

	needsRelayout = YES;
	needsUpdateTexts = YES;
	self.needsDisplay = YES;
}

-(void)update
{
	needsRelayout = YES;
	needsUpdateTexts = YES;
	self.needsDisplay = YES;
}

-(void)appendValues:(float *)buffer size:(size_t)size forPlot:(NSUInteger)plot
{
	if(plot > MultiplotCapacity) {
		return;
	}
	if(plot >= plotCount) {
		plotCount = plot + 1;
		needsUpdateTexts = YES;
	}

	// Shift existing values
	std::copy_n(&values[plot][size], MultiplotValueCapacity - size, &values[plot][0]);
	// Add new ones at the end
	for(size_t i=0; i<size; ++i) {
		values[plot][MultiplotValueCapacity - size + i] = buffer[i];
		if(buffer[i] < 0.f) {
			bidirectional = YES;
		}
	}
	std::copy_n(buffer, size, &values[plot][MultiplotValueCapacity - size]);

	needsRelayout = YES;
	self.needsDisplay = YES;
}

-(const float*)valuesForPlot:(NSUInteger)plot
{
	return values[plot];
}

+(NSColor *)colorForPlot:(NSUInteger)plot
{
	if(plot >= MultiplotCapacity) {
		return nil;
	}
	return NSColorFromHex(MultiplotColor[plot]);
}

-(void)backingScaleFactorDidChange:(NSNotification *)notification
{
	CGFloat backingScaleFactor = [self.window.screen backingScaleFactor];
	for(size_t i=0; i<MultiplotCapacity; ++i) {
		textLayer[i].contentsScale = backingScaleFactor;
	}
}

@end


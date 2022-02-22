#pragma once
#import <Cocoa/Cocoa.h>
#include <cstddef>

constexpr const size_t MultiplotCapacity = 8;
constexpr const uint32_t MultiplotColor[MultiplotCapacity] = { 0xFF3B30, 0xFF9500, 0xFFCC00, 0x4CD964, 0x5AC8FA, 0x007AFF, 0x5856D6, 0xFF2D55 };
constexpr const size_t MultiplotValueCapacity = 8192;
constexpr const CGFloat MultiplotLineWidth = 1.5;

@class Multiplot;

@protocol MultiplotDelegate <NSObject>
-(void)rightMouseDownFromMultiplot:(Multiplot *)mp event:(NSEvent *)event;
-(void)scrollWheelFromMultiplot:(Multiplot *)mp event:(NSEvent *)event;
-(void)magnifyFromMultiplot:(Multiplot *)mp event:(NSEvent *)event;
@end

@interface Multiplot : NSView
@property (nonatomic, assign) size_t lookaheadSamples;
@property (nonatomic, weak) id<MultiplotDelegate> delegate;
@property (nonatomic, copy) NSArray *plotTitles;
-(void)clear;
-(void)update;
-(void)appendValues:(float *)buffer size:(size_t)size forPlot:(NSUInteger)plot;
-(const float*)valuesForPlot:(NSUInteger)plot;
+(NSColor *)colorForPlot:(NSUInteger)plot;
@end

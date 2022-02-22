#pragma once
#import "Multiplot.h"
#import <Cocoa/Cocoa.h>
#include <cstddef>

@interface MultiplotView : NSView <MultiplotDelegate>
@property (nonatomic, assign) size_t lookaheadSamples;
-(NSDictionary *)configuration;
-(void)setConfiguration:(NSDictionary *)configuration;
-(NSRect)contentBounds;

-(NSUInteger)countOfMultiplots;
-(void)removeAllMultiplots;
-(void)addEmptyMultiplot;
-(void)addMultiplotWithKey:(NSString *)key;

-(void)clearAllMultiplots;
-(void)appendValues:(float *)buffer size:(size_t)size forKey:(NSString *)key;
-(void)useKey:(NSString *)key;

-(NSString *)csvOfCurrentData;
-(NSImage *)imageOfCurrentData;
@end

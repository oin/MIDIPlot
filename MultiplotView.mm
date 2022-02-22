#import "MultiplotView.h"
#import "Multiplot.h"

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#define MultiplotViewDefaultsKeySavedSets @"MultiplotViewSavedSets"
static constexpr const CGFloat MultiplotViewPlotHeight = 75.0;

static NSImage *MultiplotViewMenuImageWithColor(NSColor *color) {
	if(!color) {
		return nil;
	}

	NSSize size = NSMakeSize(10, 10);
	NSImage *image = [[NSImage alloc] initWithSize:size];
	[image lockFocus];
	NSBezierPath *path = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0, 0, size.width, size.height)];
	[color setFill];
	[path fill];
	[[NSColor colorWithCalibratedWhite:0.f alpha:0.25f] setStroke];
	[path stroke];
	[image unlockFocus];
	return image;
}

@interface MultiplotAddButton : NSButton
@property (nonatomic, weak) NSView *eventDelegate;
@end
@implementation MultiplotAddButton
-(void)rightMouseDown:(NSEvent *)event
{
	[self.eventDelegate rightMouseDown:event];
}
@end
@interface MultiplotContentView : NSView
@property (nonatomic, weak) NSView *eventDelegate;
@end
@implementation MultiplotContentView
-(BOOL)isOpaque
{
	return YES;
}
-(BOOL)isFlipped
{
	return YES;
}
-(void)drawRect:(NSRect)dirtyRect
{
	NSRect bounds = self.bounds;
	[[NSColor windowBackgroundColor] setFill];
	NSRectFill(bounds);
}
-(void)rightMouseDown:(NSEvent *)event
{
	[self.eventDelegate rightMouseDown:event];
}
@end

@interface MultiplotView ()
{
	BOOL inhibitLookaheadLabel;
	BOOL waitingForGlobalMenuUpdate;
	BOOL hasAlreadyUpdatedGlobalMenuFromAppendingValues;
}
@property (nonatomic, strong) NSMutableArray *multiplots;
@property (nonatomic, strong) NSMutableArray *keysForMultiplots;
@property (nonatomic, strong) NSMutableSet *allKeys;
@property (nonatomic, strong) MultiplotContentView *contentView;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) MultiplotAddButton *addButton;
@property (nonatomic, strong) NSTextField *lookaheadLabel;
@end

@implementation MultiplotView

-(void)awakeFromNib
{
	self.multiplots = [NSMutableArray array];
	self.keysForMultiplots = [NSMutableArray array];
	self.allKeys = [NSMutableSet setWithCapacity:130];

	self.autoresizesSubviews = YES;

	const NSSize contentViewSize = self.frame.size;
	self.scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, contentViewSize.width, contentViewSize.height)];
	self.scrollView.borderType = NSNoBorder;
	self.scrollView.hasVerticalScroller = YES;
	self.scrollView.hasHorizontalScroller = NO;
	self.scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	self.scrollView.autoresizesSubviews = YES;
	self.scrollView.drawsBackground = NO;
	NSSize contentSize = self.scrollView.contentSize;

	self.contentView = [[MultiplotContentView alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
	self.contentView.eventDelegate = self;
	self.contentView.autoresizingMask = NSViewWidthSizable;
	self.scrollView.documentView = self.contentView;
	[self addSubview:self.scrollView];

	self.addButton = [[MultiplotAddButton alloc] initWithFrame:NSMakeRect(0, 0, 100, 25)];
	self.addButton.title = @"Add Plot";
	[self.addButton setButtonType:NSMomentaryLightButton];
	[self.addButton setBezelStyle:NSInlineBezelStyle];
	self.addButton.eventDelegate = self;
	self.addButton.focusRingType = NSFocusRingTypeNone;
	self.addButton.target = self;
	self.addButton.action = @selector(showMenuAtAddButton:);
	[self.contentView addSubview:self.addButton];

	self.lookaheadLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 20)];
	[self.lookaheadLabel setBezeled:NO];
	[self.lookaheadLabel setDrawsBackground:NO];
	[self.lookaheadLabel setEditable:NO];
	[self.lookaheadLabel setSelectable:NO];
	self.lookaheadLabel.textColor = [NSColor whiteColor];

	self.lookaheadSamples = 1000;

	[self rebuildContentView];
}

-(void)commonInit
{

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

-(void)setLookaheadSamples:(size_t)v
{
	if(v < 16) {
		v = 16;
	}
	if(v > MultiplotValueCapacity) {
		v = MultiplotValueCapacity;
	}
	if(v == _lookaheadSamples) return;
	_lookaheadSamples = v;

	if([self.multiplots count] > 0) {
		for(Multiplot *mp in self.multiplots) {
			mp.lookaheadSamples = v;
		}
		self.lookaheadLabel.stringValue = [NSString stringWithFormat:@"%zu last samples", v];
		if(self.lookaheadLabel.superview == nil) {
			[self addSubview:self.lookaheadLabel];
		}
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideLookaheadLabel) object:nil];
		[self performSelector:@selector(hideLookaheadLabel) withObject:nil afterDelay:1.0];
	}
}

-(void)updateGlobalMenu
{
	waitingForGlobalMenuUpdate = NO;
	self.menu = [self globalMenu];
}

-(void)hideLookaheadLabel
{
	[self.lookaheadLabel removeFromSuperview];
}

-(Multiplot *)newMultiplot
{
	Multiplot *mp = [[Multiplot alloc] initWithFrame:NSMakeRect(0, 0, 100, MultiplotViewPlotHeight)];
	mp.autoresizingMask = NSViewWidthSizable;

	mp.lookaheadSamples = self.lookaheadSamples;
	mp.delegate = self;
	
	return mp;
}

-(void)rebuildContentView
{
	while([self.multiplots count] > 0) {
		Multiplot *mp = [self.multiplots objectAtIndex:0];
		[mp removeFromSuperview];
		[self.multiplots removeObjectAtIndex:0];
	}

	const size_t count = [self.keysForMultiplots count];
	for(size_t i=0; i<count; ++i) {
		Multiplot *mp = [self newMultiplot];
		mp.plotTitles = [self.keysForMultiplots objectAtIndex:i];
		[self.contentView addSubview:mp];
		[self.multiplots addObject:mp];
		[mp awakeFromNib];
	}

	[self relayout];
	self.menu = [self globalMenu];
}

-(void)relayout
{
	const size_t count = [self.multiplots count];
	NSSize contentSize = self.scrollView.contentSize;
	contentSize.width -= self.scrollView.scrollerInsets.right;
	CGFloat y = 0;
	for(size_t i=0; i<count; ++i) {
		Multiplot *mp = [self.multiplots objectAtIndex:i];
		[mp setFrame:NSMakeRect(0, y, contentSize.width, MultiplotViewPlotHeight)];
		y += MultiplotViewPlotHeight;
	}
	y += 5;
	NSSize buttonSize = self.addButton.bounds.size;
	buttonSize.width = 100.0;
	[self.addButton setFrame:NSMakeRect((contentSize.width - buttonSize.width) * 0.5, y, buttonSize.width, buttonSize.height)];
	y += buttonSize.height;
	y += 5;
	[self.contentView setFrame:NSMakeRect(0, 0, contentSize.width, y)];

	NSRect bounds = self.bounds;
	[self.lookaheadLabel setFrame:NSMakeRect(5, bounds.size.height - 30, bounds.size.width, 20)];
}

-(void)resizeWithOldSuperviewSize:(NSSize)oldSize
{
	[super resizeWithOldSuperviewSize:oldSize];
	[self relayout];
}

-(NSUInteger)countOfMultiplots
{
	return [self.multiplots count];
}

-(void)_removeMultiplotAtIndex:(NSUInteger)index
{
	Multiplot *mp = [self.multiplots objectAtIndex:index];
	[mp removeFromSuperview];
	[self.multiplots removeObjectAtIndex:index];
	[self.keysForMultiplots removeObjectAtIndex:index];
}

-(void)removeMultiplotAtIndex:(NSUInteger)index
{
	[self _removeMultiplotAtIndex:index];
	[self rebuildContentView];
}

-(void)removeAllMultiplots
{
	while([self.multiplots count] > 0) {
		[self _removeMultiplotAtIndex:0];
	}
	[self rebuildContentView];
}

-(void)clearAllMultiplots
{
	for(Multiplot *mp in self.multiplots) {
		[mp clear];
	}
}

-(void)useKey:(NSString *)key
{
	[self.allKeys addObject:key];
}

-(void)appendValues:(float *)buffer size:(size_t)size forKey:(NSString *)key
{
	const size_t count = [self.keysForMultiplots count];
	for(size_t i=0; i<count; ++i) {
		NSArray *keys = [self.keysForMultiplots objectAtIndex:i];
		NSUInteger index = [keys indexOfObject:key];
		if(index != NSNotFound) {
			Multiplot *m = [self.multiplots objectAtIndex:i];
			[m appendValues:buffer size:size forPlot:index];
		}
	}
	[self.allKeys addObject:key];

	if(!waitingForGlobalMenuUpdate) {
		waitingForGlobalMenuUpdate = YES;
		if(hasAlreadyUpdatedGlobalMenuFromAppendingValues) {
			[self performSelector:@selector(updateGlobalMenu) withObject:nil afterDelay:1.0];
		} else {
			hasAlreadyUpdatedGlobalMenuFromAppendingValues = YES;
			[self updateGlobalMenu];
		}
	}
}

-(NSArray *)allPlottedKeys
{
	NSMutableArray *array = [NSMutableArray array];
	const size_t size = [self.keysForMultiplots count];
	for(size_t i=0; i<size; ++i) {
		NSArray *keys = [self.keysForMultiplots objectAtIndex:i];
		for(NSString *key in keys) {
			if(![array containsObject:key]) {
				[array addObject:key];
			}
		}
	}
	return array;
}

-(NSArray *)allSortedKeys
{
	NSSortDescriptor *descriptor = [NSSortDescriptor sortDescriptorWithKey:@"description" ascending:YES selector:@selector(localizedStandardCompare:)];
	return [self.allKeys sortedArrayUsingDescriptors:@[descriptor]];
}

-(NSMenu *)menuForNewMultiplot
{
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"New Multiplot"];

	NSArray *keys = [self allSortedKeys];
	size_t i = 0;
	for(NSString *key in keys) {
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:key action:@selector(newMultiplotMenuItemClicked:) keyEquivalent:@""];
		item.target = self;
		item.representedObject = key;
		[menu addItem:item];
		++i;
	}
	
	[menu addItem:[NSMenuItem separatorItem]];

	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Add Empty Plot" action:@selector(newMultiplotMenuItemClicked:) keyEquivalent:@""];
	item.target = self;
	[menu addItem:item];

	return menu;
}

-(IBAction)showMenuAtAddButton:(id)sender
{
	NSMenu *menu = [self menuForNewMultiplot];
	menu.minimumWidth = self.addButton.bounds.size.width;
	[menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, self.addButton.bounds.size.height) inView:self.addButton];
}

-(IBAction)newMultiplotMenuItemClicked:(id)sender
{
	NSString *key = [sender representedObject];
	if(!key) {
		[self addEmptyMultiplot];
	} else {
		[self addMultiplotWithKey:key];
	}
}

-(void)addEmptyMultiplot
{
	Multiplot *mp = [self newMultiplot];
	[self.multiplots addObject:mp];
	[self.keysForMultiplots addObject:[NSMutableArray array]];
	[self.contentView addSubview:mp];
	[mp awakeFromNib];
	[self relayout];
}

-(void)addMultiplotWithKey:(NSString *)key
{
	Multiplot *mp = [self newMultiplot];
	[self.multiplots addObject:mp];
	mp.plotTitles = @[key];
	NSMutableArray *keys = [NSMutableArray array];
	[keys addObject:key];
	[self.keysForMultiplots addObject:keys];
	[self.contentView addSubview:mp];
	[mp awakeFromNib];
	[self relayout];
}

-(NSMenu *)menuForMultiplot:(Multiplot *)mp
{
	const auto index = [self.multiplots indexOfObject:mp];
	if(index == NSNotFound) {
		return nil;
	}

	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Multiplot Menu"];

	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Clear Plot" action:@selector(clearMultiplotMenuItemClicked:) keyEquivalent:@""];
	item.target = self;
	item.tag = index;
	[menu addItem:item];

	item = [[NSMenuItem alloc] initWithTitle:@"Remove Plot" action:@selector(removeMultiplotMenuItemClicked:) keyEquivalent:@""];
	item.target = self;
	item.tag = index;
	[menu addItem:item];

	[menu addItem:[NSMenuItem separatorItem]];

	NSArray *keys = [self.keysForMultiplots objectAtIndex:index];
	const size_t size = [keys count];
	for(size_t i=0; i<size; ++i) {
		NSString *key = keys[i];

		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:key action:@selector(multiplotKeyMenuItemClicked:) keyEquivalent:@""];
		item.target = self;
		item.state = NSOnState;
		item.representedObject = key;
		item.tag = index;
		item.image = MultiplotViewMenuImageWithColor([Multiplot colorForPlot:i]);
		[menu addItem:item];
	}

	[menu addItem:[NSMenuItem separatorItem]];

	if(size < MultiplotCapacity) {
		NSArray *allKeys = [self allSortedKeys];
		for(NSString *key in allKeys) {
			if([keys containsObject:key]) {
				continue;
			}

			NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:key action:@selector(multiplotKeyMenuItemClicked:) keyEquivalent:@""];
			item.target = self;
			item.state = NSOffState;
			item.representedObject = key;
			item.tag = index;
			[menu addItem:item];
		}
	}

	return menu;
}

-(IBAction)multiplotKeyMenuItemClicked:(id)sender
{
	const NSUInteger index = [sender tag];
	if(index >= [self countOfMultiplots]) {
		return;
	}
	NSString *key = [sender representedObject];
	if([key length] == 0) {
		return;
	}

	NSMutableArray *keys = [self.keysForMultiplots objectAtIndex:index];
	if([keys containsObject:key]) {
		[keys removeObject:key];
	} else if([keys count] < MultiplotCapacity) {
		[keys addObject:key];
	}

	Multiplot *mp = [self.multiplots objectAtIndex:index];
	mp.plotTitles = keys;
	[mp update];
}

-(IBAction)removeMultiplotMenuItemClicked:(id)sender
{
	const NSUInteger index = [sender tag];
	if(index >= [self countOfMultiplots]) {
		return;
	}
	[self removeMultiplotAtIndex:index];
}

-(IBAction)clearMultiplotMenuItemClicked:(id)sender
{
	const NSUInteger index = [sender tag];
	if(index >= [self countOfMultiplots]) {
		return;
	}
	[[self.multiplots objectAtIndex:index] clear];
}

-(void)rightMouseDownFromMultiplot:(Multiplot *)mp event:(NSEvent *)event
{
	const auto index = [self.multiplots indexOfObject:mp];
	if(index == NSNotFound) {
		return;
	}
	NSMenu *menu = [self menuForMultiplot:mp];
	[menu popUpMenuPositioningItem:nil atLocation:[NSEvent mouseLocation] inView:nil];
}

-(void)magnifyFromMultiplot:(Multiplot *)mp event:(NSEvent *)event
{
	const float d = event.magnification;
	CGFloat v = float(self.lookaheadSamples) / float(MultiplotValueCapacity);
	v = sqrt(v);
	v -= d * 0.5;
	if(v < 0.0) {
		v = 0.0;
	}
	v = v * v;
	self.lookaheadSamples = v * float(MultiplotValueCapacity);
}

-(void)scrollWheelFromMultiplot:(Multiplot *)mp event:(NSEvent *)event
{
	const auto shouldScroll = (event.modifierFlags & (NSShiftKeyMask | NSCommandKeyMask | NSAlternateKeyMask)) == 0;
	if(shouldScroll) {
		[self.scrollView scrollWheel:event];
		return;
	}

	const float d = event.scrollingDeltaY;
	CGFloat v = float(self.lookaheadSamples) / float(MultiplotValueCapacity);
	v = sqrt(v);
	v -= d * 0.001;
	if(v < 0.0) {
		v = 0.0;
	}
	v = v * v;
	self.lookaheadSamples = v * float(MultiplotValueCapacity);
}

-(NSDictionary *)configuration
{
	return @{ @"lookaheadSamples": @(self.lookaheadSamples), @"keysForMultiplots": [self.keysForMultiplots copy] };
}

-(void)setConfiguration:(NSDictionary *)configuration
{
	while([self.multiplots count] > 0) {
		[self _removeMultiplotAtIndex:0];
	}
	NSNumber *lookaheadSamples = configuration[@"lookaheadSamples"];
	if(lookaheadSamples) {
		self.lookaheadSamples = [lookaheadSamples unsignedIntValue];
	}
	NSArray *keysForMultiplots = configuration[@"keysForMultiplots"];
	if(keysForMultiplots) {
		NSMutableArray *array = [NSMutableArray array];
		for(NSArray *keys in keysForMultiplots) {
			[array addObject:[NSMutableArray arrayWithArray:keys]];
		}
		self.keysForMultiplots = array;
	}
	[self rebuildContentView];
}

+(NSString *)humanReadableStringForConfiguration:(NSDictionary *)configuration
{
	NSArray *keysForMultiplots = configuration[@"keysForMultiplots"];
	if(!keysForMultiplots) {
		return @"";
	}
	NSMutableArray *strs = [NSMutableArray array];
	NSMutableArray *countstrs = [NSMutableArray array];
	for(NSArray *keys in keysForMultiplots) {
		[strs addObject:[keys componentsJoinedByString:@"+"]];
		[countstrs addObject:[NSString stringWithFormat:@"%lu", [keys count]]];
	}
	NSString *str = [strs componentsJoinedByString:@" "];
	str = [NSString stringWithFormat:@"%@ (%d samples)", str, [configuration[@"lookaheadSamples"] intValue]];
	if([str length] > 80) {
		return [NSString stringWithFormat:@"%lu plots (%@; %d samples)", [strs count], [countstrs componentsJoinedByString:@", "], [configuration[@"lookaheadSamples"] intValue]];
	}
	return str;
}

-(NSArray *)savedMultiplotSets
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSArray *sets = [defaults arrayForKey:MultiplotViewDefaultsKeySavedSets];
	if(!sets) {
		sets = [NSArray array];
	}
	return sets;
}

-(void)saveCurrentMultiplotSetWithName:(NSString *)name
{
	NSMutableArray *array = [NSMutableArray arrayWithArray:[self savedMultiplotSets]];
	NSDictionary *entry = @{ @"name": name, @"configuration": [self configuration] };
	[array addObject:entry];
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:array forKey:MultiplotViewDefaultsKeySavedSets];
}

-(void)removeMultiplotSetWithEntry:(NSDictionary *)entry
{
	NSMutableArray *array = [NSMutableArray arrayWithArray:[self savedMultiplotSets]];
	[array removeObject:entry];
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:array forKey:MultiplotViewDefaultsKeySavedSets];
}

-(NSMenu *)globalMenu
{
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Plots"];
	NSMenuItem *item = nil;

	item = [[NSMenuItem alloc] initWithTitle:@"Add Plot" action:nil keyEquivalent:@""];
	item.submenu = [self menuForNewMultiplot];
	[menu addItem:item];

	item = [[NSMenuItem alloc] initWithTitle:@"Remove All Plots" action:@selector(removeAllMultiplotsMenuItemClicked:) keyEquivalent:@"0"];
	item.keyEquivalentModifierMask = NSCommandKeyMask;
	item.target = self;
	[menu addItem:item];

	const auto size = [self.keysForMultiplots count];
	if(size > 0) {
		item = [[NSMenuItem alloc] initWithTitle:@"Save Plotset As…" action:@selector(saveNewMultiplotSetMenuItemClicked:) keyEquivalent:@"S"];
		item.keyEquivalentModifierMask = NSCommandKeyMask | NSShiftKeyMask;
		item.target = self;
		[menu addItem:item];

		item = [[NSMenuItem alloc] initWithTitle:@"Copy Plotset Data To Clipboard As CSV" action:@selector(copyCSVOfAllPlotsetsMenuItemClicked:) keyEquivalent:@"c"];
		item.keyEquivalentModifierMask = NSCommandKeyMask | NSShiftKeyMask;
		item.target = self;
		[menu addItem:item];

		item = [[NSMenuItem alloc] initWithTitle:@"Copy Plotset Image To Clipboard" action:@selector(screenshotAllPlotsetsMenuItemClicked:) keyEquivalent:@"c"];
		item.keyEquivalentModifierMask = NSCommandKeyMask | NSControlKeyMask;
		item.target = self;
		[menu addItem:item];
	}

	[menu addItem:[NSMenuItem separatorItem]];

	NSArray *sets = [self savedMultiplotSets];
	if([sets count] > 0) {
		NSArray *keyEquivalents = @[@"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8", @"9"];
		size_t keyEquivalentI = 0;
		for(NSDictionary *entry in sets) {
			NSString *name = entry[@"name"];
			NSArray *configuration = entry[@"configuration"];
			if(!name || !configuration) {
				continue;
			}

			item = [[NSMenuItem alloc] initWithTitle:name action:@selector(useMultiplotSetMenuItemClicked:) keyEquivalent:@""];
			if(keyEquivalentI < 9) {
				item.keyEquivalent = [keyEquivalents objectAtIndex:keyEquivalentI];
			}
			item.target = self;
			item.representedObject = entry[@"configuration"];
			[menu addItem:item];

			item = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Remove Plotset \"%@\"", name] action:@selector(removeMultiplotSetMenuItemClicked:) keyEquivalent:@""];
			if(keyEquivalentI < 9) {
				item.keyEquivalent = [keyEquivalents objectAtIndex:keyEquivalentI];
			}
			item.target = self;
			item.representedObject = entry;
			item.keyEquivalentModifierMask = NSAlternateKeyMask;
			item.alternate = YES;
			[menu addItem:item];
			++keyEquivalentI;
		}

		[menu addItem:[NSMenuItem separatorItem]];

		item = [[NSMenuItem alloc] initWithTitle:@"Remove All Plotsets" action:@selector(removeAllPlotsetsMenuItemClicked:) keyEquivalent:@""];
		item.target = self;
		[menu addItem:item];
	}

	return menu;
}

-(IBAction)useMultiplotSetMenuItemClicked:(id)sender
{
	NSDictionary *configuration = [sender representedObject];
	if([configuration count] == 0) {
		return;
	}
	[self setConfiguration:configuration];
}

-(IBAction)removeMultiplotSetMenuItemClicked:(id)sender
{
	NSDictionary *entry = [sender representedObject];
	if([entry count] == 0) {
		return;
	}
	[self removeMultiplotSetWithEntry:entry];
}

-(IBAction)removeAllPlotsetsMenuItemClicked:(id)sender
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults removeObjectForKey:MultiplotViewDefaultsKeySavedSets];
}

-(IBAction)saveNewMultiplotSetMenuItemClicked:(id)sender
{
	NSAlert *alert = [[NSAlert alloc] init];
	alert.messageText = @"Save Plotset As…";
	alert.informativeText = @"Please enter a name for the new plotset.";
	NSButton *button = nil;
	[alert addButtonWithTitle:@"Save"];
	[alert addButtonWithTitle:@"Cancel"];
	NSTextField *accessory = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 20)];
	accessory.placeholderString = @"Plotset name";
	accessory.stringValue = [MultiplotView humanReadableStringForConfiguration:[self configuration]];
	alert.accessoryView = accessory;
	alert.window.initialFirstResponder = accessory;
	[alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
		if(returnCode != NSAlertFirstButtonReturn) return;
		NSString *name = [accessory.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if([name length] == 0) {
			NSArray *sets = [self savedMultiplotSets];
			name = [NSString stringWithFormat:@"Untitled Plotset %lu", [sets count]];
		}
		[self saveCurrentMultiplotSetWithName:name];
	}];
}

-(IBAction)removeAllMultiplotsMenuItemClicked:(id)sender
{
	[self removeAllMultiplots];
}

-(IBAction)copyCSVOfAllPlotsetsMenuItemClicked:(id)sender
{
	NSPasteboard* pboard = [NSPasteboard generalPasteboard];
	[pboard clearContents];
	[pboard writeObjects:@[[self csvOfCurrentData]]];
}

-(IBAction)screenshotAllPlotsetsMenuItemClicked:(id)sender
{
	NSPasteboard* pboard = [NSPasteboard generalPasteboard];
	[pboard clearContents];
	[pboard writeObjects:@[[self imageOfCurrentData]]];

	// Play a shutter sound
	if(![[NSUserDefaults standardUserDefaults] boolForKey:@"InhibitShutterSound"]) {
		NSSound *sound = [NSSound soundNamed:@"PhotoShutter"];
		if([sound isPlaying]) {
			[sound setCurrentTime:0];
		} else {
			[sound play];
		}
	}
}

-(IBAction)screenshotMultiplotMenuItemClicked:(id)sender
{
	NSUInteger plot = [sender tag];
	if(plot > [self.multiplots count]) {
		return;
	}
	NSPasteboard* pboard = [NSPasteboard generalPasteboard];
	[pboard clearContents];
	[pboard writeObjects:@[[self imageOfCurrentDataForPlot:[self.multiplots objectAtIndex:plot]]]];

	// Play a shutter sound
	if(![[NSUserDefaults standardUserDefaults] boolForKey:@"InhibitShutterSound"]) {
		NSSound *sound = [NSSound soundNamed:@"PhotoShutter"];
		if([sound isPlaying]) {
			[sound setCurrentTime:0];
		} else {
			[sound play];
		}
	}
}

-(void)rightMouseDown:(NSEvent *)event
{
	NSMenu *menu = [self globalMenu];
	[menu popUpMenuPositioningItem:nil atLocation:[NSEvent mouseLocation] inView:nil];
}

-(NSString *)csvOfCurrentData
{
	NSArray *allPlottedKeys = [self allPlottedKeys];
	NSMutableArray *keys = [NSMutableArray array];
	NSMutableArray *values = [NSMutableArray array];

	// Gather all keys and values
	const size_t countOfAllPlottedKeys = [allPlottedKeys count];
	for(size_t i=0; i<countOfAllPlottedKeys; ++i) {
		NSString *key = [allPlottedKeys objectAtIndex:i];
		const float* v = nullptr;
		const size_t plotCount = [self.keysForMultiplots count];
		for(size_t j=0; j<plotCount; ++j) {
			NSArray *keys = [self.keysForMultiplots objectAtIndex:j];
			NSUInteger indexOfKey = [keys indexOfObject:key];
			if(indexOfKey != NSNotFound) {
				Multiplot *mp = [self.multiplots objectAtIndex:j];
				v = [mp valuesForPlot:indexOfKey];
				break;
			}
		}
		if(!v) {
			continue;
		}
		NSMutableArray *array = [NSMutableArray array];
		for(size_t j=0; j<MultiplotValueCapacity; ++j) {
			[array addObject:@(v[j])];
		}
		[keys addObject:key];
		[values addObject:array];
	}
	
	NSMutableArray *lines = [NSMutableArray array];
	[lines addObject:[[@[@"sample"] arrayByAddingObjectsFromArray:keys] componentsJoinedByString:@", "]];

	const size_t keySize = [keys count];
	if(keySize == 0) {
		return @"";
	}
	size_t lineCount = 0;
	for(size_t i=0; i<MultiplotValueCapacity; ++i) {
		NSMutableArray *array = [NSMutableArray array];
		[array addObject:[NSString stringWithFormat:@"%zu", lineCount]];
		BOOL hasNonZero = NO;
		for(size_t j=0; j<keySize; ++j) {
			const float v = [[[values objectAtIndex:j] objectAtIndex:i] floatValue];
			if(v != 0.f) {
				hasNonZero = YES;
			}
			[array addObject:[NSString stringWithFormat:@"%f", v]];
		}
		if(!hasNonZero) {
			if(lineCount != 0) {
				++lineCount;
			}
			continue;
		}
		[lines addObject:[array componentsJoinedByString:@", "]];
		++lineCount;
	}

	[lines addObject:@""];

	return [lines componentsJoinedByString:@"\n"];
}

-(NSImage *)imageOfCurrentData
{
	NSRect bounds = [self contentBounds];
	NSBitmapImageRep *bmp = [self.contentView bitmapImageRepForCachingDisplayInRect:bounds];
	[self.contentView cacheDisplayInRect:bounds toBitmapImageRep:bmp];
	NSImage *img = [[NSImage alloc] initWithSize:bounds.size];
	[img addRepresentation:bmp];
	return img;
}

-(NSImage *)imageOfCurrentDataForPlot:(Multiplot *)mp
{
	NSRect bounds = mp.bounds;
	NSBitmapImageRep *bmp = [mp bitmapImageRepForCachingDisplayInRect:bounds];
	[mp cacheDisplayInRect:bounds toBitmapImageRep:bmp];
	NSImage *img = [[NSImage alloc] initWithSize:bounds.size];
	[img addRepresentation:bmp];
	return img;
}

-(NSRect)contentBounds
{
	NSRect bounds = self.contentView.bounds;
	bounds.size.height -= 35;
	return bounds;
}

@end

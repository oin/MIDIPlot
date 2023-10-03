#import "MultiplotView.h"
#include <Foundation/Foundation.h>
#import "MidiKeyView.h"
#import <Cocoa/Cocoa.h>
#include "midi_in.hpp"
#include "midi.hpp"
#include <map>

static const size_t value_size = 130 * 17;
static float value[value_size];
static bool value_used[value_size];

@interface MIDIPlot : NSObject
{
	CVDisplayLinkRef displayLink;
	NSMutableArray *keys;
}
+(instancetype)instance;
-(CVReturn)processDisplayLink;
@property (nonatomic, weak) IBOutlet NSWindow *window;
@property (nonatomic, weak) IBOutlet NSMenuItem *plotMenuItem;
@property (nonatomic, weak) IBOutlet MultiplotView *multiplotView;
@property (nonatomic, weak) IBOutlet MidiKeyView *midiKeyView;
@property (nonatomic, strong) IBOutlet NSTextView *logView;
@end

static CVReturn DisplayLinkRenderCallback(CVDisplayLinkRef displayLink, const CVTimeStamp *inNow, const CVTimeStamp *inOutputTime, CVOptionFlags flagsIn, CVOptionFlags *flagsOut, void *displayLinkContext) {
	return [[MIDIPlot instance] processDisplayLink];
}

@implementation MIDIPlot

+(instancetype)instance
{
	return (MIDIPlot *)[[NSApplication sharedApplication] delegate];
}

-(void)applicationWillFinishLaunching:(NSNotification *)aNotification
{
	[self prepareKeys];
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setBool:YES forKey:@"ApplePersistenceIgnoreState"];

	NSString *windowFrame = [defaults stringForKey:@"WindowFrame"];
	if(windowFrame) {
		[self.window setFrame:NSRectFromString(windowFrame) display:YES];
	}
}

-(void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setBool:YES forKey:@"ApplePersistenceIgnoreState"];
	[self.window makeKeyAndOrderFront:nil];

	NSDictionary *multiplotConfiguration = [defaults dictionaryForKey:@"MultiplotConfiguration"];
	if(multiplotConfiguration) {
		[self.multiplotView setConfiguration:multiplotConfiguration];
	}

	[self.multiplotView addObserver:self forKeyPath:@"menu" options:0 context:nullptr];

	dispatch_async(dispatch_get_main_queue(), ^{
		midi_in_init(); // In main queue to get notifications from main run loop
	});

	[self startDisplayLink];
}

-(void)applicationWillTerminate:(NSNotification *)aNotification
{
	[self stopDisplayLink];
	[self.multiplotView removeObserver:self forKeyPath:@"menu"];
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:self.multiplotView.configuration forKey:@"MultiplotConfiguration"];
	[defaults setObject:NSStringFromRect(self.window.frame) forKey:@"WindowFrame"];
}

-(BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
	return YES;
}

-(void)awakeFromNib
{
	[self updatePlotMenuItem];
}

-(void)prepareKeys
{
	keys = [NSMutableArray array];
	[keys addObject:@"bend"];
	[keys addObject:@"aftouch"];
	for(size_t i=0; i<128; ++i) {
		[keys addObject:[NSString stringWithFormat:@"cc%zu", i]];
	}

	for(size_t j=0; j<16; ++j) {
		[keys addObject:[NSString stringWithFormat:@"ch%zu/bend", j+1]];
		[keys addObject:[NSString stringWithFormat:@"ch%zu/aftouch", j+1]];
		for(size_t i=0; i<128; ++i) {
			[keys addObject:[NSString stringWithFormat:@"ch%zu/cc%zu", j+1, i]];
		}
	}

	NSMutableDictionary *keyLabels = self.multiplotView.keyLabels;
	keyLabels[@"bend"] = @"Pitch-bend";
	keyLabels[@"aftouch"] = @"Channel Aftertouch";
	for(size_t i=0; i<128; ++i) {
		keyLabels[[NSString stringWithFormat:@"cc%zu", i]] = [NSString stringWithFormat:@"CC %zu", i];
	}

	NSMutableDictionary *categoryLabels = self.multiplotView.categoryLabels;
	categoryLabels[@"/"] = @"All channels";
	for(size_t j=0; j<16; ++j) {
		categoryLabels[[NSString stringWithFormat:@"ch%zu", j+1]] = [NSString stringWithFormat:@"Channel %zu", j+1];
	}
}

-(void)updatePlotMenuItem
{
	self.plotMenuItem.submenu = self.multiplotView.menu;
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	if(object == self.multiplotView && [keyPath isEqualToString:@"menu"]) {
		[self updatePlotMenuItem];
	}
}

-(void)startDisplayLink
{
	if(displayLink) {
		[self stopDisplayLink];
	}

	CVDisplayLinkCreateWithActiveCGDisplays(&displayLink);
	CVDisplayLinkSetOutputCallback(displayLink, DisplayLinkRenderCallback, nil);
	CVDisplayLinkStart(displayLink);
}

-(void)stopDisplayLink
{
	CVDisplayLinkStop(displayLink);
	CVDisplayLinkRelease(displayLink);
	displayLink = nil;
}

-(void)updatePlots
{
	for(size_t i=0; i<value_size; ++i) {
		NSString *key = [keys objectAtIndex:i];
		if(value_used[i]) {
			[self.multiplotView useKey:key];
		}
		[self.multiplotView appendValues:&value[i] size:1 forKey:key];
	}
}

-(void)didReceiveNoteOn:(int)note
{
	[self.midiKeyView turnMidiNoteOn:note];
}

-(void)didReceiveNoteOff:(int)note
{
	[self.midiKeyView turnMidiNoteOff:note];
}

-(CVReturn)processDisplayLink
{
	__weak __typeof(self) weakSelf = self;

	dispatch_async(dispatch_get_main_queue(), ^{
		[weakSelf updatePlots];
	});
	return kCVReturnSuccess;
}

-(IBAction)clearAll:(id)sender
{
	[self.multiplotView clearAllMultiplots];
	[self.midiKeyView turnAllNotesOff];
	[self.logView.textStorage setAttributedString:[[NSAttributedString alloc] initWithString:@"" attributes:@{}]];
}

-(void)scrollLogToEnd
{
	[self.logView scrollToEndOfDocument:self];
}

-(void)addSyxlogLineWithString:(NSString *)string
{
	BOOL shouldScroll = fabs(NSMaxY(self.logView.visibleRect) - NSMaxY(self.logView.bounds)) < 25;
	[self.logView.textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:string attributes:@{ NSFontAttributeName: [NSFont fontWithName:@"Monaco" size:10], NSForegroundColorAttributeName: [NSColor controlTextColor] }]];
	if(shouldScroll) {
		[self.logView scrollToEndOfDocument:self];
	}
}

@end

void midi_in_on_message(uint32_t identifier, midi_msg_t m, uint64_t t) {
	const auto status = m.status();
	const auto type = midi_status_type(status);
	bool is_note_on = type == midi_msg_type_note_on;
	if(is_note_on || type == midi_msg_type_note_off) {
		const auto note = m.data1;
		const auto velocity = m.data2;
		if(is_note_on && velocity == 0) {
			is_note_on = false;
		}

		if(is_note_on) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[[MIDIPlot instance] didReceiveNoteOn:note];
			});
		} else {
			dispatch_async(dispatch_get_main_queue(), ^{
				[[MIDIPlot instance] didReceiveNoteOff:note];
			});
		}
	} else if(type == midi_msg_type_pitch_bend) {
		const auto bend = midi_data_pitch_bend(m.data1, m.data2);
		const float v = float(bend) / 8192.f;
		value[0] = v;
		value_used[0] = true;
		value[130 * (m.channel + 1)] = v;
		value_used[130 * (m.channel + 1)] = true;
	} else if(type == midi_msg_type_channel_pressure) {
		const float v = float(m.data1) / 127.f;
		value[1] = v;
		value_used[1] = true;
		value[1 + 130 * (m.channel + 1)] = v;
		value_used[1 + 130 * (m.channel + 1)] = true;
	} else if(type == midi_msg_type_control_change) {
		const float v = float(m.data2) / 127.f;
		value[m.data1 + 2] = v;
		value_used[m.data1 + 2] = true;
		value[2 + m.data1 + 130 * (m.channel + 1)] = v;
		value_used[2 + m.data1 + 130 * (m.channel + 1)] = true;
	}
}

void midi_in_on_syxlog(const char* str, bool aborted) {
	NSString *string = [NSString stringWithFormat:@"%s%s", str, aborted? " [aborted]" : ""];
	dispatch_async(dispatch_get_main_queue(), ^{
		[[MIDIPlot instance] addSyxlogLineWithString:string];
	});
}

int main(int argc, const char* argv[]) {
	return NSApplicationMain(argc, argv);
}

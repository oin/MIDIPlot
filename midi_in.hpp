#pragma once
#import <Foundation/Foundation.h>
#include "midi.hpp"

void midi_in_init();
NSString *midi_in_name(uint32_t identifier);
extern void midi_in_on_message(uint32_t identifier, midi_msg_t, uint64_t t);
extern void midi_in_on_syxlog(const char* str, bool aborted);

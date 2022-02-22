#include "midi_in.hpp"
extern "C" {
	#import <CoreMIDI/CoreMIDI.h>
}
#include <unordered_map>
#include <list>
#include <memory>
#include <cstddef>
#include <cstdint>
#include <cstdio>

// Uncomment this line if you want that all non-realtime status bytes abort the current SysEx, as per the MIDI specification.
// #define RESPECT_SYSEX_ABORT 1
static constexpr uint8_t sysex_id_byte = 0x70;
class syxlog_parser {
public:
	const char* process(uint8_t byte, bool& aborted) {
		const char* str = nullptr;
		if(byte == 0xF0) {
			if(state == state_reading && size) {
				buffer[size] = '\0';
				aborted = true;
				str = buffer;
				size = 0;
			}
			state = state_waiting_id;
			return str;
		}

		switch(state) {
			case state_idle:
				break;
			case state_waiting_id:
				if(byte == sysex_id_byte) {
					state = state_reading;
					size = 0;
				} else {
					state = state_idle;
				}
				break;
			case state_reading:
				if(byte == 0xF7) {
					state = state_idle;
					if(!size) return str;
					buffer[size] = '\0';
					str = buffer;
					size = 0;
				} else if(byte < 0x80) {
					if(size == capacity) {
						// Output the current text and continue with more later
						buffer[size] = ' ';
						buffer[size + 1] = '[';
						buffer[size + 2] = '.';
						buffer[size + 3] = '.';
						buffer[size + 4] = '.';
						buffer[size + 5] = ']';
						buffer[size + 6] = '\0';
						str = buffer;
						size = 0;
					}
					buffer[size] = byte;
					++size;
				}
#if defined(RESPECT_SYSEX_ABORT)
				else if(byte < 0xF8) {
					// Non-realtime status bytes should abort the SysEx
					buffer[size] = '\0';
					aborted = true;
					str = buffer;
					size = 0;
					state = state_idle;
				}
#endif
				break;
		}
		return str;
	}
private:
	static constexpr size_t capacity = 2048;
	enum state_t {
		state_idle,
		state_waiting_id,
		state_reading
	};
	char buffer[capacity + 7];
	size_t size = 0;
	state_t state = state_idle;
};

static bool initialized = false;
static MIDIClientRef client;
static MIDIPortRef input_port;
static NSMutableDictionary *nameDict = nil;
static std::unordered_map<MIDIUniqueID, std::unique_ptr<midi_parser>> parsers;
static std::unordered_map<MIDIUniqueID, std::unique_ptr<syxlog_parser>> syxlog_parsers;
static midi_parser endpoint_parser;
static syxlog_parser endpoint_syxlog_parser;
MIDIEndpointRef midi_in_endpoint = 0;

static NSString *source_name(MIDIEndpointRef source) {
	CFStringRef name = nil;
	MIDIObjectGetStringProperty(source, kMIDIPropertyName, &name);
	if(!name) {
		return nil;
	}
	auto name_length = CFStringGetLength(name);
	if(!name_length) {
		CFRelease(name);
		MIDIObjectGetStringProperty(source, kMIDIPropertyDisplayName, &name);
		if(!name) {
			return nil;
		}
	}
	return (__bridge NSString *)name;
}

static void on_receive(const MIDIPacketList* list, void*, void* source_refcon) {
	MIDIUniqueID which = reinterpret_cast<uintptr_t>(source_refcon);
	const auto parser = parsers[which].get();
	const auto syxlog_parser = syxlog_parsers[which].get();
	if(!parser) {
		return;
	}

	const MIDIPacket* packet = list->packet;
	for(size_t i=0; i<list->numPackets; ++i) {
		for(size_t j=0; j<packet->length; ++j) {
			parser->process(packet->data[j], [&](auto m) {
				midi_in_on_message(which, m, packet->timeStamp);
			});
			bool aborted = false;
			const char* str = syxlog_parser->process(packet->data[j], aborted);
			if(str) {
				midi_in_on_syxlog(str, aborted);
			}
		}
		packet = MIDIPacketNext(packet);
	}
}

static void on_receive_endpoint(const MIDIPacketList* list, void*, void*) {
	const MIDIPacket* packet = list->packet;
	for(size_t i=0; i<list->numPackets; ++i) {
		for(size_t j=0; j<packet->length; ++j) {
			endpoint_parser.process(packet->data[j], [&](auto m) {
				midi_in_on_message(0, m, packet->timeStamp);
			});
			bool aborted = false;
			const char* str = endpoint_syxlog_parser.process(packet->data[j], aborted);
			if(str) {
				midi_in_on_syxlog(str, aborted);
			}
		}
		packet = MIDIPacketNext(packet);
	}
}

static void add_source(MIDIEndpointRef source) {
	MIDIUniqueID id = 0;
	if(MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &id) == 0) {
		parsers.emplace(std::make_pair(id, std::make_unique<midi_parser>()));
		syxlog_parsers.emplace(std::make_pair(id, std::make_unique<syxlog_parser>()));
		MIDIPortConnectSource(input_port, source, reinterpret_cast<void*>(id));
		[nameDict setObject:source_name(source) forKey:@(id)];
	}
}

static void on_notification(const MIDINotification* message, void*) {
	const auto id = message->messageID;
	const auto added = id == kMIDIMsgObjectAdded;
	const auto removed = id == kMIDIMsgObjectRemoved;
	if(added || removed) {
		const auto info = reinterpret_cast<const MIDIObjectAddRemoveNotification*>(message);
		if(info->childType == kMIDIObjectType_Source) {
			MIDIEndpointRef source = info->child;
			if(added) {
				add_source(source);
			} else {
				MIDIUniqueID id = 0;
				if(MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &id) == 0) {
					MIDIPortDisconnectSource(input_port, source);
					parsers.erase(id);
					syxlog_parsers.erase(id);
				}
			}
		}
	}
}

static void reindex() {
	auto count = MIDIGetNumberOfSources();
	for(size_t i=0; i<count; ++i) {
		MIDIEndpointRef source = MIDIGetSource(i);
		add_source(source);
	}
}

void midi_in_init() {
	if(initialized) return;

	nameDict = [NSMutableDictionary dictionary];

	MIDIClientCreate(CFSTR("MIDIPlot"), on_notification, NULL, &client);
	MIDIInputPortCreate(client, CFSTR("MIDIPlot"), on_receive, NULL, &input_port);
	MIDIDestinationCreate(client, CFSTR("MIDIPlot"), on_receive_endpoint, nullptr, &midi_in_endpoint);
	
	reindex();

	initialized = true;
}

NSString *midi_in_name(uint32_t identifier) {
	return [nameDict objectForKey:@(identifier)];
}

#pragma once
#include <cstdint>
#include <cstddef>

/**
 * @file
 * MIDI functions and types.
 */

/**
 * The byte value of a beginning SysEx message.
 */
constexpr const uint8_t midi_sysex_begin = 0xF0;

/**
 * The byte value of an ending SysEx message.
 */
constexpr const uint8_t midi_sysex_end = 0xF7;

/**
 * A byte value that cannot be part of a SysEx message, and that might be taken as an indicator of an abort.
 */
constexpr const uint8_t midi_sysex_abort = 0xFF;

/**
 * The first invalid MIDI channel.
 */
constexpr const uint8_t midi_channel_invalid = 0x10;

/**
 * An invalid data byte.
 */
constexpr const uint8_t midi_data_invalid = 0x80;

/**
 * An invalid status byte.
 */
constexpr const uint8_t midi_status_invalid = 0;

/**
 * @return true if the given byte is a status byte.
 */
constexpr bool midi_status_is_valid(uint8_t byte) {
	return byte >> 7;
}

/**
 * @return true if the given status byte identifies a channel message, and false if it identifies a system message.
 */
constexpr bool midi_status_is_channel_message(uint8_t status) {
	return (status & 0x70) != 0x70;
}

/**
 * @return true if the given status byte identifies a real-time system message.
 */
constexpr bool midi_status_is_realtime(uint8_t status) {
	return status >= 0xF8;
}

/**
 * @return The channel of the MIDI message represented by the given status byte.
 */
constexpr unsigned midi_status_channel(uint8_t status) {
	return status & 0xF;
}

/*
 * 
 * Classification of MIDI messages:
 * 
 *                        -- voice messages
 *   - channel messages -|   (status 8x to Ex, 1 to 2 data bytes)
 *  |  (80<status<F0)     -- mode messages
 *  |                        (like CC but bit6 of first data byte set)
 * -| 
 *  |                     -- common messages 
 *  |                    |   (status F1 to F6, 0 to 2 data bytes)
 *   -- system messages -|-- real-time messages
 *                       |   (status F8 to FF, no data byte)
 *                        -- exclusive messages
 *                           (stream with bit7=0 between F0=start and F7=end)
 * 
 * (inspired from https://users.cs.cf.ac.uk/Dave.Marshall/Multimedia/node158.html)
 * 
*/

/**
 * A type of MIDI message.
 */
enum midi_msg_type_t : uint8_t {
	midi_msg_type_invalid = 0,
	// Channel messages
	midi_msg_type_note_off = 0x80,
	midi_msg_type_note_on = 0x90,
	midi_msg_type_polyphonic_key_pressure = 0xA0,
	midi_msg_type_control_change = 0xB0,
	midi_msg_type_program_change = 0xC0,
	midi_msg_type_channel_pressure = 0xD0,
	midi_msg_type_pitch_bend = 0xE0,
	// System messages
	/// Common messages
	midi_msg_type_timing_code = 0xF1,
	midi_msg_type_song_position_pointer = 0xF2,
	midi_msg_type_song_select = 0xF3,
	midi_msg_type_undefined_f4 = 0xF4,
	midi_msg_type_undefined_f5 = 0xF5,
	midi_msg_type_tune_request = 0xF6,
	/// Real-time messages
	midi_msg_type_timing_clock = 0xF8,
	midi_msg_type_undefined_f9 = 0xF9,
	midi_msg_type_start_sequence = 0xFA,
	midi_msg_type_continue_sequence = 0xFB,
	midi_msg_type_stop_sequence = 0xFC,
	midi_msg_type_undefined_fd = 0xFD,
	midi_msg_type_active_sensing = 0xFE,
	midi_msg_type_system_reset = 0xFF,
	/// Exclusive messages
	/**
	 * The byte value of a beginning SysEx message.
	 */
	midi_msg_type_sysex_begin = midi_sysex_begin,
	/**
	 * The byte value of an ending SysEx message.
	 */
	midi_msg_type_sysex_end = midi_sysex_end,
};

/**
 * @return true if the given message type identifies a channel message, and false if it identifies a system message.
 */
constexpr bool midi_msg_type_is_channel(midi_msg_type_t t) {
	return (t & 0x70) != 0x70;
}

/**
 * @return A status byte with the given type and MIDI channel, if applicable.
 */
constexpr uint8_t midi_status(midi_msg_type_t t, uint8_t channel) {
	return midi_msg_type_is_channel(t)? (t | channel) : t;
}

/**
 * @return The type of the MIDI message represented by the given status byte, or undefined if it is a data byte.
 */
constexpr midi_msg_type_t midi_status_type(uint8_t status) {
	if(!midi_status_is_valid(status)) return midi_msg_type_invalid;
	if(midi_status_is_channel_message(status)) {
		return midi_msg_type_t(status & 0xF0);
	}
	return midi_msg_type_t(status);
}

/**
 * @return The pitch-bend value (between -8192 and 8191) contained in the given two data bytes.
 */
constexpr int16_t midi_data_pitch_bend(uint8_t data1, uint8_t data2) {
	return int16_t(uint16_t(uint16_t(data2 << 7) | data1)) - 8192;
}

/**
 * @return The number of data bytes following a MIDI message with the given type.
 */
constexpr size_t midi_data_size(midi_msg_type_t type) {
	switch(type) {
		case midi_msg_type_note_off:
		case midi_msg_type_note_on:
		case midi_msg_type_polyphonic_key_pressure:
		case midi_msg_type_control_change:
		case midi_msg_type_pitch_bend:
		case midi_msg_type_song_position_pointer:
			return 2;
		case midi_msg_type_program_change:
		case midi_msg_type_channel_pressure:
		case midi_msg_type_timing_code:
		case midi_msg_type_song_select:
			return 1;
		case midi_msg_type_invalid:
		case midi_msg_type_timing_clock:
		case midi_msg_type_start_sequence:
		case midi_msg_type_continue_sequence:
		case midi_msg_type_stop_sequence:
		case midi_msg_type_active_sensing:
		case midi_msg_type_system_reset:
		case midi_msg_type_tune_request:
		case midi_msg_type_sysex_begin:
		case midi_msg_type_sysex_end:
		default:
			break;
	}
	return 0;
}

/**
 * A non-SysEx MIDI message containing one, two, or three bytes.
 */
struct midi_msg_t {
	midi_msg_type_t type;
	uint8_t channel;
	uint8_t data1;
	uint8_t data2;

	constexpr midi_msg_t() : type(midi_msg_type_invalid), channel(midi_channel_invalid), data1(midi_data_invalid), data2(midi_data_invalid) {}
	constexpr midi_msg_t(midi_msg_type_t type, uint8_t channel, uint8_t data1, uint8_t data2) : type(type), channel(channel), data1(data1), data2(data2) {}
	constexpr midi_msg_t(uint8_t status, uint8_t data1, uint8_t data2) : type(midi_status_type(status)), channel(midi_status_channel(status)), data1(data1), data2(data2) {}
	constexpr midi_msg_t(uint8_t status, uint8_t data1) : midi_msg_t(status, data1, midi_data_invalid) {}
	constexpr midi_msg_t(uint8_t status) : midi_msg_t(status, midi_data_invalid, midi_data_invalid) {}
	constexpr midi_msg_t(const uint8_t* data) : midi_msg_t(data[0], data[1], data[2]) {}

	/**
	 * @return The status byte of the MIDI message.
	 */
	constexpr uint8_t status() const {
		return midi_status(type, channel);
	}
};

/**
 * A byte-per-byte MIDI parser with running status and SysEx support.
 */
class midi_parser {
public:
	/**
	 * Reset the MIDI state machine, abandoning any ongoing message.
	 */
	void reset() {
		offset = 0;
		expected = 0;
		status = 0;
	}

	/**
	 * A function called when a complete MIDI message that is not a SysEx (system exclusive message) has been received.
	 */
	using message_fn_t = void(midi_msg_t, bool running_status);
	
	/**
	 * Process the next byte from a MIDI stream, and call one of the given functions if a new MIDI message has been detected.
	 * 
	 * @param byte The next byte of a MIDI stream.
	 * @param message_fn A function that is called when a complete new MIDI message that is not a SysEx (system exclusive message) has been received (see message_fn_t).
	 */
	template <typename MessageFn>
	void process(uint8_t byte, MessageFn message_fn) {
		auto t = midi_status_type(byte);
		if(t != midi_msg_type_invalid) {
			// This is a status byte.
			if(midi_status_is_realtime(byte)) {
				// Real-time messages are handled transparently, without interrupting another ongoing message.
				message_fn(midi_msg_t(byte));
				return;
			} else {
				// If we were previously involved in a SysEx, we should end it before anything else.
				if(status == midi_sysex_begin) {
					status = 0;
				}
				if(t == midi_sysex_end) {
					// If the new byte is a SysEx end byte (0xF7), then ignore it (if there was a SysEx, it has already passed).
					offset = 0;
					status = 0;
					expected = 0;
				} else {
					// Else, start over with the beginning of a new MIDI message, a new adventure, new horizons!
					status = byte;
					expected = midi_data_size(t);
					offset = 0;

					if(t == midi_sysex_begin) {
						return;
					}
				}
			}
		} else {
			// This is a data byte.
			if(status != 0) {
				// As there is a current status, it makes sense to handle the byte.
				if(expected != 0) {
					// This is one we expected to receive, so let's handle it.
					if(offset < 2) {
						data[offset++] = byte;
						--expected;
					}
				} else {
					// We hadn't been expecting any more data at this point, except if we're in the middle of a SysEx, or in case of running status.
					if(status == midi_sysex_begin) {
						return;
					} else if(midi_status_is_channel_message(status)) {
						// If the previous status message was a channel message, this is the first data byte of a new MIDI message with "running status".
						data[0] = byte;
						offset = 1;
						expected = midi_data_size(midi_status_type(status)) - 1;
					} else {
						// Else, ignore the byte.
						return;
					}
				}
			} else {
				// Else, ignore the byte.
				return;
			}
		}

		if(status != 0 && expected == 0) {
			// If we don't expect any more bytes to come for the current MIDI message, we can signal it.
			uint8_t buffer[3] = {status, data[0], data[1]};
			message_fn(midi_msg_t(buffer));
		}
	}
private:
	size_t offset = 0;
	uint8_t data[2] = {0};
	uint8_t expected = 0;
	uint8_t status = 0;
};

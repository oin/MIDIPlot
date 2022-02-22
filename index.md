# MIDIPlot

MIDIPlot is a small utility designed to quickly visualize MIDI CC, pitch-bend, and channel aftertouch in real-time.

![The main window of MIDIPlot, with its three zones detailed](https://github.com/oin/MIDIPlot/raw/main/README.png)

The main window consists of three zones:

 - The **Plot Area** allows you to monitor MIDI CC, pitch-bend and channel aftertouch values.
 - The **Note View** displays the currently played MIDI notes.
 - **[syxlog](https://github.com/oin/syxlog) messages** are appended to a text view in the order they arrive.

# Download

- [MIDIPlot v1.0](https://github.com/oin/MIDIPlot/releases/tag/v1.0) (macOS 10.9+, Intel and Apple Silicon)

# How to use

MIDIPlot automatically connects to all available MIDI sources and listens to all channels at once.

You can add an arbitrary number of plots into the Plot Area, either by using the _Plots_ menu, by right-clicking the empty space in the Plot Area, or by clicking the _Add Plot_ button.
Press _Cmd+0_ to remove all plots.

Each plot can display up to 8 signals, each with its own color.
_Right-click a plot_ to add or remove signals.

To adjust the speed at which signals scroll, shift-scroll using your mouse, or use a zoom gesture using your trackpad.

In the _Plots_ menu (or in the contextual menu displayed by right-clicking the empty space in the Plot Area), you can save the current plot configuration as a _Plot Set_ to be recalled later.
The first 9 plot sets can be recalled instantly by pressing _Cmd+1_ to _Cmd+9_, or by selecting the corresponding entry in the _Plots_ menu.

Press _Cmd+K_ to clear all (plots, stuck MIDI keys, as well as [syxlog](https://github.com/oin/syxlog) messages).

# Acknowledgements

This project uses code from [MidiKeys](https://github.com/flit/MidiKeys).

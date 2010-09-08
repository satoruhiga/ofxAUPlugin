#pragma once

#include "ofMain.h"

#include "CAAUProcessor.h"

class ofxAUPlugin
{
	static vector<CAComponent*> components;
	static bool _inited;
	static int _sampleRate, _bufferSize;
	static void loadPlugins();
	
	static OSStatus inputCallback(void *inRefCon,
								  AudioUnitRenderActionFlags *ioActionFlags,
								  const AudioTimeStamp *inTimeStamp,
								  UInt32 inBusNumber,
								  UInt32 inNumberFrames,
								  AudioBufferList *ioData);
	
	vector<float> inputBuffer;
	AUOutputBL *outputBuffer;
	CAAUProcessor *processor;
	
	int _numInputCh, _numOutputCh;
	
	void clear();
	void initProcessor(CAComponent comp);
	
public:
	
	static void init(int sampleRate = 44100, int bufferSize = 512);
	static void listPlugins();
	
	ofxAUPlugin();
	virtual ~ofxAUPlugin();
	
	void loadPlugin(string name);
	void loadPreset(string path);
	
	const int numInput() const { return _numInputCh; };
	const int numOutput() const { return _numOutputCh; };
	
	void process(const float *input, float *output);
};
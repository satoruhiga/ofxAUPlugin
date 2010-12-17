#pragma once

#include "ofMain.h"

#include "CAAUProcessor.h"

class ofxAUPlugin
{
public:

	struct ParamInfo
	{
		int paramID;
		string name;
		float minValue, maxValue;
	};
	
private:

	static vector<CAComponent *> components;
	static bool inited;
	static int sampleRate, bufferSize;
	static void loadPlugins();

	static OSStatus inputCallback(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData);

	vector<float> inputBuffer;
	AUOutputBL *outputBuffer;
	CAAUProcessor *processor;

	int numInputCh, numOutputCh;

	void clear();
	void initProcessor(CAComponent comp);
	void initParameter();

	vector<ParamInfo> paramsInfo;

public:

	static void init(int sampleRate = 44100, int bufferSize = 512);
	static void listPlugins();

	ofxAUPlugin();
	virtual ~ofxAUPlugin();

	void loadPlugin(string name);
	void loadPreset(string path);

	const int numInput() const { return numInputCh; }
	const int numOutput() const { return numOutputCh; }
	
	void dumpParamNames();

	vector<ParamInfo> getParamsInfo() { return paramsInfo; }

	float getParamValue(int paramID);
	void setParamValue(int paramID, float value);

	void process(const float *input, float *output);
	
	void bypass(bool yn);
};

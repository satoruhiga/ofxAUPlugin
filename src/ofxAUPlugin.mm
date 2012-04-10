#include "ofxAUPlugin.h"

vector<CAComponent*> ofxAUPlugin::components;
bool ofxAUPlugin::inited = false;

int ofxAUPlugin::sampleRate = 44100;
int ofxAUPlugin::bufferSize = 512;

void ofxAUPlugin::loadPlugins()
{
	for (int i = 0; i < components.size(); i++)
	{
		delete components[i];
	}

	components.clear();

	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	ComponentDescription cd;
	Component comp;

	cd.componentType = kAudioUnitType_Effect;
	cd.componentSubType = 0;
	cd.componentManufacturer = 0;
	cd.componentFlags = 0;
	cd.componentFlagsMask = 0;

	comp = FindNextComponent(NULL, &cd);

	while (comp != NULL)
	{
		components.push_back(new CAComponent(comp));
		comp = FindNextComponent(comp, &cd);
	}

	[pool release];
}

void ofxAUPlugin::init(int sampleRate, int bufferSize)
{
	if (inited == false)
	{
		inited = true;
		ofxAUPlugin::sampleRate = sampleRate;
		ofxAUPlugin::bufferSize = bufferSize;

		loadPlugins();
	}
}

void ofxAUPlugin::listPlugins()
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	for (int i = 0; i < components.size(); i++)
	{
		printf("[%i] - %s\n", i, [(NSString*)components[i]->GetCompName() UTF8String]);
	}

	[pool release];
}

ofxAUPlugin::ofxAUPlugin()
{
	outputBuffer = NULL;
	processor = NULL;
	numInputCh = numOutputCh = 0;

	clear();
}

ofxAUPlugin::~ofxAUPlugin()
{
	clear();
}

void ofxAUPlugin::clear()
{
	if (outputBuffer)
	{
		delete outputBuffer;
		outputBuffer = NULL;
	}

	if (processor)
	{
		delete processor;
		processor = NULL;
	}
}

void ofxAUPlugin::initProcessor(CAComponent comp)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	clear();

	processor = new CAAUProcessor(comp);

	CAStreamBasicDescription input_format, output_format;

	assert(processor->AU().GetFormat(kAudioUnitScope_Input, 0, input_format) == noErr);
	assert(processor->AU().GetFormat(kAudioUnitScope_Output, 0, output_format) == noErr);

	numInputCh = input_format.NumberChannels();
	numOutputCh = output_format.NumberChannels();

	assert(numInputCh > 0 || numOutputCh > 0);

	assert(processor->Initialize(input_format, output_format, 0) == noErr);
	assert(processor->Preflight() == noErr);

	AURenderCallbackStruct cb;
	cb.inputProc = ofxAUPlugin::inputCallback;
	cb.inputProcRefCon = this;

	assert(processor->EstablishInputCallback(cb) == noErr);

	outputBuffer = new AUOutputBL(output_format, bufferSize);
	outputBuffer->Allocate(bufferSize);
	outputBuffer->Prepare();

	[pool release];

	initParameter();
}

void ofxAUPlugin::initParameter()
{
	CAAudioUnit &au = processor->AU();

	// get parameter size

	UInt32 size;
	AudioUnitGetPropertyInfo(au.AU(),
		kAudioUnitProperty_ParameterList,
		kAudioUnitScope_Global,
		0,
		&size,
		NULL);

	int numOfParams = size / sizeof(AudioUnitParameterID);

	vector<AudioUnitParameterID> paramList(numOfParams, 0);

	// get parameter id list

	AudioUnitGetProperty(au.AU(),
		kAudioUnitProperty_ParameterList,
		kAudioUnitScope_Global,
		0,
		&paramList[0],
		&size);

	paramsInfo.clear();

	// get parameters info

	for (int i = 0; i < paramList.size(); i++)
	{
		AudioUnitParameterInfo paramInfo;
		UInt32 size = sizeof(AudioUnitParameterInfo);

		AudioUnitGetProperty(au.AU(),
			kAudioUnitProperty_ParameterInfo,
			kAudioUnitScope_Global,
			paramList[i],
			&paramInfo,
			&size);

		ParamInfo info;
		info.paramID = paramList[i];
		info.name = paramInfo.name;
		info.minValue = paramInfo.minValue;
		info.maxValue = paramInfo.maxValue;

		paramsInfo[paramInfo.name] = info;
	}
}

void ofxAUPlugin::loadPlugin(string name)
{
	ofxAUPlugin::init();

	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	CAComponent *c = NULL;

	for (int i = 0; i < components.size(); i++)
	{
		string n = [(NSString*)components[i]->GetCompName() UTF8String];

		if (n == name)
		{
			c = components[i];
		}
	}

	if (c == NULL)
	{
		ofLog(OF_LOG_ERROR, "plugin not found: %s", name.c_str());
	}

	clear();

	initProcessor(*c);

	[pool release];
}

void ofxAUPlugin::loadPreset(string path)
{
	ofxAUPlugin::init();

	path = ofToDataPath(path, true);

	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	CAComponent *c = NULL;
	NSDictionary *data = [NSDictionary dictionaryWithContentsOfFile:[NSString stringWithUTF8String:path.c_str()]];

	int type = [[data objectForKey:@"type"] intValue];
	int subtype = [[data objectForKey:@"subtype"] intValue];
	int manufacturer = [[data objectForKey:@"manufacturer"] intValue];

	for (int i = 0; i < components.size(); i++)
	{
		CAComponent comp = CAComponent(type, subtype, manufacturer);

		if (components[i]->Comp() == comp.Comp())
		{
			c = components[i];
			break;
		}
	}

	clear();

	initProcessor(*c);

	assert(processor->SetAUPreset(data) == noErr);

	[pool release];
}

OSStatus ofxAUPlugin::inputCallback(void *inRefCon,
AudioUnitRenderActionFlags *ioActionFlags,
const AudioTimeStamp *inTimeStamp,
UInt32 inBusNumber,
UInt32 inNumberFrames,
AudioBufferList *ioData)
{
	ofxAUPlugin *self = (ofxAUPlugin*)inRefCon;

	for (int c = 0; c < ioData->mNumberBuffers; c++)
	{
		AudioBuffer &buffer = ioData->mBuffers[c];
		const float *src = &self->inputBuffer[0] + c;
		float *dst = (float*)buffer.mData;

		for (int i = 0; i < bufferSize; i++)
		{
			*dst = *src;
			src += self->numInputCh;
			dst += 1;
		}
	}

	return noErr;
}

void ofxAUPlugin::process(const float *input, float *output)
{
	if (processor == NULL || outputBuffer == NULL)
	{
		ofLog(OF_LOG_ERROR, "ofxAUPlugin: not initialized yet");
		return;
	}

	AudioUnitRenderActionFlags flags = 0;
	AudioTimeStamp time;
	memset (&time, 0, sizeof(time));
	time.mSampleTime = ofGetElapsedTimef() * sampleRate;
	time.mFlags = kAudioTimeStampSampleTimeValid;

	inputBuffer.assign(input, input + (bufferSize * numInputCh));

	OSStatus err = noErr;
	bool outIsSilence = false;
	UInt32 frames = bufferSize;
	bool outOLCompleted = false, outOLRequiresPostProcess = false, outDone = false;

	assert(processor->Render(outputBuffer->ABL(), frames, outIsSilence, &outOLCompleted, &outOLRequiresPostProcess) == noErr);

	if (outOLRequiresPostProcess)
	{
		while (!outDone)
		{
			assert(processor->PostProcess(outputBuffer->ABL(), frames, outIsSilence, outDone) == noErr);
		}
	}

	for (int c = 0; c < numOutputCh; c++)
	{
		AudioBuffer &buffer = outputBuffer->ABL()->mBuffers[c];
		float *src = (float*)buffer.mData;
		float *dst = output + c;

		for (int i = 0; i < bufferSize; i++)
		{
			*dst = *src++;
			dst += numOutputCh;
		}
	}
}

void ofxAUPlugin::listParamInfo()
{
	map<string, ParamInfo>::iterator it = paramsInfo.begin();
	
	while (it != paramsInfo.end())
	{
		const ParamInfo &param = (*it).second;
		cout << "#" << param.paramID << ": " << param.name << " [" << param.minValue << " ~ " << param.maxValue << "]" << endl;		
		it++;
	}
}

float ofxAUPlugin::getParam(const string& name)
{
	if (paramsInfo.find(name) == paramsInfo.end()) return 0;
	
	float result;
	ParamInfo &info = paramsInfo[name];
	
	AudioUnitGetParameter(processor->AU().AU(),
						  info.paramID,
						  kAudioUnitScope_Global,
						  0,
						  &result);
	
	return result;
}

void ofxAUPlugin::setParam(const string& name, float value)
{
	if (paramsInfo.find(name) == paramsInfo.end()) return;
	
	ParamInfo &info = paramsInfo[name];
	CAAudioUnit &au = processor->AU();
	
	value = ofClamp(value, info.minValue, info.maxValue);
	
	AudioUnitSetParameter(au.AU(),
						  info.paramID,
						  kAudioUnitScope_Global,
						  0,
						  value,
						  0);
}

void ofxAUPlugin::bypass(bool yn)
{
	if (processor->AU().CanBypass())
		processor->AU().SetBypass(yn);
}
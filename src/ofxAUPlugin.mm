#include "ofxAUPlugin.h"

vector<CAComponent*> ofxAUPlugin::components;
bool ofxAUPlugin::_inited = false;

int ofxAUPlugin::_sampleRate = 44100;
int ofxAUPlugin::_bufferSize = 512;

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
	if (_inited == false)
	{
		_inited = true;
		_sampleRate = sampleRate;
		_bufferSize = bufferSize;
		
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
	_numInputCh = _numOutputCh = 0;
	
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
		
	_numInputCh = input_format.NumberChannels();
	_numOutputCh = output_format.NumberChannels();
	
	assert(_numInputCh > 0 || _numOutputCh > 0);
	
	assert(processor->Initialize(input_format, output_format, 0) == noErr);
	assert(processor->Preflight() == noErr);

	AURenderCallbackStruct cb;
	cb.inputProc = ofxAUPlugin::inputCallback;
	cb.inputProcRefCon = this;
	
	assert(processor->EstablishInputCallback(cb) == noErr);

	outputBuffer = new AUOutputBL(output_format, _bufferSize);
	outputBuffer->Allocate(_bufferSize);
	outputBuffer->Prepare();
	
	[pool release];
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
		
		for (int i = 0; i < _bufferSize; i++)
		{
			*dst = *src; 
			src += self->_numInputCh;
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
	time.mSampleTime = ofGetElapsedTimef() * _sampleRate;
	time.mFlags = kAudioTimeStampSampleTimeValid;
	
	inputBuffer.assign(input, input + (_bufferSize * _numInputCh));
	
	OSStatus err = noErr;
	bool outIsSilence = false;
	UInt32 frames = _bufferSize;
	bool outOLCompleted = false, outOLRequiresPostProcess = false, outDone = false;
	
	assert(processor->Render(outputBuffer->ABL(), frames, outIsSilence, &outOLCompleted, &outOLRequiresPostProcess) == noErr);
	
	if (outOLRequiresPostProcess)
	{
		while (!outDone) {
			assert(processor->PostProcess(outputBuffer->ABL(), frames, outIsSilence, outDone) == noErr);
		}
	}
	
	for (int c = 0; c < _numOutputCh; c++)
	{
		AudioBuffer &buffer = outputBuffer->ABL()->mBuffers[c];
		float *src = (float*)buffer.mData;
		float *dst = output + c;
		
		for (int i = 0; i < _bufferSize; i++)
		{
			*dst = *src++;
			dst += _numOutputCh;
		}
	}
}

#include "testApp.h"

#include "ofxAUPlugin.h"

ofxAUPlugin delay;
ofxAUPlugin reverb;

float pan = 0, pan_t = 0;
float amp = 0, amp_t = 0;

void testApp::audioRequested( float * output, int bufferSize, int nChannels )
{
	//
	// calculate sine wave
	//
	
	static float phase = 0;
	float *ptr = output;
	
	pan_t = ofMap(mouseX, 0, ofGetWidth(), 0, 1, true);
	float freq = ofMap(mouseY, 0, ofGetHeight(), 40, 2000, true);
	
	for (int i = 0; i < bufferSize; i++)
	{
		float s = sin(phase * TWO_PI) * 0.5 * amp;
		*ptr++ = s * cos(pan * HALF_PI);
		*ptr++ = s * sin(pan * HALF_PI);
		phase += freq / 44100.0f;
		if (phase > 1) phase -= 1;
		
		pan += (pan_t - pan) * 0.1;
		amp += (amp_t - amp) * 0.1;
	}
	
	
	//
	// do effect
	//
	
	delay.process(output, output);
	reverb.process(output, output);
}

//--------------------------------------------------------------
void testApp::setup(){
	ofSetVerticalSync(true);
	ofSetFrameRate(60);
	
	ofBackground(0, 0, 0);
	ofSetColor(255, 255, 255);
	
	int samplerate = 44100;
	int buffersize = 1024;
	
	ofxAUPlugin::init(samplerate, buffersize);
	
	//
	// dump installed plugins
	//
	
	ofxAUPlugin::listPlugins();
	
	
	//
	// load plugin from .aupreset file
	//
	
	delay.loadPreset("delay.aupreset");

	
	//
	// or plugin name
	//
	
	reverb.loadPlugin("Apple: AUMatrixReverb");
	
	
	//
	// get plugin's i/o channels count
	//
	
	printf("input ch:%i, output ch:%i\n", delay.numInput(), delay.numOutput());
	
	
	//
	// start sound stream
	//
	
	ofSoundStreamSetup(2, 0, this, samplerate, buffersize, 4);
	
	
	//
	// List prams info
	//
	
	delay.listParamInfo();
	/*
	 you'll get like....
	 
	 #0: dry/wet mix [0 ~ 100]
	 #1: delay time [0.0001 ~ 2]
	 #2: feedback [-99.9 ~ 99.9]
	 #3: lowpass cutoff frequency [10 ~ 22050]
	 */
	
	// so, set feedback param
	delay.setParam("feedback", 99);
}

//--------------------------------------------------------------
void testApp::update(){

}

//--------------------------------------------------------------
void testApp::draw(){
	ofDrawBitmapString("mouse drag to play sound", 20, 20);
}

//--------------------------------------------------------------
void testApp::keyPressed(int key){

}

//--------------------------------------------------------------
void testApp::keyReleased(int key){

}

//--------------------------------------------------------------
void testApp::mouseMoved(int x, int y ){
	delay.setParam("delay time", ofMap(x, 0, ofGetWidth(), 0.0001, 2, true));
}

//--------------------------------------------------------------
void testApp::mouseDragged(int x, int y, int button){
	
}

//--------------------------------------------------------------
void testApp::mousePressed(int x, int y, int button){
	amp_t = 1;
}

//--------------------------------------------------------------
void testApp::mouseReleased(int x, int y, int button){
	amp_t = 0;
}

//--------------------------------------------------------------
void testApp::windowResized(int w, int h){

}


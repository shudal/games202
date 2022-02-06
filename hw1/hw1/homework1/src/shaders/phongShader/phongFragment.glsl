#ifdef GL_ES
precision mediump float;
#endif

// Phong related variables
uniform sampler2D uSampler;
uniform vec3 uKd;
uniform vec3 uKs;
uniform vec3 uLightPos;
uniform vec3 uCameraPos;
uniform vec3 uLightIntensity;

varying highp vec2 vTextureCoord;
varying highp vec3 vFragPos;
varying highp vec3 vNormal;

// Shadow map related variables
#define NUM_SAMPLES 20
#define BLOCKER_SEARCH_NUM_SAMPLES NUM_SAMPLES
#define PCF_NUM_SAMPLES NUM_SAMPLES
#define NUM_RINGS 10

#define EPS 1e-3
#define PI 3.141592653589793
#define PI2 6.283185307179586

uniform sampler2D uShadowMap;

varying vec4 vPositionFromLight;


highp float rand_1to1(highp float x ) { 
  // -1 -1
  return fract(sin(x)*10000.0);
}

highp float rand_2to1(vec2 uv ) { 
  // 0 - 1
	const highp float a = 12.9898, b = 78.233, c = 43758.5453;
	highp float dt = dot( uv.xy, vec2( a,b ) ), sn = mod( dt, PI );
	return fract(sin(sn) * c);
}

float unpack(vec4 rgbaDepth) {
    const vec4 bitShift = vec4(1.0, 1.0/256.0, 1.0/(256.0*256.0), 1.0/(256.0*256.0*256.0));
    return dot(rgbaDepth, bitShift);
}

vec2 poissonDisk[NUM_SAMPLES];

void poissonDiskSamples( const in vec2 randomSeed ) {

  float ANGLE_STEP = PI2 * float( NUM_RINGS ) / float( NUM_SAMPLES );
  float INV_NUM_SAMPLES = 1.0 / float( NUM_SAMPLES );

  float angle = rand_2to1( randomSeed ) * PI2;
  float radius = INV_NUM_SAMPLES;
  float radiusStep = radius;

  for( int i = 0; i < NUM_SAMPLES; i ++ ) {
    poissonDisk[i] = vec2( cos( angle ), sin( angle ) ) * pow( radius, 0.75 );
    radius += radiusStep;
    angle += ANGLE_STEP;
  }
}

void uniformDiskSamples( const in vec2 randomSeed ) {

  float randNum = rand_2to1(randomSeed);
  float sampleX = rand_1to1( randNum ) ;
  float sampleY = rand_1to1( sampleX ) ;

  float angle = sampleX * PI2;
  float radius = sqrt(sampleY);

  for( int i = 0; i < NUM_SAMPLES; i ++ ) {
    poissonDisk[i] = vec2( radius * cos(angle) , radius * sin(angle)  );

    sampleX = rand_1to1( sampleY ) ;
    sampleY = rand_1to1( sampleX ) ;

    angle = sampleX * PI2;
    radius = sqrt(sampleY);
  }
}

float findBlocker( sampler2D shadowMap,  vec2 uv, float zReceiver ) {

  float deepAvg=-1.0;

  float totalDeep=0.0;
  int blockerCnt = 0;
  for (int i=0; i<BLOCKER_SEARCH_NUM_SAMPLES; i++) {
    vec2 x=poissonDisk[i]; 
    x = uv + x * (10.0/2048.0);
    vec4 deepValuePacked=texture2D(uShadowMap,x);
    float deepValue = unpack(deepValuePacked);

    if (deepValue < zReceiver) { 
      totalDeep += deepValue;
      blockerCnt++;
    }
  }
  if (blockerCnt > 0) {
    deepAvg = totalDeep / float(blockerCnt);
  }
	return deepAvg;
}

float PCF(sampler2D shadowMap, vec4 coords) {
  //poissonDiskSamples(coords.xy);
  uniformDiskSamples(coords.xy);
  
  float finalVis=0.0;
  for (int i=0; i<PCF_NUM_SAMPLES; i++) {
    vec2 x=poissonDisk[i];
    
    //x = (x + vec2(1,1)) / 2.0;

    // 5x5附近的格子采样
    // shadowmap采样的像素是2048x2048,因此1/2048是一个像素的长度。采样得到的数值范围是(-1,1)
    x = coords.xy + x * (2.5/2048.0);
    vec4 deepValuePacked=texture2D(uShadowMap,x);
    float deepValue = unpack(deepValuePacked);
    if (deepValue > coords.z) {
      finalVis++;
    }
  }
  finalVis = finalVis / float(PCF_NUM_SAMPLES);
  return finalVis;
}

float PCSS(sampler2D shadowMap, vec4 coords){

  // STEP 1: avgblocker depth
  uniformDiskSamples(coords.xy);
  float d_blocker = findBlocker(shadowMap,coords.xy,coords.z);
  const float w_light=20.0;
  //gl_FragColor = vec4(d_blocker,0,0,1);
  // STEP 2: penumbra size
  float w_p=1.0;
  if (d_blocker > 0.0) {
    w_p = w_light * (coords.z - d_blocker) / d_blocker;
  } 

  // STEP 3: filtering
  
  float finalVis=0.0;
  for (int i=0; i<PCF_NUM_SAMPLES; i++) {
    vec2 x=poissonDisk[i];
       
    x = coords.xy + x * (w_p * 2.5/2048.0);
    vec4 deepValuePacked=texture2D(uShadowMap,x);
    float deepValue = unpack(deepValuePacked);
    if (deepValue > coords.z) {
      finalVis++;
    }
  }
  finalVis = finalVis / float(PCF_NUM_SAMPLES);
  return finalVis;

}


float useShadowMap(sampler2D shadowMap, vec4 shadowCoord){
  vec4 deepValuePacked=texture2D(uShadowMap,shadowCoord.xy);
  float deepValue = unpack(deepValuePacked);

  if (deepValue < shadowCoord.z) {
    return 0.0;
  } else {
    return 1.0;
  } 
}

vec3 blinnPhong() {
  vec3 color = texture2D(uSampler, vTextureCoord).rgb;
  color = pow(color, vec3(2.2));

  vec3 ambient = 0.05 * color;

  vec3 lightDir = normalize(uLightPos);
  vec3 normal = normalize(vNormal);
  float diff = max(dot(lightDir, normal), 0.0);
  vec3 light_atten_coff =
      uLightIntensity / pow(length(uLightPos - vFragPos), 2.0);
  vec3 diffuse = diff * light_atten_coff * color;

  vec3 viewDir = normalize(uCameraPos - vFragPos);
  vec3 halfDir = normalize((lightDir + viewDir));
  float spec = pow(max(dot(halfDir, normal), 0.0), 32.0);
  vec3 specular = uKs * light_atten_coff * spec;

  vec3 radiance = (ambient + diffuse + specular);
  vec3 phongColor = pow(radiance, vec3(1.0 / 2.2));
  return phongColor;
}

void main(void) {

  float visibility;
  
  vec3 shadowCoord;

  vec4 x=(vPositionFromLight + vec4(1,1,1,0)) / 2.0;
  shadowCoord=x.xyz;

  //visibility = useShadowMap(uShadowMap, vec4(shadowCoord, 1.0));
  //visibility = PCF(uShadowMap, vec4(shadowCoord, 1.0));
  visibility = PCSS(uShadowMap, vec4(shadowCoord, 1.0));



  //visibility=1.0;
  vec3 phongColor = blinnPhong();

  //phongColor=vec3(shadowCoord.z,0,0);

  gl_FragColor = vec4(phongColor * visibility, 1.0);
  //gl_FragColor = vec4(phongColor, 1.0);
}
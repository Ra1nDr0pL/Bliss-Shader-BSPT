#include "/lib/settings.glsl"
#include "/lib/res_params.glsl"
#include "/lib/util.glsl"

flat out vec4 lightCol;
flat out vec3 averageSkyCol;
flat out vec3 averageSkyCol_Clouds;

flat out vec4 dailyWeatherParams0;
flat out vec4 dailyWeatherParams1;

flat out vec3 WsunVec;
flat out vec3 refractedSunVec;

// flat out float tempOffsets;

uniform sampler2D colortex4;

uniform float sunElevation;
uniform vec2 texelSize;
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform mat4 gbufferModelViewInverse;
uniform float frameTimeCounter;

#include "/lib/Shadow_Params.glsl"
#include "/lib/sky_gradient.glsl"

//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////
//////////////////////////////VOID MAIN//////////////////////////////

void main() {
	gl_Position = ftransform();

	// gl_Position.xy = (gl_Position.xy*0.5+0.5)*0.51*2.0-1.0;
	gl_Position.xy = (gl_Position.xy*0.5+0.5)*(0.01+VL_RENDER_RESOLUTION)*2.0-1.0;

	lightCol.rgb = vec3(0.0);
	averageSkyCol = vec3(0.0);

	#ifdef OVERWORLD_SHADER
		lightCol.rgb = texelFetch2D(colortex4,ivec2(6,37),0).rgb;
		averageSkyCol = texelFetch2D(colortex4,ivec2(1,37),0).rgb;
		averageSkyCol_Clouds = texelFetch2D(colortex4,ivec2(0,37),0).rgb;
		
		#ifdef Daily_Weather
			dailyWeatherParams0 = vec4(texelFetch2D(colortex4,ivec2(1,1),0).rgb / 1500.0, 0.0);
			dailyWeatherParams1 = vec4(texelFetch2D(colortex4,ivec2(2,1),0).rgb / 1500.0, 0.0);

			dailyWeatherParams0.a = texelFetch2D(colortex4,ivec2(3,1),0).x/1500.0;
			dailyWeatherParams1.a = texelFetch2D(colortex4,ivec2(3,1),0).y/1500.0;
		#else
			dailyWeatherParams0 = vec4(CloudLayer0_coverage, CloudLayer1_coverage, CloudLayer2_coverage, 0.0);
			dailyWeatherParams1 = vec4(CloudLayer0_density, CloudLayer1_density, CloudLayer2_density, 0.0);
		#endif
	#endif

	#ifdef NETHER_SHADER
		averageSkyCol_Clouds = volumetricsFromTex(vec3(0.0,1.0,0.0), colortex4, 6).rgb;
	#endif

	#ifdef END_SHADER
		averageSkyCol_Clouds = vec3(15.0);
	#endif

	lightCol.a = float(sunElevation > 1e-5)*2.0 - 1.0;
	WsunVec = normalize(mat3(gbufferModelViewInverse) * sunPosition);

	vec3 moonVec = normalize(mat3(gbufferModelViewInverse) * moonPosition);
	vec3 WmoonVec = moonVec;
	if(dot(-moonVec, WsunVec) < 0.9999) WmoonVec = -moonVec;

	WsunVec = mix(WmoonVec, WsunVec, clamp(lightCol.a,0,1));
	
	refractedSunVec = refract(WsunVec, -vec3(0.0,1.0,0.0), 1.0/1.33333);
}

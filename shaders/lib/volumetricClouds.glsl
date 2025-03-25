#define ALTOSTRATUS_LAYER 2
#define LARGECUMULUS_LAYER 1
#define SMALLCUMULUS_LAYER 0

float cloud_movement = (worldTime + mod(worldDay,100)*24000.0) / 24.0 * Cloud_Speed;

float densityAtPos(in vec3 pos){
	pos /= 18.;
	pos.xz *= 0.5;
	vec3 p = floor(pos);
	vec3 f = fract(pos);
	vec2 uv =  p.xz + f.xz + p.y * vec2(0.0,193.0);
	vec2 coord =  uv / 512.0;
	
	//The y channel has an offset to avoid using two textures fetches
	vec2 xy1 = texture2D(noisetex, coord).yx;
	vec2 xy2 = texture2D(noisetex, coord * 2.5).yx;

	//Strengthen the vertical detail
	float vn = texture2D(noisetex, vec2(coord.x, pos.y / 100.0)).r;
	vn = vn * vn;

	float density = mix(xy1.r, xy1.g, f.y) + mix(xy2.r, xy2.g, f.y) * 0.5;
	density *= 1.0 + vn * 0.5;

	return density;
}

float getCloudShape(int LayerIndex, int LOD, in vec3 position, float minHeight, float maxHeight){

	vec3 samplePos = position*vec3(1.0, 1.0/48.0, 1.0)/4.0;
	
	float coverage = 0.0;
	float shape = 0.0;
	float largeCloud = 0.0;
	float smallCloud = 0.0;

	if(LayerIndex == ALTOSTRATUS_LAYER){
		coverage = mix(dailyWeatherParams0.z, 1.2*Rain_coverage, rainStrength);

		largeCloud = texture2D(noisetex, (position.xz + cloud_movement)/100000. * CloudLayer2_scale).b;
		smallCloud = 1.0 - texture2D(noisetex, ((position.xz - cloud_movement)/7500. - vec2(1.0-largeCloud, -largeCloud)/5.0) * CloudLayer2_scale).b;
		smallCloud = largeCloud + smallCloud * 0.4 * clamp(1.5-largeCloud,0.0,1.0);
		
		shape = min(max(coverage - smallCloud,0.0)/sqrt(coverage),1.0);
		shape *= shape;

		return shape;
	}
	if(LayerIndex == LARGECUMULUS_LAYER){
		coverage = mix(dailyWeatherParams0.y, Rain_coverage, rainStrength);
		
		largeCloud = texture2D(noisetex, (samplePos.zx + cloud_movement*2.5)/15000.0 * CloudLayer1_scale).b;
		smallCloud = texture2D(noisetex, (samplePos.zx - cloud_movement*2.5)/3000.0 * CloudLayer1_scale).b;	
		smallCloud += abs(largeCloud* -0.7);

		shape = min(max((coverage - smallCloud) * 1.2,0.0)/sqrt(coverage),1.0);
	}
	if(LayerIndex == SMALLCUMULUS_LAYER){
		coverage = mix(dailyWeatherParams0.x, Rain_coverage, rainStrength);

		largeCloud = texture2D(noisetex, (samplePos.xz + cloud_movement)/5000.0 * CloudLayer0_scale).b;
		smallCloud = 1.0-texture2D(noisetex, (samplePos.xz - cloud_movement)/1000.0 * CloudLayer0_scale).r;
		smallCloud = abs(largeCloud-0.6) + smallCloud * smallCloud;

		shape = min(max(coverage - smallCloud,0.0)/sqrt(coverage),1.0);
	}

	float toTop = maxHeight - position.y;
	float toBottom = position.y - minHeight;
	float tallness = maxHeight - minHeight;

	// clamp density of the cloud within its upper/lower bounds
	shape = min(min(shape, clamp(toTop,0,1)), clamp(toBottom,0,1));

	// carve out the upper part of clouds. make sure it rounds out at its upper bound
	float topShape = clamp(toTop / tallness, 0.0, 1.0);
	topShape = min(exp(-0.5 * (1.0-topShape)), 1.0-pow(1.0-topShape,5.0));

	// round out the bottom part slightly
	float bottomShape = smoothstep(0.0, 0.25, toBottom / tallness);

	shape = max((shape - 1.0) + topShape * bottomShape, 0.0);

	/// erosion noise
	if(shape > 0.01){

		// shrink the coverage slightly so it is a similar shape to clouds with erosion. this helps cloud lighting and cloud shadows.
		if (LOD < 1) return max(shape - 0.27 * ERODE_AMOUNT,0.0);

		samplePos.xz -= cloud_movement/4.0;
		samplePos.xz += pow(max(toBottom - 20.0, 0.0) / (max(tallness, 1.0) * 0.20), 1.5);

		float erosionBase = sqrt(1.0 - shape);

		// initial erosion
		float erosion = 0.0;
		#ifdef HQ_CLOUDS
			erosion = texture2D(noisetex, samplePos.xz * 0.01).r * erosionBase;
		#endif

		if(LayerIndex == LARGECUMULUS_LAYER){
			erosion += (1.0 - densityAtPos(samplePos * 100.0 * CloudLayer1_scale)) * erosionBase;

			float falloff = 1.0 - clamp(toTop/200.0,0.0,1.0);
			erosion += abs(densityAtPos(samplePos * 450.0 * CloudLayer1_scale) - falloff) * 0.75 * (1.0 - shape) * (1.0 - falloff * 0.5);

			erosion = erosion * erosion * erosion * erosion;
		}
		if(LayerIndex == SMALLCUMULUS_LAYER){
			erosion += (1.0 - densityAtPos(samplePos * 200.0 * CloudLayer0_scale)) * erosionBase;

			float falloff = 1.0 - clamp(toTop/100.0,0.0,1.0);
			erosion += abs(densityAtPos(samplePos * 600.0 * CloudLayer0_scale) - falloff) * 0.75 * (1.0 - shape) * (1.0 - falloff * 0.5);

			erosion = erosion * erosion * erosion * erosion;
		}
		return max(shape - erosion * ERODE_AMOUNT, 0.0);
	}
	else return 0.0;
}

float getPlanetShadow(vec3 playerPos, vec3 WsunVec){
	float planetShadow = min(max(playerPos.y - (-100.0 + 1.0 / abs(WsunVec.y*0.1)),0.0) / 100.0, 1.0);
	
	planetShadow = mix(pow(1.0-pow(1.0-planetShadow,2.0),2.0), 1.0, pow(abs(WsunVec.y),2.0));
	
	return planetShadow;
}

float GetCloudShadow(vec3 playerPos, vec3 sunVector){

	float totalShadow = getPlanetShadow(playerPos, sunVector);

	#ifdef CLOUDS_SHADOWS
 		float cloudShadows = 0.0;

		#ifdef CloudLayer0
			vec3 pos0 = playerPos + sunVector / abs(sunVector.y) * max(CloudLayer0_height - playerPos.y + 20.0, 0.0);
			cloudShadows = getCloudShape(SMALLCUMULUS_LAYER, 0, pos0, CloudLayer0_height, CloudLayer0_height + 50.0) * dailyWeatherParams1.x;
		#endif
		#ifdef CloudLayer1
			vec3 pos1 = playerPos + sunVector / abs(sunVector.y) * max(CloudLayer1_height - playerPos.y + 40.0, 0.0);
			cloudShadows += getCloudShape(LARGECUMULUS_LAYER, 0, pos1, CloudLayer1_height, CloudLayer1_height + 100.0) * dailyWeatherParams1.y;
		#endif
		#ifdef CloudLayer2
			vec3 pos2 = playerPos + sunVector / abs(sunVector.y) * max(CloudLayer2_height - playerPos.y + 1.0, 0.0);
			cloudShadows += getCloudShape(ALTOSTRATUS_LAYER, 0, pos2, CloudLayer2_height, CloudLayer2_height + 2.5) * dailyWeatherParams1.z * (1.0-abs(WsunVec.y));
		#endif

		cloudShadows *= CLOUD_SHADOW_STRENGTH;

		#if defined CloudLayer0 || defined CloudLayer1 || defined CloudLayer2
			totalShadow *= exp((cloudShadows*cloudShadows) * -200.0);
		#endif
	#endif

	return totalShadow;
}

#ifndef CLOUDSHADOWSONLY

float phaseCloud(float x, float g){
	float gg = g * g;
	return (gg * -0.25 + 0.25) * pow(-2.0 * (g * x) + (gg + 1.0), -1.5) / 3.14;
}

float getCloudScattering(
	int LayerIndex,
	vec3 rayPosition,
	vec3 sunVector,
	float dither, 
	float minHeight,
	float maxHeight,
	float density
){
	int samples = 3;
	int LOD = 0;

	if(LayerIndex == ALTOSTRATUS_LAYER) samples = 2;

	float shadow = 0.0;
	vec3 shadowRayPosition = vec3(0.0);

	for (int i = 0; i < samples; i++){
		if(LayerIndex == ALTOSTRATUS_LAYER){
			shadowRayPosition = rayPosition + sunVector * (1.0 + i * dither) / (pow(abs(sunVector.y*0.5),3.0) * 0.995 + 0.005);
		}else{
			shadowRayPosition = rayPosition + sunVector * (1.0 + i + dither)*20.0;
		}

		// float fadeddensity = density * pow(clamp((shadowRayPosition.y - minHeight)/(max(maxHeight-minHeight,1.0)*0.25),0.0,1.0),2.0);

		shadow += getCloudShape(LayerIndex, LOD, shadowRayPosition, minHeight, maxHeight) * density;	
	}
	return shadow;
}

vec3 getCloudLighting(
	float shape,
	float shapeFaded,

	float sunShadowMask,
	vec3 directLightCol,
	vec3 directLightCol_multi,

	float indirectShadowMask,
	vec3 indirectLightCol,

	float distanceFade
){
	float powderEffect = 1.0 - exp(-3.0*shapeFaded);

	vec3 directScattering = directLightCol * exp(-10.0 * sunShadowMask) + directLightCol_multi * exp(1.0 - 1.5 * (sunShadowMask + indirectShadowMask * indirectShadowMask)) * powderEffect;
	vec3 indirectScattering = indirectLightCol * mix(1.0, exp2(-5.0 * shape), indirectShadowMask * indirectShadowMask * distanceFade);

	return indirectScattering + directScattering;
}

vec4 raymarchCloud(
	int LayerIndex,
	int samples,
	vec3 rayPosition,
	vec3 rayDirection,
	float dither,

	float minHeight,
	float maxHeight,

	vec3 sunVector,
	vec3 sunScattering, 
	vec3 sunMultiScattering, 
	vec3 skyScattering,
	float distanceFade,

	float referenceDistance,
	vec3 sampledSkyCol,

	inout vec2 cloudPlaneDistance
){
	vec3 color = vec3(0.0);
	float totalAbsorbance = 1.0;

	float GetPos = 0.0;

	float planetShadow = getPlanetShadow(rayPosition, sunVector);
	sunScattering *= planetShadow;
	sunMultiScattering *= planetShadow;

	float distanceFactor = length(rayDirection);

	float densityTresholdCheck = 0.0;
 
	if(LayerIndex == SMALLCUMULUS_LAYER) densityTresholdCheck = 0.06;
	if(LayerIndex == LARGECUMULUS_LAYER) densityTresholdCheck = 0.02;
	if(LayerIndex == ALTOSTRATUS_LAYER) densityTresholdCheck = 0.01;

	densityTresholdCheck = mix(1e-5, densityTresholdCheck, dither);

	if(LayerIndex == ALTOSTRATUS_LAYER){
		float density = mix(dailyWeatherParams1.z,0.5,rainStrength);

		bool ifAboveOrBelowPlane = max(mix(-1.0, 1.0, clamp(cameraPosition.y - minHeight,0.0,1.0)) * normalize(rayDirection).y,0.0) > 0.0;

		// check if the ray staring position is going farther than the reference distance, if yes, dont begin marching. this is to check for intersections with the world.
		// check if the camera is above or below the cloud plane, so it doesnt waste work on the opposite hemisphere
		#ifndef VL_CLOUDS_DEFERRED
			if(length(rayPosition - cameraPosition) > referenceDistance || ifAboveOrBelowPlane) return vec4(color, totalAbsorbance);
		#else
			if(ifAboveOrBelowPlane) return vec4(color, totalAbsorbance);
		#endif

		float shape = getCloudShape(LayerIndex, 1, rayPosition, minHeight, maxHeight);
		float shapeWithDensity = shape*density;

		if(shapeWithDensity > mix(1e-5, 0.06, dither)){
			cloudPlaneDistance.x = length(rayPosition - cameraPosition);
			cloudPlaneDistance.y = 0.0;
		}

		// check if the pixel has visible clouds before doing work.
		if(shapeWithDensity > 1e-5){

			// can add the initial cloud shape sample for a free shadow starting step :D
			float sunShadowMask = (shapeWithDensity + getCloudScattering(LayerIndex, rayPosition, sunVector, dither, minHeight, maxHeight, density)) * (1.0-abs(WsunVec.y));
			float indirectShadowMask = 0.5;

			vec3 lighting = getCloudLighting(shapeWithDensity, shapeWithDensity, sunShadowMask, sunScattering, sunMultiScattering, indirectShadowMask, skyScattering, distanceFade);

			vec3 newPos = rayPosition - cameraPosition;
 			newPos.xz /= max(newPos.y,0.0)*0.0025 + 1.0;
 			newPos.y = min(newPos.y,0.0);
 
 			float distancefog = exp(-0.00025*length(newPos));
 			vec3 atmosphereHaze = (sampledSkyCol - sampledSkyCol * distancefog);
 			lighting = lighting * distancefog + atmosphereHaze;
 
 			float densityCoeff = exp(-distanceFactor*shapeWithDensity);	
			color += (lighting - lighting * densityCoeff) * totalAbsorbance;
			totalAbsorbance *= densityCoeff;
		}

		return vec4(color, totalAbsorbance);
	}

	if(LayerIndex < ALTOSTRATUS_LAYER){
		float density = mix(dailyWeatherParams1.x,0.5,rainStrength);

		if(LayerIndex == LARGECUMULUS_LAYER) density = mix(dailyWeatherParams1.y, 0.2,rainStrength);
		
		float skylightOcclusion = 1.0;
		#if defined CloudLayer1 && defined CloudLayer0
			if(LayerIndex == SMALLCUMULUS_LAYER) {
				float upperLayerOcclusion = getCloudShape(LARGECUMULUS_LAYER, 0, rayPosition + vec3(0.0,1.0,0.0) * max((CloudLayer1_height+20) - rayPosition.y,0.0), CloudLayer1_height, CloudLayer1_height+100.0);
				skylightOcclusion = mix(mix(0.0,0.2,dailyWeatherParams1.y), 1.0, pow(1.0 - upperLayerOcclusion*dailyWeatherParams1.y,2));
			}

			skylightOcclusion = mix(1.0, skylightOcclusion, distanceFade);
		#endif

		for(int i = 0; i < samples; i++) {

			// check if the ray staring position is going farther than the reference distance, if yes, dont begin marching. this is to check for intersections with the world.
			#ifndef VL_CLOUDS_DEFERRED
				if(length(rayPosition - cameraPosition) > referenceDistance) break;
			#endif

			// check if the pixel is in the bounding box before doing work.
			if(clamp(rayPosition.y - maxHeight,0.0,1.0) < 1.0 && clamp(rayPosition.y - minHeight,0.0,1.0) > 0.0){

				float shape = getCloudShape(LayerIndex, 1, rayPosition, minHeight, maxHeight);
				float shapeWithDensity = shape*density;
				float shapeWithDensityFaded = shape*density * pow(clamp((rayPosition.y - minHeight)/(max(maxHeight-minHeight,1.0)*0.25),0.0,1.0),2.0);

				if(shapeWithDensityFaded > densityTresholdCheck){
					cloudPlaneDistance.x = length(rayPosition - cameraPosition);
					cloudPlaneDistance.y = 0.0;
				}

				// check if the pixel has visible clouds before doing work.
				if(shapeWithDensityFaded > 1e-5){

					// can add the initial cloud shape sample for a free shadow starting step :D
					float indirectShadowMask = 1.0 - clamp((rayPosition.y - minHeight) / (maxHeight - minHeight), 0.0, 1.0);
					float sunShadowMask = shapeWithDensity + getCloudScattering(LayerIndex, rayPosition, sunVector, dither, minHeight, maxHeight, density);
					
					// do cloud shadows from one layer to another
					// large cumulus layer -> small cumulus layer
					#if defined CloudLayer0 && defined CloudLayer1
						if(LayerIndex == SMALLCUMULUS_LAYER){
							vec3 shadowStartPos = rayPosition + sunVector / abs(sunVector.y) * max((CloudLayer1_height + 20.0) - rayPosition.y, 0.0);
							sunShadowMask += 3.0 * getCloudShape(LARGECUMULUS_LAYER, 0, shadowStartPos, CloudLayer1_height, CloudLayer1_height+100.0)*dailyWeatherParams1.y;
						}
					#endif
					// altostratus layer -> all cumulus layers
					#ifdef CloudLayer2
						vec3 shadowStartPos = rayPosition + sunVector / abs(sunVector.y) * max(CloudLayer2_height - rayPosition.y, 0.0);
						sunShadowMask += getCloudShape(ALTOSTRATUS_LAYER, 0, shadowStartPos, CloudLayer2_height, CloudLayer2_height) * dailyWeatherParams1.z * (1.0-abs(sunVector.y));
					#endif
					
					vec3 lighting = getCloudLighting(shapeWithDensity, shapeWithDensityFaded, sunShadowMask, sunScattering, sunMultiScattering, indirectShadowMask, skyScattering * skylightOcclusion, distanceFade);

					vec3 newPos = rayPosition - cameraPosition;
 					newPos.xz /= max(newPos.y,0.0)*0.0025 + 1.0;
 					newPos.y = min(newPos.y,0.0);
 
 					float distancefog = exp(-0.00025*length(newPos));
 					vec3 atmosphereHaze = (sampledSkyCol - sampledSkyCol * distancefog);
 					lighting = lighting * distancefog + atmosphereHaze;

					float densityCoeff = exp(-distanceFactor*shapeWithDensityFaded);
					color += (lighting - lighting * densityCoeff) * totalAbsorbance;
					totalAbsorbance *= densityCoeff;

					// check if you can see through the cloud on the pixel before doing the next iteration
					if (totalAbsorbance < 1e-5) break;
				}
			}
			rayPosition += rayDirection;
		}
		return vec4(color, totalAbsorbance);
	}
}

vec3 getRayOrigin(
	vec3 rayStartPos,
	vec3 cameraPos,
	float dither,

	float minHeight,
	float maxHeight
){
	vec3 cloudDist = vec3(1.0);
	cloudDist.xz = mix(vec2(255.0), vec2(5.0), clamp(cameraPos.y - minHeight ,0.0,clamp((maxHeight-15)-cameraPosition.y ,0.0,1.0)));
	// allow passing through/above/below the plane without limits
	float flip = mix(max(cameraPos.y - maxHeight,0.0), max(minHeight - cameraPos.y,0.0), clamp(rayStartPos.y,0.0,1.0));

	// orient the ray to be a flat plane facing up/down
	// vec3 position = rayStartPos*dither + cameraPos + (rayStartPos/abs(rayStartPos.y)) * flip;
	vec3 position = rayStartPos*dither + cameraPos + (rayStartPos/length(rayStartPos/cloudDist)) * flip;

	return position;
}

vec4 GetVolumetricClouds(
	vec3 viewPos,
	vec2 dither,
	vec3 sunVector,
	vec3 directLightCol,
	vec3 indirectLightCol,

	inout float cloudPlaneDistance
){	
	#ifndef VOLUMETRIC_CLOUDS
		return vec4(0.0,0.0,0.0,1.0);
	#endif

	vec3 color = vec3(0.0);
	float totalAbsorbance = 1.0;
	vec4 cloudColor = vec4(color, totalAbsorbance);

	float cloudheight = CloudLayer0_tallness;
	float minHeight = CloudLayer0_height;
	float maxHeight = cloudheight + minHeight;

	#if defined OVERWORLD_SHADER && defined AETHER_FLAG
		minHeight = CloudLayer0_height - 350.0;
		maxHeight = cloudheight + minHeight;
	#endif

	float heightRelativeToClouds = clamp(1.0 - max(cameraPosition.y - minHeight,0.0) / 100.0 ,0.0,1.0);

	float maxdist = far + 16.0*5.0;
	#ifdef DISTANT_HORIZONS
		maxdist = dhFarPlane - 16.0;
	#endif

   	float lViewPosM = length(viewPos) < maxdist ? length(viewPos) - 1.0 : 100000000.0;
	vec4 NormPlayerPos = normalize(gbufferModelViewInverse * vec4(viewPos, 1.0) + vec4(gbufferModelViewInverse[3].xyz,0.0));

	vec3 signedSunVec = sunVector;
	vec3 unignedSunVec = sunVector;// * (float(sunElevation > 1e-5)*2.0-1.0);
	float SdotV = dot(unignedSunVec, NormPlayerPos.xyz);

	#ifdef SKY_GROUND
 		NormPlayerPos.y += 0.03 * heightRelativeToClouds;
 	#endif

	float maxSamples = 15.0;
	float minSamples = 10.0;
	int samples = int(clamp(maxSamples / sqrt(exp2(NormPlayerPos.y)),0.0, minSamples));
   
   	///------- setup the ray
	vec3 cloudDist = vec3(1.0);
	cloudDist.xz = mix(vec2(255.0), vec2(5.0), clamp(cameraPosition.y - minHeight,0.0,clamp((maxHeight-5) - cameraPosition.y ,0.0,1.0)));

	// vec3 rayDirection = NormPlayerPos.xyz * (cloudheight/abs(NormPlayerPos.y)/samples);
	vec3 rayDirection = NormPlayerPos.xyz * (cloudheight/length(NormPlayerPos.xyz/cloudDist)/samples);
	vec3 rayPosition = getRayOrigin(rayDirection, cameraPosition, dither.y, minHeight, maxHeight);

	#ifdef SKY_GROUND
		vec3 sampledSkyCol = indirectLightCol;
	#else
		vec3 sampledSkyCol = skyFromTex(normalize(rayPosition-cameraPosition), colortex4)/1200.0 * Sky_Brightness;
	#endif

	// setup for getting distance
	vec3 playerPos = mat3(gbufferModelViewInverse) * viewPos;
	#ifdef DISTANT_HORIZONS
		float maxLength = min(length(playerPos), max(far, dhRenderDistance))/length(playerPos);
	#else
		float maxLength = min(length(playerPos), far)/length(playerPos);
	#endif
	playerPos *= maxLength;

	float startDistance = length(playerPos);

	#if defined EXCLUDE_WRITE_TO_LUT && defined USE_CUSTOM_CLOUD_LIGHTING_COLORS
		directLightCol = dot(directLightCol,vec3(0.21, 0.72, 0.07)) * vec3(DIRECTLIGHT_CLOUDS_R,DIRECTLIGHT_CLOUDS_G,DIRECTLIGHT_CLOUDS_B);
		indirectLightCol = dot(indirectLightCol,vec3(0.21, 0.72, 0.07)) * vec3(INDIRECTLIGHT_CLOUDS_R,INDIRECTLIGHT_CLOUDS_G,INDIRECTLIGHT_CLOUDS_B);
	#endif

	///------- do color stuff outside of the raymarcher loop
	vec3 sunScattering = directLightCol * (phaseCloud(SdotV, 0.85) + phaseCloud(SdotV, 0.75)) * 3.14;
	vec3 sunMultiScattering = 0.8 * directLightCol;// * (phaseCloud(SdotV, 0.35) + phaseCloud(-SdotV, 0.35) * 0.5) * 6.28;
	vec3 skyScattering = indirectLightCol;

	vec3 distanceEstimation = normalize(NormPlayerPos.xyz * (cloudheight/abs(NormPlayerPos.y)/samples));

	float distanceFade = 1.0 - clamp(exp2(pow(abs(distanceEstimation.y),1.5) * -100.0),0.0,1.0)*heightRelativeToClouds;
	distanceFade = 1.0;

	skyScattering *= 2.0;
 	// sunScattering *= distanceFade;
 	// sunMultiScattering *= distanceFade;
 
   	////-------  RENDER SMALL CUMULUS CLOUDS
		vec4 smallCumulusClouds = cloudColor;

		vec2 cloudLayer0_Distance = vec2(startDistance, 1.0);
		#ifdef CloudLayer0
			smallCumulusClouds = raymarchCloud(SMALLCUMULUS_LAYER, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight, unignedSunVec, sunScattering, sunMultiScattering, skyScattering, distanceFade, lViewPosM, sampledSkyCol, cloudLayer0_Distance);
		#endif

	////------- RENDER LARGE CUMULUS CLOUDS
		vec4 largeCumulusClouds = cloudColor;

		#ifdef CloudLayer1
			cloudheight = CloudLayer1_tallness;
			minHeight = CloudLayer1_height;
			maxHeight = cloudheight + minHeight;

			cloudDist.xz = mix(vec2(255.0), vec2(5.0), clamp(cameraPosition.y - minHeight,0.0,clamp((maxHeight-15) - cameraPosition.y ,0.0,1.0)));
			rayDirection = NormPlayerPos.xyz * (cloudheight/length(NormPlayerPos.xyz/cloudDist)/samples);
			rayPosition = getRayOrigin(rayDirection, cameraPosition, dither.y, minHeight, maxHeight);

			vec2 cloudLayer1_Distance = vec2(startDistance, 1.0);
			if(smallCumulusClouds.a > 1e-5) largeCumulusClouds = raymarchCloud(LARGECUMULUS_LAYER, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight, unignedSunVec, sunScattering, sunMultiScattering, skyScattering, distanceFade, lViewPosM, sampledSkyCol, cloudLayer1_Distance);
		#endif

   	////------- RENDER ALTOSTRATUS CLOUDS
		vec4 altoStratusClouds = cloudColor;
		
		#ifdef CloudLayer2
			cloudheight = 5.0;
			minHeight = CloudLayer2_height;
			maxHeight = cloudheight + minHeight;

			cloudDist.xz = mix(vec2(255.0), vec2(5.0), clamp(cameraPosition.y - minHeight,0.0,clamp((maxHeight-15) - cameraPosition.y ,0.0,1.0)));
			rayDirection = NormPlayerPos.xyz * (cloudheight/length(NormPlayerPos.xyz/cloudDist));
			rayPosition = getRayOrigin(rayDirection, cameraPosition, dither.y, minHeight, maxHeight);

			vec2 cloudLayer2_Distance = vec2(startDistance, 1.0);
			if(smallCumulusClouds.a > 1e-5 || largeCumulusClouds.a > 1e-5) altoStratusClouds = raymarchCloud(ALTOSTRATUS_LAYER, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight, unignedSunVec, sunScattering, sunMultiScattering, skyScattering, distanceFade, lViewPosM, sampledSkyCol, cloudLayer2_Distance);
		#endif

   	////------- BLEND LAYERS

		#if defined CloudLayer0 && !defined CloudLayer1 && !defined CloudLayer2
			cloudPlaneDistance = cloudLayer0_Distance.x;
		#endif
 
		#if defined CloudLayer0 && defined CloudLayer1 && !defined CloudLayer2
			cloudPlaneDistance = mix(cloudLayer0_Distance.x, cloudLayer1_Distance.x, cloudLayer0_Distance.y);
		#endif
 	
		#if defined CloudLayer0 && defined CloudLayer1 && defined CloudLayer2
			cloudPlaneDistance = mix(cloudLayer2_Distance.x, cloudLayer1_Distance.x, cloudLayer2_Distance.y);
			cloudPlaneDistance = mix(cloudLayer0_Distance.x, cloudPlaneDistance, cloudLayer0_Distance.y);
		#endif

		#if defined CloudLayer0 && !defined CloudLayer1 && !defined CloudLayer2
			cloudPlaneDistance = cloudLayer0_Distance.x;
		#endif

		#if !defined CloudLayer0 && defined CloudLayer1 && !defined CloudLayer2
			cloudPlaneDistance = cloudLayer1_Distance.x;
		#endif

		#if !defined CloudLayer0 && !defined CloudLayer1 && defined CloudLayer2
			cloudPlaneDistance = cloudLayer2_Distance.x;
		#endif

		#ifdef CloudLayer2
			cloudColor = altoStratusClouds;
		#endif

		#ifdef CloudLayer1
			cloudColor.rgb *= largeCumulusClouds.a;
			cloudColor.rgb += largeCumulusClouds.rgb;
			cloudColor.a *= largeCumulusClouds.a;
		#endif

		#ifdef CloudLayer0
			cloudColor.rgb *= smallCumulusClouds.a;
			cloudColor.rgb += smallCumulusClouds.rgb;
			cloudColor.a *= smallCumulusClouds.a;
		#endif

		color = cloudColor.rgb;
		totalAbsorbance = cloudColor.a;

		return vec4(color, totalAbsorbance);
	}
#endif
####    autopilot/route-manager help-functions                                                 ####
####    Author: Markus Bulik                                                                   ####
####    This file is licenced under the terms of the GNU General Public Licence V2 or later    ####

##############################################################################
## Route-Manager - AP - routines                                            ##
## AP- route-manager driven (in passive-mode, controls 'true-heading-hold', ##
##                       'vertical-speed-hold', 'altitude-hold')            ##
##############################################################################

var kpForHeadingDeg = -2.3;
var kpForHeading = 0.18;
var tiForHeading = 3.0;

# 707 needs about 180 seconds (at speed 250 kts) fo a 180° turn, much more than a theoretical standard-turn
var wpAircraftSpecificTurnFactor = 2.0;
# passed distance (kts) per second per kt (707 needs 4 second to get into 20 deg. roll)
var wpAircraftSpecificTurnInertiaFactor = 4.0 / 3600.0;

# math.sin() seems not to be functional - this is a approximation for 0 < angle < 90 degrees
var sinus = func(angle) {
	var rad = 0.01745 * angle;
	return (rad - ((rad * rad * rad) / 6) + ((rad * rad * rad * rad * rad) / 120));
}
var cosinus = func(angle) {
	var rad = 0.01745 * angle;
	return (rad - ((rad * rad) / 2) + ((rad * rad * rad * rad) / 24) - ((rad * rad * rad * rad * rad * rad) / 720));
}
var tangens = func(angle) {
	var rad = 0.01745 * angle;
	return (rad + ((rad * rad * rad) / 3) + ((rad * rad * rad * rad * rad) * 2 / 15) - ((rad * rad * rad * rad * rad * rad * rad) * 17 / 315));
}

var listenerApRouteManagerInitFunc = func {
	# do initializations of new properties

	setprop("/autopilot/internal/route-manager-waypoint-near-by", 0);
	setprop("autopilot/locks/passive-mode", 0);

	setprop("/autopilot/internal/target-kp-for-heading-deg", kpForHeadingDeg);
	setprop("/autopilot/internal/target-kp-for-heading-hold", kpForHeading);
	setprop("/autopilot/internal/target-ti-for-heading-hold", tiForHeading);
	setprop("/autopilot/internal/gs-rate-of-climb-near-far-filtered", 0.0);
	setprop("/autopilot/internal/VOR-near-by", 0);
	setprop("/autopilot/internal/target-roll-deg-for-VOR-near-by", 0.0);
}
setlistener("/sim/signals/fdm-initialized", listenerApRouteManagerInitFunc);

var getTotalLbs = func {
	return( getprop("/consumables/fuel/tank[0]/level-lbs") +
		getprop("/consumables/fuel/tank[1]/level-lbs") +
		getprop("/consumables/fuel/tank[2]/level-lbs") +
		getprop("/consumables/fuel/tank[3]/level-lbs") +
		getprop("/consumables/fuel/tank[4]/level-lbs") +
		getprop("/consumables/fuel/tank[5]/level-lbs") +
		getprop("/consumables/fuel/tank[6]/level-lbs") +
		getprop("/payload/weight[0]/weight-lb") +
		getprop("/payload/weight[1]/weight-lb") +
		getprop("/payload/weight[2]/weight-lb") +
		getprop("/payload/weight[3]/weight-lb") +
		getprop("/payload/weight[4]/weight-lb") +
		getprop("/payload/weight[5]/weight-lb") +
		getprop("/payload/weight[6]/weight-lb") );
}

# switch-functions
var listenerApHeadingSwitchFunc = func {

	if (	getprop("/autopilot/locks/heading") == "nav1-hold" or
		getprop("/autopilot/locks/heading") == "dg-heading-hold" or
		((getprop("/autopilot/locks/heading") == "true-heading-hold") and (getprop("/autopilot/route-manager/active") == 0))) {

		#print ("-> listenerApHeadingSwitchFunc -> installed");
		setprop("/autopilot/internal/target-kp-for-heading-hold", (kpForHeading * 0.05));
	}
}
setlistener("/autopilot/settings/heading-bug-deg", listenerApHeadingSwitchFunc);
setlistener("/instrumentation/nav[0]/radials/selected-deg", listenerApHeadingSwitchFunc);
setlistener("/autopilot/locks/heading", listenerApHeadingSwitchFunc);

var listenerApHeadingPassiveModeFunc = func {

	if (	getprop("/autopilot/locks/heading") == "true-heading-hold" and
		getprop("/autopilot/route-manager/active") == 1) {

		#print ("-> listenerApHeadingPassiveModeFunc -> installed");
		setprop("/autopilot/internal/target-kp-for-heading-hold", (kpForHeading * 0.05));
	}
}
setlistener("autopilot/locks/passive-mode", listenerApHeadingSwitchFunc);

# switch-functions
var listenerApHeadingFunc = func {
	if (	getprop("/autopilot/locks/heading") == "nav1-hold" or
		getprop("/autopilot/locks/heading") == "dg-heading-hold" or
		getprop("/autopilot/locks/heading") == "true-heading-hold") {

		#print ("-> listenerApHeadingFunc -> installed");

		var timerGap = 0.05;

		var airspeedKt = getprop("/velocities/airspeed-kt");
		var totalLbs = getTotalLbs();

		if (totalLbs > 100000 and airspeedKt < 300) {
			# full load: 196000 lbs

			# iterate to 10.0 at full load, low (speed < 300)
			tiForHeading = 3.0 + ((totalLbs - 100000.0) * 0.000072917);
		}
		else {
			tiForHeading = 3.0;
		}

		#print ("-> listenerApHeadingFunc -> kpForHeadingDeg=", kpForHeadingDeg, "  tiForHeading=", tiForHeading, "  totalLbs=", totalLbs);
		setprop("/autopilot/internal/target-kp-for-heading-deg", kpForHeadingDeg);
		setprop("/autopilot/internal/target-ti-for-heading-hold", tiForHeading);

		# interpolate 'kpForHeading'
		var interpolationSeconds = 6;
		var numInterpolations = (1 / timerGap) * interpolationSeconds;
		var kpForHeadingInterpolationIncrement = kpForHeading / numInterpolations;
		var kpForHeadingActual = getprop("/autopilot/internal/target-kp-for-heading-hold");
		if (kpForHeadingActual < kpForHeading) {
			kpForHeadingActual = kpForHeadingActual + kpForHeadingInterpolationIncrement;
			kpForHeadingActual = (kpForHeadingActual > kpForHeading ? kpForHeading : kpForHeadingActual);

		}
		setprop("/autopilot/internal/target-kp-for-heading-hold", kpForHeadingActual);

		settimer(listenerApHeadingFunc, timerGap);
	}
}
setlistener("/autopilot/locks/heading", listenerApHeadingFunc);

var listenerApGsNearFarFunc = func {
	if (getprop("/autopilot/locks/altitude") == "gs1-hold") {

		#print ("-> listenerApGs1NearFarFunc -> installed");
		#print ("-> listenerApGs1NearFarFunc -> gs-rate-of-climb=", getprop("/instrumentation/nav[0]/gs-rate-of-climb"));
		var gsRateNearFarFiltered = getprop("/autopilot/internal/gs-rate-of-climb-near-far-filtered");

		# filter unrealistic values
		if (gsRateNearFarFiltered > 5.0) {
			gsRateNearFarFiltered = 5.0;
		}
		elsif (gsRateNearFarFiltered < -20.0) {
			gsRateNearFarFiltered = -20.0;
		}

		if (getprop("/instrumentation/nav[0]/gs-in-range") == 1) {

			var nav1GsRateOfClimp = getprop("/instrumentation/nav[0]/gs-rate-of-climb");
			if (nav1GsRateOfClimp < -2.0) {	# in GS

				if (getprop("/instrumentation/nav[0]/gs-rate-of-climb") != nil) {
					gsRateNearFarFiltered = nav1GsRateOfClimp;
					setprop("/autopilot/internal/gs-rate-of-climb-near-far-filtered", gsRateNearFarFiltered);
				}
				else {
					setprop("/autopilot/internal/gs-rate-of-climb-near-far-filtered", 0.0);
				}
			}
			else {
				# iterate to 1.67 (100 fpm)
				var gsRateNearFarFilteredIncrement = 0.2;
				if (abs(gsRateNearFarFiltered - 1.67) > 1.0) {
					gsRateNearFarFilteredIncrement = 1.0;
				}
				gsRateNearFarFiltered = (gsRateNearFarFiltered < 1.67 ? (gsRateNearFarFiltered + gsRateNearFarFilteredIncrement) : gsRateNearFarFiltered);
				gsRateNearFarFiltered = (gsRateNearFarFiltered > 1.67 ? (gsRateNearFarFiltered - gsRateNearFarFilteredIncrement) : gsRateNearFarFiltered);
				setprop("/autopilot/internal/gs-rate-of-climb-near-far-filtered", gsRateNearFarFiltered);
			}
		}
		else {
			# iterate to 0.0
			var gsRateNearFarFilteredIncrement = 0.2;
			if (abs(gsRateNearFarFiltered) > 1.0) {
				gsRateNearFarFilteredIncrement = 1.0;
			}
			gsRateNearFarFiltered = (gsRateNearFarFiltered < 0.0 ? (gsRateNearFarFiltered + gsRateNearFarFilteredIncrement) : gsRateNearFarFiltered);
			gsRateNearFarFiltered = (gsRateNearFarFiltered > 0.0 ? (gsRateNearFarFiltered - gsRateNearFarFilteredIncrement) : gsRateNearFarFiltered);
			setprop("/autopilot/internal/gs-rate-of-climb-near-far-filtered", gsRateNearFarFiltered);

		}

		#print("listenerApGs1NearFarFunc: gs-rate-of-climb-near-far-filtered=", getprop("/autopilot/internal/gs-rate-of-climb-near-far-filtered"));

		settimer(listenerApGsNearFarFunc, 0.05);
	}
}
setlistener("/autopilot/locks/altitude", listenerApGsNearFarFunc);


# notes:
# if 'passive-mode' is switched on, the autopilot is controled by the route-manager, that means the settings for 'true-heading-hold'
# and 'altitude-hold' come from the route-manager, additionally the route-manager activates 'true-heading-hold'.
# This procedure calculates the appropriate vertical-speed and activates 'vertical-speed-hold', 'altitude-hold' as needed.
# Also provides a 'smooting'-procedure on the transition of waypoints.

var waypointIdPrev = nil;
var waypointVspeedChangedManually = 0;
var waypointVspeedMaxValue = 999999.0;
var waypointVspeedPrev = waypointVspeedMaxValue;

# need this for workarround for error in 'settimer()' ?!?
var apHeadingWaypointSetVSpeed_force = 0;
var apHeadingWaypointSetVSpeed_lastCalled = getprop("/sim/time/elapsed-sec");


var apHeadingWaypointSetVSpeed = func {
	if (	getprop("autopilot/locks/passive-mode") == 1 and
		getprop("autopilot/route-manager/active") == 1 and getprop("autopilot/route-manager/airborne") == 1) {

		if (apHeadingWaypointSetVSpeed_force == 0) {
			var now = getprop("/sim/time/elapsed-sec");
			if (now - apHeadingWaypointSetVSpeed_lastCalled < 28) {
				return;
			}
			apHeadingWaypointSetVSpeed_lastCalled = now;
		}
		
		var currentWaypointIndex = getprop("autopilot/route-manager/current-wp");
		var waypointId = getprop("autopilot/route-manager/wp/id");
		var waypointDistanceNm = getprop("autopilot/route-manager/wp/dist");
		#print("apHeadingWaypointSetVSpeed: waypointDistanceNm=", waypointDistanceNm);

		if (waypointId != nil and waypointId != "" and waypointDistanceNm != nil) {

			var groundspeedKt = getprop("velocities/groundspeed-kt");
			#print("apHeadingWaypointSetVSpeed: groundspeedKt=", groundspeedKt);

			var currentWaypointIndex = getprop("autopilot/route-manager/current-wp");
			#print("apHeadingWaypointSetVSpeed: currentWaypointIndex=", currentWaypointIndex);
			var altitudeFt = getprop("position/altitude-ft");
			var autopilotSettingAltitudeFt = getprop("autopilot/settings/target-altitude-ft");
			var waypointAlt = getprop("autopilot/route-manager/route/wp["~currentWaypointIndex~"]/altitude-ft");

			if (autopilotSettingAltitudeFt == nil or autopilotSettingAltitudeFt < 0) {
				if (waypointAlt != nil) {
					autopilotSettingAltitudeFt = waypointAlt;
				}
				else {
					autopilotSettingAltitudeFt = 0.0;
				}
			}
			var altitudeDistFt = autopilotSettingAltitudeFt - altitudeFt;
			#print("apHeadingWaypointSetVSpeed: altitudeDistFt=", altitudeDistFt);

			# calculate vspeed
			var vspeed = 0.0;
			if (waypointDistanceNm > 0.0) {
				var substructionNm = (waypointDistanceNm > 4.0 ? 4.0 : 0.0);
				vspeed = (altitudeDistFt * groundspeedKt / (waypointDistanceNm - substructionNm)) * 0.01; # nm/h -> ft/min : factor=0.01
				vspeed += vspeed * 0.25; # make sure to reach the destination altitude before reaching the waypoint (add 25%)
			}
			# clamb: limit vspeed to min., max. values
			if (vspeed > 0) {
				maxVSpeed = 1500.0;
			}
			else {
				vspeed = (vspeed < -1000.0) ? -1000.0 : vspeed;
				vspeed = (vspeed > -200.0) ? -200.0 : vspeed;
			}

			# clamp climbrate according to weigth, altitude etc.
			var minClimpRate = -1500.0;
			var maxClimpRate = 1500.0;
			vspeed = (vspeed < minClimpRate ? minClimpRate : vspeed);
			vspeed = (vspeed > maxClimpRate ? maxClimpRate : vspeed);

			#print("apHeadingWaypointSetVSpeed: listenerApHeadingWaypoint: vspeed=", vspeed);
			var vspeedPrev = getprop("autopilot/settings/vertical-speed-fpm");
			if (vspeedPrev == nil) {
				vspeedPrev = waypointVspeedMaxValue;
			}
			# set vspeed, only if vspeed has not been changed mannually and the change is greater than 5%
			if (vspeedPrev == waypointVspeedPrev or waypointVspeedPrev == waypointVspeedMaxValue) {
				waypointVspeedChangedManually = 0;
			}
			else {
				waypointVspeedChangedManually = 1;
			}
			if (waypointVspeedChangedManually == 0 and (abs(vspeed) > abs(vspeedPrev * 0.05))) {
				setprop("autopilot/settings/vertical-speed-fpm", vspeed);
				waypointVspeedPrev = vspeed;
			}

			if (	getprop("autopilot/locks/altitude") != "vertical-speed-hold" and
				getprop("autopilot/locks/altitude") != "altitude-hold") {
				setprop("autopilot/locks/altitude", "vertical-speed-hold");
			}

			setprop("autopilot/settings/altitude-ft", autopilotSettingAltitudeFt);
		}
	}
}

var apHeadingWaypointSetVSpeedRepeat = func() {

	if (	getprop("autopilot/locks/passive-mode") == 1 and
		getprop("autopilot/route-manager/active") == 1 and getprop("autopilot/route-manager/airborne") == 1) {

		apHeadingWaypointSetVSpeed_force = 0;

		apHeadingWaypointSetVSpeed();

		# settimer for corretion of vspeed each 30 seconds
		if (waypointVspeedChangedManually == 0 and getprop("autopilot/locks/altitude") == "vertical-speed-hold") {
			settimer(apHeadingWaypointSetVSpeedRepeat, 30.0);
		}
	}
}
var apHeadingWaypointSetVSpeedStart = func() {

	apHeadingWaypointSetVSpeed_force = 1;

	apHeadingWaypointSetVSpeed();

	apHeadingWaypointSetVSpeed_force = 0;

	# settimer for corretion of vspeed each 30 seconds
	if (waypointVspeedChangedManually == 0) {
		settimer(apHeadingWaypointSetVSpeedRepeat, 30.0);
	}
}

var switchedToAltHold = 0;
setlistener("autopilot/route-manager/current-wp", func {switchedToAltHold = 0;} );

var waypointDistanceNmHold = 1.0;
var waypointDistanceNm = 36000.0;
var listenerApPassiveMode = func {

	var routeManagerWaypointNearBy = 0;

	if (getprop("autopilot/locks/passive-mode") == 1) {

		var timerInterval = 0.5;

		var groundspeedKt = getprop("velocities/groundspeed-kt");

		if (getprop("autopilot/route-manager/active") == 1 and getprop("autopilot/route-manager/airborne") == 1) {

			var currentWaypointIndex = getprop("autopilot/route-manager/current-wp");
			var waypointId = getprop("autopilot/route-manager/wp/id");
			var waypointDistanceNmCurrent = getprop("autopilot/route-manager/wp/dist");
			var waypointDistanceNmIsReal = 0;
			# workarround: sometimes after switch of current-waypoint the distance isn't
			# yet updated (FG-bug  ?!?), so wait until there's a major change in distance
			if (abs(waypointDistanceNmCurrent - waypointDistanceNm) > 0.0000001) {
				waypointDistanceNm = waypointDistanceNmCurrent;
				waypointDistanceNmIsReal = 1;
			}
			else {
				waypointDistanceNmIsReal = 0;
			}

			if (waypointId != nil and waypointId != "" and waypointDistanceNm != nil and waypointDistanceNmIsReal == 1) {

				if (getprop("autopilot/locks/heading") != "true-heading-hold") {
					setprop("autopilot/locks/heading", "true-heading-hold");
				}

				if (waypointId == waypointIdPrev) {
					# 'smoothing' on waypoint-transition:
					# avoid heading change near active waypoint due to great angle difference -> keep actual heading
					if (getprop("autopilot/internal/route-manager-waypoint-near-by") == 0) {
						waypointDistanceNmHold = 0.5 + (groundspeedKt * 0.001);
					}
					if (waypointDistanceNm < waypointDistanceNmHold)  {
						if (getprop("autopilot/internal/route-manager-waypoint-near-by") == 0) {
	
							# smoothing: interpolate Kp for heading-hold
							listenerApHeadingPassiveModeFunc();
						}
						routeManagerWaypointNearBy = 1;
					}
					# don't need to do this, the route manager does it already
					#else {
					#	setprop("autopilot/settings/true-heading-deg",
					#		getprop("autopilot/route-manager/wp["~currentWaypointIndex~"]/bearing-deg"));
					#}
				}

				if (waypointId != waypointIdPrev) {
					waypointVspeedPrev = waypointVspeedMaxValue;
					waypointVspeedChangedManually = 0;

					setprop("autopilot/locks/altitude", "");

					routeManagerWaypointNearBy = 1;
					settimer(apHeadingWaypointSetVSpeedStart , 1.0);
				}

				var altitudeFt = getprop("instrumentation/altimeter/indicated-altitude-ft");
				var autopilotSettingAltitudeFt = getprop("autopilot/settings/target-altitude-ft");
				var waypointAlt = getprop("autopilot/route-manager/route/wp["~currentWaypointIndex~"]/altitude-ft");
				if (autopilotSettingAltitudeFt == nil or autopilotSettingAltitudeFt < 0) {
					if (waypointAlt != nil) {
						autopilotSettingAltitudeFt = waypointAlt;
					}
					else {
						autopilotSettingAltitudeFt = 0.0;
					}
				}

				var altitudeDistFt = autopilotSettingAltitudeFt - altitudeFt;
				var altitudeDistFtSwitch = 350.0;
				if (abs(getprop("velocities/vertical-speed-fps")) < 25.0) {
					# abs(vspeed) < 1500.0 fpm -> switch to altitude-hold a bit later
					altitudeDistFtSwitch -= (25.0 - abs(getprop("velocities/vertical-speed-fps"))) * 10.0;
				}
				var waypointDistanceNmSwitch = 0.5 + (groundspeedKt * 0.001);
				if (abs(altitudeDistFt) < altitudeDistFtSwitch or waypointDistanceNm < waypointDistanceNmSwitch) {
					if (switchedToAltHold == 0 and getprop("autopilot/locks/altitude") == "vertical-speed-hold") {
						setprop("autopilot/locks/altitude", "altitude-hold");
						switchedToAltHold = 1;
					}
				}

				# switch to next waypoint on short distance in order to smooth the curve to fly (not for last waypoint)
				if (waypointId == waypointIdPrev
					and currentWaypointIndex < getprop("autopilot/route-manager/route/num") - 1) {

					var groundspeedKt = getprop("velocities/groundspeed-kt");

					# calculate the correct theoretical value (followed by standard-turn: 360° -> 120 seconds)
					# with an aircraft-specific factor (experimental: flightgear-aircrafts doesn't fly ideal standard-turns)
					var radiusMiles = groundspeedKt * 0.005306 * wpAircraftSpecificTurnFactor;
					#print("radiusMiles=", radiusMiles);

					var waypointDistanceNmSwitchToNext = radiusMiles;

					if (currentWaypointIndex > 0) {

						# calculate actual heading fault
						var headingDeg = getprop("orientation/heading-deg");
						var indicatedTrackDeg = getprop("instrumentation/gps/indicated-track-true-deg");
						var trackDiff = 0.0;
						if (headingDeg < 180.0 and indicatedTrackDeg >= 180.0) {
							trackDiff = abs((indicatedTrackDeg - 360) - headingDeg);
						}
						else {
							trackDiff = abs(headingDeg - indicatedTrackDeg);
						}
						# if current heading fault less than 3 deg: take current heading as reference,
						# else take the bearing of the former waypoint as reference
						var currentBearingReference = (trackDiff < 3.0) ? headingDeg :
							getprop("autopilot/route-manager/route/wp["~(currentWaypointIndex-1)~"]/leg-bearing-true-deg");
						var wptBearingDiff = (abs(currentBearingReference
							- getprop("autopilot/route-manager/route/wp["~currentWaypointIndex~"]/leg-bearing-true-deg")));
						wptBearingDiff = ((wptBearingDiff > 180.0) ? (wptBearingDiff - 180.0) : wptBearingDiff);

						#print("wptBearingDiff=", wptBearingDiff);

						# calculate distance to switch (I'm not such a good mathematican, so this may not be all in all correct)
						var absWptBearingDiff = abs(wptBearingDiff);
						if (absWptBearingDiff < 90) {
							waypointDistanceNmSwitchToNext = (radiusMiles * sinus(absWptBearingDiff)) -
								(cosinus(absWptBearingDiff) * tangens(90 - absWptBearingDiff));
						}
						elsif (absWptBearingDiff > 90 and absWptBearingDiff < 180) {
							absWptBearingDiff = absWptBearingDiff - 90;
							absWptBearingDiff = (absWptBearingDiff < 120 ? absWptBearingDiff : 120);	# clamp to 120
							waypointDistanceNmSwitchToNext = waypointDistanceNmSwitchToNext +
								(radiusMiles * sinus(absWptBearingDiff));
						}

						# add an inertial-turn offset (the aircraft needs some time to get into 20° turn)
						waypointDistanceNmSwitchToNext = waypointDistanceNmSwitchToNext + (wpAircraftSpecificTurnInertiaFactor * groundspeedKt);

						#print("waypointDistanceNmSwitchToNext=", waypointDistanceNmSwitchToNext);
					}
					#print("waypointDistanceNmHold=", waypointDistanceNmHold);

					# clamp to 6 nm max.
					waypointDistanceNmSwitchToNext = ((waypointDistanceNmSwitchToNext > 6.0) ? 6.0
										: waypointDistanceNmSwitchToNext);
					#print("waypointDistanceNmSwitchToNext=", waypointDistanceNmSwitchToNext);

					# waypointDistanceNmSwitchToNext = <distance to waypoint on which to switch to the next waypoint>
					# (have to switch before reaching waypoint, because we have to take in account the curve the aircraft goes)
					if (waypointDistanceNm  < waypointDistanceNmSwitchToNext)  {
						setprop("autopilot/route-manager/current-wp", currentWaypointIndex + 1);
						waypointDistanceNmHold = 1.0;
						timerInterval = 3.0;	# wait a bit longer, so FG-route-manager can switch all vars
					}
				}

				waypointIdPrev = waypointId;
			}
		}

		if (groundspeedKt != nil) {
			timerInterval -= (groundspeedKt * 0.005);
		}

		setprop("autopilot/internal/route-manager-waypoint-near-by", routeManagerWaypointNearBy);

		settimer(listenerApPassiveMode , timerInterval);
	}
	else {
		# we are switched off -> cleanup

		if (getprop("autopilot/locks/heading") == "true-heading-hold") {
			setprop("autopilot/locks/heading", "");
		}
		setprop("autopilot/internal/route-manager-waypoint-near-by", 0);

		waypointDistanceNmHold = 1.0;
		waypointDistanceNm = 36000.0;
		switchedToAltHold = 0;
		waypointIdPrev = nil;
		waypointVspeedChangedManually = 0;
		waypointVspeedPrev = waypointVspeedMaxValue;
		apHeadingWaypointSetVSpeed_force = 0;
	}
}
setlistener("autopilot/locks/passive-mode", listenerApPassiveMode);

var listenerApAltitudeClambFunc = func {
	if (getprop("/autopilot/locks/altitude") == "gs1-hold") {

		#print("listenerApAltitudeClambFunc -> triggered");

		setprop("/autopilot/internal/gs-rate-of-climb-near-far-filtered", getprop("/velocities/vertical-speed-fps"));
	}
}
setlistener("/autopilot/locks/altitude", listenerApAltitudeClambFunc);


var listenerApNav1NearFarFunc = func {
	if (getprop("/autopilot/locks/heading") == "nav1-hold") {

		#print ("-> listenerApNav1NearFarFunc -> installed");

		var navDistance = getprop("instrumentation/nav[0]/nav-distance");

		# 'smooth' VOR-transition
		if (getprop("instrumentation/nav[0]/gs-in-range") == 0 and navDistance < 2000.0) {
			if (getprop("/autopilot/internal/VOR-near-by") == 0) {
				listenerApHeadingSwitchFunc();

				var targetRollDeg = getprop("/autopilot/internal/target-roll-deg");
				setprop("/autopilot/internal/target-roll-deg-for-VOR-near-by", 0.0);

				setprop("/autopilot/internal/VOR-near-by", 1);

				interpolate("/autopilot/internal/target-roll-deg-for-VOR-near-by", targetRollDeg, 8.0);
			}
		}
		else {
			if (getprop("/autopilot/internal/VOR-near-by") == 1) {
				listenerApHeadingSwitchFunc();

				setprop("/autopilot/internal/VOR-near-by", 0);
			}
		}

		settimer(listenerApNav1NearFarFunc, 0.05);
	}
	else {
		setprop("/autopilot/internal/target-roll-deg-for-VOR-near-by", 0.0);
	}
}
setlistener("/autopilot/locks/heading", listenerApNav1NearFarFunc);


### speed with pitch

var listenerApSpeedWithPitchClambFunc = func {
	if (getprop("/autopilot/locks/speed") == "speed-with-pitch-trim") {
		#print ("-> listenerApSpeedWithPitchClambFunc -> installed");

		var pitch = getprop("/orientation/pitch-deg");
		setprop("/autopilot/internal/umin-for-speed-with-pitch-hold", (pitch < -5.0 ? -5.0 : pitch));
		interpolate("/autopilot/internal/umin-for-speed-with-pitch-hold", -5.0, 5);
		setprop("/autopilot/internal/umax-for-speed-with-pitch-hold", (pitch > 15.0 ? 15.0 : pitch));
		interpolate("/autopilot/internal/umax-for-speed-with-pitch-hold", 15.0, 5);
	}
}
var listenerApSpeedWithPitchSwitchFunc = func {
	if (getprop("/autopilot/locks/speed") == "speed-with-pitch-trim") {
		# disable pitch-/AoA-hold (makes no sence together with speed-with-pitch-hold)
		if (	getprop("/autopilot/locks/altitude") == "pitch-hold" or
			getprop("/autopilot/locks/altitude") == "aoa-hold") {
			setprop("/autopilot/locks/altitude", "");
		}
	}
}

setlistener("/autopilot/locks/speed", listenerApSpeedWithPitchClambFunc);
setlistener("/autopilot/settings/target-speed-kt", listenerApSpeedWithPitchClambFunc);
setlistener("/autopilot/locks/speed", listenerApSpeedWithPitchSwitchFunc);


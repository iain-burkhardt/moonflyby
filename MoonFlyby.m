function result = MoonFlyby(startDate)
% MOONFLYBY  Date-based Earth-to-Moon flyby simulator.
%
% Requires PositionFetch.m in the same folder.
%
% Usage:
%   result = MoonFlyby("2027-04-01 00:00:00");
%   result = MoonFlyby(datetime(2027,4,1,0,0,0));
%
% Model:
%   - Earth-centred, non-rotating ICRF-like frame
%   - Actual Moon and Sun positions/velocities from JPL Horizons through
%     PositionFetch.m
%   - Newtonian point-mass gravity from Earth, Moon, and Sun
%   - Sun and Moon differential accelerations account for the
%     Earth-centred (accelerating) reference frame
%   - Lambert transfer gives an initial translunar-injection estimate
%   - fminsearch adjusts the departure velocity to target a lunar flyby
%   - ode113 numerically propagates the resulting trajectory
%
% Important:
%   This is a physically based educational simulator, not a validated
%   Artemis II reconstruction or mission-design tool. The current version
%   targets a lunar flyby; it does NOT guarantee an Artemis-style
%   Earth-return/free-return trajectory, atmospheric entry, launch vehicle
%   performance, or operational safety. The point-mass model omits
%   nonspherical gravity, Earth/Moon rotation, maneuver execution errors,
%   solar radiation pressure, and other smaller effects.

    if nargin < 1 || isempty(startDate)
        startDate = datetime("now","TimeZone","UTC");
    end

    % Interpret a timezone-free datetime as UTC.
    if isdatetime(startDate)
        launchTime = startDate;
        if isempty(launchTime.TimeZone)
            launchTime.TimeZone = "UTC";
        else
            launchTime.TimeZone = "UTC";
        end
    else
        launchTime = datetime(startDate, ...
            "InputFormat","yyyy-MM-dd HH:mm:ss", ...
            "TimeZone","UTC");
    end

    if isnat(launchTime)
        error("Could not interpret startDate. Use yyyy-MM-dd HH:mm:ss.");
    end

    % ------------------------- Configuration ---------------------------
    muE = 398600.435507;       % Earth GM, km^3/s^2
    muM = 4902.800066;         % Moon GM, km^3/s^2
    muS = 132712440041.9394;  % Sun GM, km^3/s^2

    earthRadius = 6378.1363;  % km
    moonRadius  = 1737.4;     % km

    parkingAltitude = 200;    % km above mean Earth radius
    targetFlybyAltitude = 800; % km above lunar mean radius
    nominalTOFdays = 4.0;     % initial Earth-to-Moon transfer estimate
    totalDays = 12.0;         % propagation duration after departure

    % Horizons requests are made at one-hour intervals. PositionFetch
    % returns vectors relative to Earth because center='500@399'.
    tStart = char(string(launchTime,"yyyy-MM-dd HH:mm:ss"));
    endTime = launchTime + days(totalDays);
    tStop = char(string(endTime,"yyyy-MM-dd HH:mm:ss"));

    fprintf("Fetching JPL Horizons ephemerides...\n");
    
    stepSize = num2str(round(totalDays * 24));

    moon = PositionFetch("301","500@399",tStart,tStop,stepSize);
    sun  = PositionFetch("10","500@399",tStart,tStop,stepSize);

    if height(moon) < 3 || height(sun) < 3
        error("Horizons returned too few ephemeris samples.");
    end

    % Convert Julian dates to elapsed seconds from the first sample.
    tGrid = (moon.JD - moon.JD(1))*86400;
    tGridSun = (sun.JD - moon.JD(1))*86400;

    % Ensure both Horizons calls returned the same time grid.
    if numel(tGrid) ~= numel(tGridSun) || ...
            max(abs(tGrid-tGridSun)) > 0.5
        error("Moon and Sun ephemeris time grids do not match.");
    end

    moonPos = moon.Position_km;
    moonVel = moon.Velocity_kms;
    sunPos  = sun.Position_km;

    % Component-wise shape-preserving interpolation.
    moonPosition = cell(1,3);
    moonVelocity = cell(1,3);
    sunPosition = cell(1,3);
    for k = 1:3
        moonPosition{k} = griddedInterpolant(tGrid,moonPos(:,k), ...
            "pchip","linear");
        moonVelocity{k} = griddedInterpolant(tGrid,moonVel(:,k), ...
            "pchip","linear");
        sunPosition{k} = griddedInterpolant(tGrid,sunPos(:,k), ...
            "pchip","linear");
    end

    ephem.moonPosition = moonPosition;
    ephem.moonVelocity = moonVelocity;
    ephem.sunPosition = sunPosition;

    % --------------------- Initial Lambert estimate --------------------
    tFlyby = nominalTOFdays*86400;
    if tFlyby >= tGrid(end)
        error("Ephemeris interval is shorter than the transfer time.");
    end

    rLEO = earthRadius + parkingAltitude;
    r0 = [rLEO;0;0]; % chosen point on the initial parking orbit

    rMoonAtTOF = vectorAt(ephem.moonPosition,tFlyby);
    vMoonAtTOF = vectorAt(ephem.moonVelocity,tFlyby);

    % First solve aims at the Moon's centre to estimate arrival direction.
    [vLambert0,vLambertArrival] = lambertUV(r0,rMoonAtTOF,tFlyby,muE);
    vInfinityEstimate = vLambertArrival-vMoonAtTOF;

    % Select a B-plane-like offset perpendicular to the estimated
    % incoming lunar-relative velocity. The offset is the desired
    % Moon-centred closest-approach radius, not an altitude.
    bDirection = cross(vInfinityEstimate,vMoonAtTOF);
    if norm(bDirection) < 1e-8
        bDirection = cross(vInfinityEstimate,[0;0;1]);
    end
    if norm(bDirection) < 1e-8
        bDirection = [0;1;0];
    end
    bDirection = bDirection/norm(bDirection);

    targetRadius = moonRadius + targetFlybyAltitude;
    targetAtFlyby = rMoonAtTOF + targetRadius*bDirection;

    [vLambert,~] = lambertUV(r0,targetAtFlyby,tFlyby,muE);

    % ------------------- Three-body targeting correction ---------------
    % ------------------- Three-body targeting correction ---------------
    fprintf("Correcting departure velocity with three-body dynamics...\n");

    % Use a scaled velocity correction so the optimizer works with
    % dimensionless variables rather than very small km/s values.
    velocityScale = 0.01; % km/s per optimization unit

    opt = optimset("Display","iter", ...
        "MaxIter",1000, ...
        "MaxFunEvals",5000, ...
        "TolX",1e-9, ...
        "TolFun",1e-9);

    objective = @(x) targetingCost( ...
        velocityScale*x(:),vLambert,r0,targetAtFlyby, ...
        tFlyby,ephem,muE,muM,muS);

    xCorrection = fminsearch(objective,[0;0;0],opt);

    deltaVCorrection = velocityScale*xCorrection(:);
    vInitial = vLambert + deltaVCorrection;

    fprintf("Final targeting cost: %.6e\n", ...
        objective(xCorrection));
    fprintf("Velocity correction magnitude: %.6f km/s\n", ...
        norm(deltaVCorrection));

    % ---------------------- Full trajectory propagation ----------------
    y0 = [r0;vInitial];
    tOutput = linspace(0,totalDays*86400,2401);

    odeOptions = odeset("RelTol",1e-10,"AbsTol",1e-11, ...
        "MaxStep",300);

    fprintf("Propagating spacecraft trajectory...\n");
    [t,Y] = ode113(@(tt,yy) spacecraftODE(tt,yy,ephem,muE,muM,muS), ...
        tOutput,y0,odeOptions);

    spacecraftPosition = Y(:,1:3);
    spacecraftVelocity = Y(:,4:6);

    moonTrajectory = zeros(numel(t),3);
    for k = 1:numel(t)
        moonTrajectory(k,:) = vectorAt(ephem.moonPosition,t(k)).';
    end

    % Closest lunar approach within +/- 24 hours of the nominal encounter.
    lunarWindow = abs(t-tFlyby) <= 86400;
    lunarDistances = vecnorm(spacecraftPosition(lunarWindow,:) - ...
        moonTrajectory(lunarWindow,:),2,2);
    lunarTimes = t(lunarWindow);
    [lunarClosestDistance,iMoon] = min(lunarDistances);
    lunarClosestTime = lunarTimes(iMoon);
    lunarAltitude = lunarClosestDistance-moonRadius;

    % Closest Earth approach after the lunar encounter.
    afterFlyby = t >= tFlyby;
    earthDistances = vecnorm(spacecraftPosition(afterFlyby,:),2,2);
    returnTimes = t(afterFlyby);
    [earthClosestDistance,iEarth] = min(earthDistances);
    earthClosestTime = returnTimes(iEarth);
    earthClosestAltitude = earthClosestDistance-earthRadius;

    % Departure delta-v relative to a circular parking orbit whose
    % tangential direction is aligned with the required departure velocity.
    parkingSpeed = sqrt(muE/rLEO);
    vParking = parkingSpeed*vInitial/norm(vInitial);
    deltaV = norm(vInitial-vParking);

    % ----------------------------- Results ------------------------------
    result.launchTime = launchTime;
    result.timeSeconds = t;
    result.spacecraftPosition_km = spacecraftPosition;
    result.spacecraftVelocity_kms = spacecraftVelocity;
    result.moonPosition_km = moonTrajectory;
    result.initialPosition_km = r0;
    result.initialVelocity_kms = vInitial;
    result.lambertVelocity_kms = vLambert;
    result.departureCorrection_kms = deltaVCorrection;
    result.estimatedTLI_kms = deltaV;
    result.lunarClosestApproach_km = lunarClosestDistance;
    result.lunarFlybyAltitude_km = lunarAltitude;
    result.lunarClosestTime_days = lunarClosestTime/86400;
    result.earthClosestApproach_km = earthClosestDistance;
    result.earthClosestAltitude_km = earthClosestAltitude;
    result.earthClosestTime_days = earthClosestTime/86400;

    fprintf("\n========== MOON FLYBY RESULTS ==========\n");
    fprintf("Launch epoch:                 %s UTC\n",tStart);
    fprintf("Estimated departure delta-v:  %.4f km/s\n",deltaV);
    fprintf("Three-body velocity correction: [%.5f %.5f %.5f] km/s\n", ...
        deltaVCorrection(1),deltaVCorrection(2),deltaVCorrection(3));
    fprintf("Closest lunar distance:       %.2f km\n",lunarClosestDistance);
    fprintf("Closest lunar altitude:       %.2f km\n",lunarAltitude);
    fprintf("Lunar closest approach time:  %.3f days\n", ...
        lunarClosestTime/86400);
    fprintf("Closest Earth distance after flyby: %.2f km\n", ...
        earthClosestDistance);
    fprintf("Closest Earth altitude after flyby: %.2f km\n", ...
        earthClosestAltitude);
    fprintf("Earth closest approach time:  %.3f days\n", ...
        earthClosestTime/86400);
    fprintf("========================================\n");

    % ------------------------------ Plot --------------------------------
    figure("Name","Earth-Moon Flyby","Color","w");
    hold on;
    set(gca,"Color","w");
    grid on;
    axis equal;

    plot3(spacecraftPosition(:,1),spacecraftPosition(:,2), ...
        spacecraftPosition(:,3),"r-","LineWidth",1.6);
    plot3(moonTrajectory(:,1),moonTrajectory(:,2), ...
        moonTrajectory(:,3),"b--","LineWidth",1.2);
    plot3(0,0,0,"bo","MarkerFaceColor","b","MarkerSize",9);

    plot3(spacecraftPosition(1,1),spacecraftPosition(1,2), ...
        spacecraftPosition(1,3),"go","MarkerFaceColor","g");
    plot3(spacecraftPosition(end,1),spacecraftPosition(end,2), ...
        spacecraftPosition(end,3),"ro","MarkerFaceColor","r");

    [sx,sy,sz] = sphere(32);
    surf(earthRadius*sx,earthRadius*sy,earthRadius*sz, ...
        "FaceAlpha",0.25,"EdgeColor","none");

    moonAtClosest = vectorAt(ephem.moonPosition,lunarClosestTime);
    scAtClosest = interp1(t,spacecraftPosition,lunarClosestTime);
    plot3(moonAtClosest(1),moonAtClosest(2),moonAtClosest(3), ...
        "bo","MarkerFaceColor","c","MarkerSize",7);
    plot3(scAtClosest(1),scAtClosest(2),scAtClosest(3), ...
        "ko","MarkerFaceColor","y","MarkerSize",7);

    xlabel("X (km)"); ylabel("Y (km)"); zlabel("Z (km)");
    title("Earth-centred spacecraft trajectory");
    legend("Spacecraft","Moon orbit","Earth","Departure", ...
        "Final spacecraft position","Moon at closest approach", ...
        "Spacecraft at closest lunar approach", ...
        "Location","bestoutside");
    view(3);
    hold off;

    % Plot Earth-Moon separation and spacecraft-to-Moon distance.
    figure("Name","Lunar Encounter Range","Color","w");
    scMoonRange = vecnorm(spacecraftPosition-moonTrajectory,2,2);
    plot(t/86400,scMoonRange,"LineWidth",1.5);
    hold on;
    yline(moonRadius,"k--","Lunar surface");
    xline(tFlyby/86400,"r:","Nominal encounter");
    grid on;
    xlabel("Elapsed time (days)");
    ylabel("Spacecraft-Moon distance (km)");
    title("Spacecraft distance from the Moon");
    hold off;
end

% ============================ Local functions ===========================

function cost = targetingCost(dv,vBase,r0,target,tTarget,ephem,muE,muM,muS)
    v0 = vBase+dv(:);
    y0 = [r0;v0];
    opts = odeset("RelTol",2e-9,"AbsTol",1e-10,"MaxStep",600);
    try
        [~,Y] = ode113(@(tt,yy) spacecraftODE(tt,yy,ephem,muE,muM,muS), ...
            [0 tTarget],y0,opts);
        missKm = norm(Y(end,1:3).'-target);
        % Scale terms so miss distance dominates, while keeping the
        % correction near the Lambert estimate.
        cost = (missKm/100)^2 + (norm(dv)/0.05)^2;
        if ~isfinite(cost)
            cost = 1e30;
        end
    catch
        cost = 1e30;
    end
end

function dydt = spacecraftODE(t,y,ephem,muE,muM,muS)
    r = y(1:3);
    v = y(4:6);

    rMoon = vectorAt(ephem.moonPosition,t);
    rSun  = vectorAt(ephem.sunPosition,t);

    rEarthToMoon = rMoon;
    rEarthToSun = rSun;

    aEarth = -muE*r/norm(r)^3;

    dMoon = rEarthToMoon-r;
    aMoon = muM*(dMoon/norm(dMoon)^3 - ...
        rEarthToMoon/norm(rEarthToMoon)^3);

    dSun = rEarthToSun-r;
    aSun = muS*(dSun/norm(dSun)^3 - ...
        rEarthToSun/norm(rEarthToSun)^3);

    dydt = [v; aEarth+aMoon+aSun];
end

function vec = vectorAt(interpolants,t)
    vec = zeros(3,1);
    for j = 1:3
        vec(j) = interpolants{j}(t);
    end
end

function [v1,v2] = lambertUV(r1vec,r2vec,dt,mu)
% Universal-variable, zero-revolution Lambert solver (short/long way
% selected from the sign of the z component of the cross product).
    r1 = norm(r1vec);
    r2 = norm(r2vec);
    cosDtheta = dot(r1vec,r2vec)/(r1*r2);
    cosDtheta = max(-1,min(1,cosDtheta));

    cross12 = cross(r1vec,r2vec);
    if cross12(3) >= 0
        sinDtheta = sqrt(max(0,1-cosDtheta^2));
    else
        sinDtheta = -sqrt(max(0,1-cosDtheta^2));
    end

    denom = 1-cosDtheta;
    if abs(denom) < 1e-12
        error("Lambert geometry is nearly collinear.");
    end
    A = sinDtheta*sqrt(r1*r2/denom);

    if abs(A) < 1e-12
        error("Lambert solver encountered degenerate geometry.");
    end

    z = 0;
    target = sqrt(mu)*dt;
    for iter = 1:500
        [C,S] = stumpff(z);
        if C <= 0
            z = z+0.1;
            continue;
        end
        y = r1+r2+A*(z*S-1)/sqrt(C);
        if y < 0
            z = z+0.1;
            continue;
        end
        F = (y/C)^(3/2)*S+A*sqrt(y)-target;

        if abs(F) < 1e-7
            break;
        end

        dz = 1e-5*max(1,abs(z));
        [Cp,Sp] = stumpff(z+dz);
        yp = r1+r2+A*((z+dz)*Sp-1)/sqrt(Cp);
        Fp = (yp/Cp)^(3/2)*Sp+A*sqrt(yp)-target;
        derivative = (Fp-F)/dz;

        if ~isfinite(derivative) || abs(derivative) < 1e-12
            z = z+sign(-F)*0.1;
        else
            zNew = z-F/derivative;
            if ~isfinite(zNew) || abs(zNew-z) > 10
                zNew = z-sign(F)*0.1;
            end
            z = zNew;
        end
    end

    [C,S] = stumpff(z);
    y = r1+r2+A*(z*S-1)/sqrt(C);
    if y <= 0 || ~isfinite(y)
        error("Lambert solver failed to find a valid transfer.");
    end

    f = 1-y/r1;
    g = A*sqrt(y/mu);
    gdot = 1-y/r2;

    if abs(g) < 1e-12
        error("Lambert solver produced a near-zero g coefficient.");
    end

    v1 = (r2vec-f*r1vec)/g;
    v2 = (gdot*r2vec-r1vec)/g;
end

function [C,S] = stumpff(z)
    if z > 1e-8
        sz = sqrt(z);
        C = (1-cos(sz))/z;
        S = (sz-sin(sz))/sz^3;
    elseif z < -1e-8
        sz = sqrt(-z);
        C = (cosh(sz)-1)/(-z);
        S = (sinh(sz)-sz)/sz^3;
    else
        C = 1/2;
        S = 1/6;
    end
end

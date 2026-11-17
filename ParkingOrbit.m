function po = ParkingOrbit(alt_km, inc_deg, launchSite, tLaunch, coastAngle_deg, pass)
% PARKINGORBIT  Initial state of the spacecraft in its circular parking orbit.
%
% Finds the orbit plane that passes over the launch site at launch time,
% places the spacecraft over the site (orbit insertion), then moves it
% "coastAngle_deg" further around the orbit to the point where the
% translunar injection (TLI) burn will happen.
%
% INPUTS:
%   alt_km         - parking orbit altitude above Earth's surface [km]
%   inc_deg        - orbit inclination [deg]; must be >= |site latitude|
%   launchSite     - struct from launch_site_selector (.lat_deg, .lon_deg)
%   tLaunch        - launch time, 'yyyy-MM-dd HH:mm:ss' (UT)
%   coastAngle_deg - (optional) degrees travelled after insertion before
%                    TLI. Can exceed 360 (multiple laps). Default 0.
%                    THIS IS THE VALUE TARGETING WILL ADJUST LATER.
%   pass           - (optional) 'ascending' (heading north-east, default)
%                    or 'descending' (heading south-east)
%
% OUTPUT (struct), all in the Earth-centered inertial frame:
%   po.r0, po.v0   - position [km] / velocity [km/s] at insertion (3x1)
%   po.r,  po.v    - position / velocity at the TLI point (3x1)
%   po.tCoast      - time from insertion to TLI point [s]
%   po.radius      - orbit radius [km]
%   po.speed       - circular orbit speed [km/s]
%   po.period      - orbit period [s]
%   po.RAAN_deg    - right ascension of ascending node [deg]
%   po.u0_deg      - argument of latitude at insertion [deg]
%   po.uTLI_deg    - argument of latitude at TLI point [deg]
%
% SIMPLIFICATIONS (list these on the error slide):
%   - Spherical Earth, launch-site altitude ignored
%   - Rocket reaches orbit directly over the launch site (no downrange
%     travel during ascent, ascent takes zero time)
%   - GMST formula gives Earth's rotation in an "equator of date" frame;
%     ICRF differs from it by ~0.4 deg of precession around 2027
%
% EXAMPLE:
%   site.lat_deg = 28.6084;  site.lon_deg = -80.6043;   % KSC
%   po = ParkingOrbit(185, 28.6084, site, '2027-01-01 00:00:00', 90);

if nargin < 5, coastAngle_deg = 0; end
if nargin < 6, pass = 'ascending'; end

%% 1. Constants
muE = 398600.4418;   % Earth gravitational parameter [km^3/s^2]
RE  = 6378.137;      % Earth equatorial radius [km]

%% 2. Circular orbit size and speed
R = RE + alt_km;             % orbit radius [km]
V = sqrt(muE / R);           % circular speed [km/s]
n = V / R;                   % angular rate [rad/s]

%% 3. Check that the site can reach this inclination
% An orbit can't pass over a latitude higher than its inclination, so
% e.g. KSC (28.6 N) can't launch straight into a 10 deg orbit.
lat = deg2rad(launchSite.lat_deg);
lon = deg2rad(launchSite.lon_deg);
inc = deg2rad(inc_deg);

ratio = sin(lat) / sin(inc);
if abs(ratio) > 1 + 1e-12
    error(['ParkingOrbit: inclination %.2f deg is below the launch ' ...
           'site latitude %.2f deg - that orbit never passes over the site.'], ...
           inc_deg, launchSite.lat_deg);
end
ratio = max(min(ratio, 1), -1);   % guard against rounding just past 1

%% 4. Where is the launch site in inertial space at launch?
% Earth rotates under the inertial frame. GMST is the angle between the
% inertial X axis and the Greenwich meridian; adding the site longitude
% gives the site's "local sidereal time" theta.
jd    = juliandate(datetime(tLaunch, 'InputFormat', 'yyyy-MM-dd HH:mm:ss'));
theta = deg2rad(gmst_deg(jd)) + lon;

%% 5. Solve for the orbit plane that passes over the site
% Spherical trigonometry for a point on an inclined orbit:
%   sin(lat)   = sin(inc) * sin(u)             -> u = argument of latitude
%   tan(delta) = cos(inc) * tan(u)             -> delta = longitude past node
% where u is measured from the ascending node along the orbit, and delta
% is measured along the equator. Then RAAN = theta - delta.
u0 = asin(ratio);                      % ascending pass (moving north)
if strcmpi(pass, 'descending')
    u0 = pi - u0;                      % descending pass (moving south)
end

delta = atan2(cos(inc) * sin(u0), cos(u0));
RAAN  = mod(theta - delta, 2*pi);

%% 6. State at insertion and at the TLI point
[po.r0, po.v0] = circ_state(R, V, RAAN, inc, u0);

uTLI = u0 + deg2rad(coastAngle_deg);
[po.r, po.v] = circ_state(R, V, RAAN, inc, uTLI);

po.tCoast   = deg2rad(coastAngle_deg) / n;
po.radius   = R;
po.speed    = V;
po.period   = 2*pi / n;
po.RAAN_deg = rad2deg(RAAN);
po.u0_deg   = rad2deg(u0);
po.uTLI_deg = mod(rad2deg(uTLI), 360);

%% 7. Self-check: insertion point should sit right above the site
siteHat = [cos(lat)*cos(theta); cos(lat)*sin(theta); sin(lat)];
errDeg  = rad2deg(acos(max(min(dot(po.r0/R, siteHat), 1), -1)));
if errDeg > 1e-6
    warning('ParkingOrbit: insertion point is %.4f deg off the site.', errDeg);
end

end


%% Local function: position and velocity on a circular orbit
function [r, v] = circ_state(R, V, RAAN, inc, u)
% Standard rotation from orbital elements to inertial coordinates for a
% circular orbit (eccentricity = 0, so only RAAN, inc, and u matter).
cO = cos(RAAN);  sO = sin(RAAN);
ci = cos(inc);   si = sin(inc);
cu = cos(u);     su = sin(u);

r = R * [cO*cu - sO*su*ci;
         sO*cu + cO*su*ci;
         su*si];

% Velocity is perpendicular to r, in the orbit plane, in the direction of
% motion (derivative of r with respect to u, scaled to speed V)
v = V * [-cO*su - sO*cu*ci;
         -sO*su + cO*cu*ci;
          cu*si];
end


%% Local function: Greenwich Mean Sidereal Time
function g = gmst_deg(jd)
% IAU 1982 GMST formula (Vallado, "Fundamentals of Astrodynamics").
% Input: Julian date (UT). Output: GMST in degrees, 0-360.
Tc = (jd - 2451545.0) / 36525;   % Julian centuries since J2000
g  = 280.46061837 + 360.98564736629 * (jd - 2451545.0) ...
     + 0.000387933 * Tc^2 - Tc^3 / 38710000;
g  = mod(g, 360);
end

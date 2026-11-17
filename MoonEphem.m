function moon = MoonEphem(tLaunch, durationDays, step)
% MOONEPHEM  Moon position/velocity relative to Earth at ANY time.
%
% Pulls cached (or fresh) hourly Horizons data for the mission window and
% fits cubic splines through it, so the trajectory integrator (ode113) can
% ask for the Moon's state at any time, not just on the hour.
%
% INPUTS:
%   tLaunch      - launch time, 'yyyy-MM-dd HH:mm:ss' (UT)
%   durationDays - length of the window to cover (use max mission duration)
%   step         - (optional) Horizons step, default '1 h'
%
% OUTPUT (struct):
%   moon.pos(t)  - 3x1 Moon position [km],   t = seconds after launch
%   moon.vel(t)  - 3x1 Moon velocity [km/s], t = seconds after launch
%   moon.jd0     - Julian date of launch
%   moon.tMax    - last valid time [s]
%   moon.T       - raw Horizons table (for plotting / checks)
%
% EXAMPLE:
%   moon = MoonEphem('2027-01-01 00:00:00', 12);
%   rM = moon.pos(3*86400);   % Moon position 3 days after launch
%
% ACCURACY NOTE:
%   The Moon moves ~3,700 km per hour, but its path is very smooth, so a
%   cubic spline through hourly points is accurate to well under 1 km -
%   far smaller than the other errors listed in the validation section.

if nargin < 3, step = '1 h'; end

fmt  = 'yyyy-MM-dd HH:mm:ss';
t0   = datetime(tLaunch, 'InputFormat', fmt);

% Pad one day on each side so the spline is well-behaved at the ends
% (splines get less accurate right at the first and last data points).
padDays = 1;
tStart  = datestr(t0 - days(padDays),                'yyyy-mm-dd HH:MM:SS');
tStop   = datestr(t0 + days(durationDays + padDays), 'yyyy-mm-dd HH:MM:SS');

% Moon relative to Earth center, ICRF frame (our Earth-centered inertial)
T = EphemCache('301', '500@399', tStart, tStop, step);

% Convert Julian dates to seconds after launch
jd0  = juliandate(t0);
tsec = (T.JD - jd0) * 86400;

% spline() wants each component as a ROW, so transpose the Nx3 matrices.
% The result "pp" is a piecewise polynomial; ppval(pp, t) evaluates it
% and returns a 3x1 column vector - the shape ode113 expects.
ppPos = spline(tsec', T.Position_km');
ppVel = spline(tsec', T.Velocity_kms');

moon.pos  = @(t) ppval(ppPos, t);
moon.vel  = @(t) ppval(ppVel, t);
moon.jd0  = jd0;
moon.tMax = durationDays * 86400;
moon.T    = T;

end

%% MoonFlyby.m  -  Earth-to-Moon free-return flyby, targeted against JPL Horizons
%
% What it does
%   1. Pulls the Moon's real position/velocity (Earth-centered, ICRF) from
%      NASA Horizons using PositionFetch.m.
%   2. Starts from a circular low-Earth parking orbit and applies a single
%      trans-lunar injection (TLI) burn.
%   3. SOLVES for the TLI burn point and size so that the spacecraft
%        (a) passes the Moon at the periselene altitude you ask for, and
%        (b) swings back and reaches Earth at the perigee altitude you ask
%            for (a free-return "figure 8", like Apollo 8/13 or Artemis).
%      Instead of guessing a launch, it does a coarse grid search for
%      candidates and then refines with a Newton iteration.
%   4. Makes four readable figures (all are normal MATLAB figures, so
%      zoom/pan tools work).
%
% Model: point-mass Earth + point-mass Moon (Moon position interpolated
% from Horizons).  No Sun, no J2, no drag - fine for a flyby study, but the
% numbers will differ a little from a full mission design.
%
% Requires: PositionFetch.m on the path, internet access, base MATLAB only
% (no toolboxes).  Needs R2018b or newer (xline/yline, local functions in
% scripts).
%
% ---------------------------------------------------------------------
% GLOSSARY (terms used throughout the comments)
%   TLI        = Trans-Lunar Injection: the one engine burn that sends the
%                spacecraft from Earth orbit toward the Moon.
%   Periselene = closest approach to the Moon.
%   Perigee    = closest approach to Earth.
%   dv         = "delta-v", the change in speed produced by the burn.
%   ICRF       = a fixed (non-rotating) coordinate frame used by astronomers.
%   Free return= a path that loops around the Moon and falls back to Earth
%                with no second burn needed.
%
% HOW THE SCRIPT IS ORGANIZED
%   Sections 1-8 run top to bottom as a normal script.
%   The "local functions" at the very bottom are helper routines that the
%   script calls; MATLAB requires them to be at the END of a script file.
%
% CONVENTIONS
%   Positions are in km, velocities in km/s, times in seconds.
%   A vector like r = [x; y; z] is a 3-by-1 COLUMN vector.  Many variables
%   below hold one column per time sample (3-by-N matrices).
% ---------------------------------------------------------------------

clear; clc; close all;   % wipe variables, clear the command window, close old figures

%% 1. User settings -------------------------------------------------------
% These are the only values you normally need to edit.  They are stored as
% fields of a struct called "cfg" (short for configuration).
cfg.launchUTC   = '2027-01-01 00:00:00';  % TLI burn epoch (UT)
cfg.parkAlt_km  = 185;     % circular parking-orbit altitude
cfg.periAlt_km  = 100;     % target lunar periselene altitude
cfg.entryAlt_km = 60;      % target Earth perigee altitude on return
cfg.transitGuess_days = 3; % rough Earth->Moon transit time (sets orbit plane)
cfg.maxFlight_days    = 9; % longest trajectory we will integrate
cfg.ephemDays         = 14;% length of Moon ephemeris to download
cfg.saveFigures       = false;  % true -> writes PNGs next to this file

%% 2. Constants -----------------------------------------------------------
% Stored in a struct called "C".
C.muE = 398600.4418;   % Earth GM, km^3/s^2   (gravitational parameter = G*mass)
C.muM = 4902.800066;   % Moon  GM, km^3/s^2
C.Re  = 6378.137;      % Earth radius, km
C.Rm  = 1737.4;        % Moon radius, km
C.parkR     = C.Re + cfg.parkAlt_km;   % parking-orbit radius, measured from Earth's CENTER
C.periAlt   = cfg.periAlt_km;          % copy of the targets into C so helper
C.entryAlt  = cfg.entryAlt_km;         %   functions can see them
DAY = 86400;                           % seconds in a day (used to convert units)

%% 3. Moon ephemeris from Horizons ---------------------------------------
% An "ephemeris" is a table of where a body is at a series of times.
fmt = 'yyyy-MM-dd HH:mm:ss';           % date/time text format used for datetime conversions
t0  = datetime(cfg.launchUTC, 'InputFormat', fmt);   % convert launch text into a datetime object
fprintf('Downloading Moon ephemeris from JPL Horizons...\n');
% PositionFetch (your other file) queries NASA Horizons.  Arguments:
%   '301'      = Horizons ID for the Moon
%   '500@399'  = observer at the center of Earth (body 399)
%   start time, stop time (launch + ephemDays), and a '1 h' sample spacing.
% It returns a table T with (at least) columns JD, Position_km, Velocity_kms.
T = PositionFetch('301', '500@399', char(t0, fmt), ...
                  char(t0 + days(cfg.ephemDays), fmt), '1 h');

tSec = (T.JD - T.JD(1)) * DAY;          % seconds after launch epoch (JD = Julian Date in days)
% spline() fits a smooth curve through the hourly samples so we can ask for
% the Moon's position at ANY time, not only on the hour.  The ".'" transposes
% the N-by-3 table data into 3-by-N (spline wants one row per coordinate).
% The result is a "piecewise polynomial" that we evaluate later with ppval().
moon.pos = spline(tSec, T.Position_km.');   % 3-by-N data -> piecewise poly
moon.vel = spline(tSec, T.Velocity_kms.');
% ppval(moon.pos, 0) = Moon position at t = 0; norm() gives its length (distance).
fprintf('  %d samples, Moon distance at launch: %.0f km\n', ...
        numel(tSec), norm(ppval(moon.pos, 0)));

%% 4. Orbit-plane frame ---------------------------------------------------
% The transfer orbit lies (approximately) in the plane containing Earth, the
% Moon's position at arrival, and the Moon's direction of motion.
ta = cfg.transitGuess_days * DAY;       % guessed arrival time at the Moon, in seconds
fr = planeFrame(moon, ta);              % build the 2-D orbit-plane axes (see local function)
fprintf('  TLI burn-point search centered at %.1f deg in parking orbit\n', ...
        wrapTo2Pi_(fr.phi0)*180/pi);    % angle wrapped to 0..2*pi then converted to degrees

%% 5. Coarse grid search (burn angle x burn size) -------------------------
% Strategy: we don't know a good burn angle or burn size, so we try many
% combinations ("grid"), fly each one for a few days, and record how close
% it got to the Moon.  The best few become starting guesses for section 6.
fprintf('Grid search for candidate trajectories...\n');
phiGrid = fr.phi0 + (-45:3:45)*pi/180;  % burn angles: center +/- 45 deg in 3-deg steps (radians)
dvGrid  = 3.06:0.01:3.24;                 % km/s added to circular speed
cand = zeros(numel(phiGrid) * numel(dvGrid), 3);   % [miss, phi, dv]  (preallocated results table)
n = 0;                                   % row counter for cand
for i = 1:numel(phiGrid)                 % loop over burn angles
    for j = 1:numel(dvGrid)              % loop over burn sizes
        % tliState builds the starting position/velocity right after the burn;
        % flyTo numerically integrates the motion for up to 5 days
        % (loose tolerance 1e-7 and 600 s max step, since this is only a rough screen).
        sol = flyTo(tliState(phiGrid(i), dvGrid(j), fr, C), ...
                    5 * DAY, 1e-7, 600, moon, C);
        RM  = ppval(moon.pos, sol.x);    % Moon position at each integrator time step
        % Distance spacecraft<->Moon at each step; keep the smallest ("miss distance").
        % sol.y(1:3,:) = spacecraft x,y,z at every step.
        miss = min(sqrt(sum((sol.y(1:3, :) - RM).^2, 1)));
        n = n + 1;
        cand(n, :) = [miss, phiGrid(i), dvGrid(j)];   % store this trial's result
    end
end
cand = sortrows(cand, 1);                % sort so the smallest miss distance is first
fprintf('  best raw miss distance: %.0f km\n', cand(1, 1));

%% 6. Refine with Newton iteration ---------------------------------------
% Newton's method repeatedly adjusts the unknowns until the errors reach ~0.
% Unknowns x = [burn angle (rad), dv (km/s)].
% Residuals  = [periselene radius error; return-perigee radius error] (km).
% Two unknowns, two errors, so we can (usually) drive both errors to zero.
tEnd = cfg.maxFlight_days * DAY;         % maximum flight time to integrate
% "fun" is a function handle: give it x, it flies the trajectory and returns
% the two errors.  The @(x) syntax creates an anonymous (inline) function.
fun  = @(x) residual(x, fr, moon, C, tEnd);
found = false;                           % flag: did any starting guess converge?
for k = 1:min(12, size(cand, 1))         % try the 12 best candidates, in order
    fprintf('  Newton from candidate %d (miss %.0f km)... ', k, cand(k, 1));
    % newton2 arguments:
    %   fun                       : residual function to zero out
    %   cand(k,2:3).'             : starting guess [phi; dv] (as a column)
    %   [1e-6; 1e-8]              : finite-difference step sizes for each unknown
    %   [3*pi/180; 0.02]          : largest allowed change per iteration (3 deg, 20 m/s)
    %   1e-2                      : convergence tolerance (km); errors must be < 10 m
    % Outputs: x = solution, ok = converged?, it = iterations used.
    [x, ok, it] = newton2(fun, cand(k, 2:3).', [1e-6; 1e-8], ...
                          [3*pi/180; 0.02], 1e-2);
    if ok
        fprintf('converged in %d iterations.\n', it);
        found = true;
        break                            % stop at the first success
    else
        fprintf('no.\n');
    end
end
if ~found
    % error() halts the script with a message.
    error(['No free-return solution found for this date. Try a different ' ...
           'launchUTC, or widen the grid in section 5.']);
end

%% 7. Final high-accuracy trajectory -------------------------------------
% Re-fly the solved burn, this time with very tight tolerance (1e-10) and a
% smaller max step (1800 s) for a smooth, accurate result.
y0  = tliState(x(1), x(2), fr, C);
sol = flyTo(y0, tEnd, 1e-10, 1800, moon, C);
% encounterMetrics finds: rpm/tpm = Moon closest-approach distance/time,
%                         rpe/tpe = Earth closest-approach distance/time (return).
[rpm, tpm, rpe, tpe] = encounterMetrics(sol, moon);

% Build the list of times at which we want output points:
%   - 6000 evenly spaced points from launch to return perigee, plus
%   - a dense set (every 20 s, +/- 2 hours) around periselene for detail.
tt  = [linspace(0, tpe, 6000), tpm + (-7200:20:7200)];   % extra detail at flyby
tt  = unique(tt(tt >= 0 & tt <= tpe));            % TLI -> return perigee  (unique sorts and removes duplicates)
Y   = deval(sol, tt);        % evaluate the integrator's solution at those times (6-by-N: pos & vel)
R   = Y(1:3, :);             % spacecraft position, 3-by-N
RM  = ppval(moon.pos, tt);   % Moon position at the same times
VM  = ppval(moon.vel, tt);   % Moon velocity at the same times

% Rotating frame: x = Earth->Moon, z = Moon orbit normal, y completes set.
% In this frame the Moon sits still on the x-axis, which makes the
% "figure 8" shape easy to see.  We build three unit vectors (xh, yh, zh)
% for every time step.  The "./" divides each column by its own length.
xh = RM ./ sqrt(sum(RM.^2, 1));                      % unit vector Earth -> Moon
zh = cross(RM, VM, 1);  zh = zh ./ sqrt(sum(zh.^2, 1));   % unit normal to Moon's orbit (position x velocity)
yh = cross(zh, xh, 1);                               % completes the right-handed set
% proj(A,B) = dot product of each column of A with the matching column of B.
% Dotting a position with a unit axis gives its coordinate along that axis.
proj = @(A, B) sum(A .* B, 1);
xr = proj(R, xh);  yr = proj(R, yh);                 % Earth-centered, rotating
Rrel = R - RM;                                       % Moon-centered (spacecraft minus Moon)
mx = proj(Rrel, xh);  my = proj(Rrel, yh);           % Moon-centered coords in the rotating axes
dE = sqrt(sum(R.^2, 1));                             % Earth distance
dM = sqrt(sum(Rrel.^2, 1));                          % Moon distance
tD = tt / DAY;                                       % times converted to days (for plotting)

[~, kpm] = min(abs(tt - tpm));   % index of the sample closest to periselene (~ discards the min value itself)
farSide  = mx(kpm) > 0;          % if x>0 relative to Moon, we passed BEHIND it (far side)
vcirc = sqrt(C.muE / C.parkR);   % circular orbital speed at the parking radius

% Print a summary of the solution to the Command Window.
fprintf('\n================ FREE-RETURN SOLUTION ================\n');
fprintf('TLI burn at   : %s UT  (%.1f deg around parking orbit)\n', ...
        char(t0, fmt), wrapTo2Pi_(x(1))*180/pi);
fprintf('TLI delta-v   : %.1f m/s  (parking speed %.3f km/s)\n', ...
        1000 * x(2), vcirc);                         % x(2) is km/s; *1000 -> m/s
fprintf('Periselene    : %s UT, altitude %.1f km, %s of Moon\n', ...
        char(t0 + seconds(tpm), 'yyyy-MM-dd HH:mm'), rpm - C.Rm, ...   % distance from center minus radius = altitude
        ternary_(farSide, 'far side', 'near side'));
fprintf('Return perigee: %s UT, altitude %.1f km\n', ...
        char(t0 + seconds(tpe), 'yyyy-MM-dd HH:mm'), rpe - C.Re);
fprintf('Total flight  : %.2f days\n', tpe / DAY);
fprintf('======================================================\n');

%% 8. Figures -------------------------------------------------------------
pos = [80 80 1000 720];   % figure window [left bottom width height] in pixels
% circ(r) returns the x and y coordinates of a circle of radius r (361 points).
% "deal" lets one anonymous function hand back two outputs.
circ = @(r) deal(r * cos(linspace(0, 2*pi, 361)), r * sin(linspace(0, 2*pi, 361)));
% lbl(axes, text) sets a bold title on an axes object.
lbl = @(a, s) set(get(a, 'Title'), 'String', s, 'FontWeight', 'bold');

% ---- Figure 1: whole trip in the Earth-Moon rotating frame --------------
f1 = figure('Name', 'Trajectory (rotating frame)', 'Position', pos);
ax = axes(f1); hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');   % hold on = keep adding plots to the same axes
% patch() with 'interp' edge color draws a line whose color changes along its
% length (here by time).  The trailing "nan" ends the line cleanly.
% Divide by 1e3 to plot in thousands of km.
patch(ax, [xr nan]/1e3, [yr nan]/1e3, [tD nan], ...
      'EdgeColor', 'interp', 'FaceColor', 'none', 'LineWidth', 2.2);
colormap(ax, parula); cb = colorbar(ax); cb.Label.String = 'Days after TLI';
moonX = norm(ppval(moon.pos, tpm)) / 1e3;         % Moon's distance from Earth at flyby (this is its x location in the rotating frame)
[cx, cy] = circ(66000/1e3);                       % Moon sphere of influence (region where Moon's gravity dominates)
plot(ax, moonX + cx, cy, ':', 'Color', [.5 .5 .5]);   % dotted gray circle centered on the Moon
text(ax, moonX, 66, 'Moon SOI (~66,000 km)', 'HorizontalAlignment', 'center', ...
     'Color', [.4 .4 .4]);
plot(ax, 0, 0, 'o', 'MarkerSize', 16, 'MarkerFaceColor', [.15 .4 .9], ...   % Earth at the origin (blue dot)
     'MarkerEdgeColor', 'k');
plot(ax, moonX, 0, 'o', 'MarkerSize', 9, 'MarkerFaceColor', [.6 .6 .6], ... % Moon (gray dot)
     'MarkerEdgeColor', 'k');
text(ax, 0, -14, 'Earth', 'HorizontalAlignment', 'center');
text(ax, moonX, -14, 'Moon', 'HorizontalAlignment', 'center');
for d = 1:floor(tD(end))                          % daily tick marks
    [~, q] = min(abs(tD - d));                    % index of the sample nearest to day d
    plot(ax, xr(q)/1e3, yr(q)/1e3, 'k.', 'MarkerSize', 16);
    text(ax, xr(q)/1e3 + 4, yr(q)/1e3 + 6, sprintf('day %d', d), 'FontSize', 9);
end
axis(ax, 'equal'); xlabel(ax, 'x  (thousand km, toward Moon)');   % 'equal' = same scale on both axes so shapes aren't distorted
ylabel(ax, 'y  (thousand km)');
lbl(ax, sprintf('Free-return trajectory, Earth-Moon rotating frame  (bodies not to scale)'));

% ---- Figure 2: zoom on the Moon (Moon-centered, to scale) ---------------
f2 = figure('Name', 'Lunar flyby zoom', 'Position', pos);
ax = axes(f2); hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');
w  = dM < 25000;                                   % window around the Moon (logical mask: true where within 25,000 km)
hh = (tt(w) - tpm) / 3600;                         % hours from periselene
patch(ax, [mx(w) nan], [my(w) nan], [hh nan], ...  % path colored by hours from closest approach
      'EdgeColor', 'interp', 'FaceColor', 'none', 'LineWidth', 2.2);
colormap(ax, parula); cb = colorbar(ax); cb.Label.String = 'Hours from periselene';
[cx, cy] = circ(C.Rm);
fill(ax, cx, cy, [.7 .7 .7], 'EdgeColor', 'k');    % gray filled disk = the Moon, true size
[cx, cy] = circ(C.Rm + C.periAlt);
plot(ax, cx, cy, '--', 'Color', [.4 .4 .4]);       % dashed circle at the target periselene radius
plot(ax, mx(kpm), my(kpm), 'rp', 'MarkerSize', 14, 'MarkerFaceColor', 'r');   % red star at closest approach
text(ax, mx(kpm) + 800, my(kpm) + 1200, ...
     sprintf('periselene\n%.0f km altitude', rpm - C.Rm), 'Color', 'r');
for hr = -6:1:6                                    % hourly ticks
    [~, q] = min(abs(tt - (tpm + hr*3600)));       % sample nearest to "hr" hours from periselene
    if dM(q) < 25000                               % only label ticks inside the zoom window
        plot(ax, mx(q), my(q), 'k.', 'MarkerSize', 14);
        text(ax, mx(q) + 500, my(q), sprintf('%+d h', hr), 'FontSize', 9);   % %+d prints a sign (+/-)
    end
end
% quiver draws an arrow: start (-6000,0), direction (-4000,0), no auto-scaling (0).
quiver(ax, -6000, 0, -4000, 0, 0, 'k', 'LineWidth', 1.5, 'MaxHeadSize', 2);
text(ax, -6000, -1200, 'toward Earth', 'HorizontalAlignment', 'center');
axis(ax, 'equal'); xlabel(ax, 'x  (km, Earth->Moon direction)');
ylabel(ax, 'y  (km)');
lbl(ax, 'Lunar flyby, Moon-centered (Moon drawn to scale)');

% ---- Figure 3: Earth departure and return, inertial orbit plane ---------
f3 = figure('Name', 'Near-Earth legs', 'Position', pos);
% Project positions onto the orbit-plane axes e1, e2 (fixed, non-rotating).
% repmat copies the single axis vector so it has one column per time sample.
px = proj(R, repmat(fr.e1, 1, size(R, 2)));
py = proj(R, repmat(fr.e2, 1, size(R, 2)));
legs = {tt <= tpm, tt > tpm};                      % masks: outbound leg (before flyby) and return leg (after)
ttl  = {'Departure: parking orbit and TLI burn', 'Return: entry perigee'};
for s = 1:2                                        % s = 1: departure panel, s = 2: return panel
    ax = subplot(1, 2, s); hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');   % side-by-side panels
    m = legs{s} & dE < 30000;                      % this leg AND within 30,000 km of Earth
    plot(ax, px(m)/1e3, py(m)/1e3, 'LineWidth', 2.2);
    [cx, cy] = circ(C.Re);
    fill(ax, cx/1e3, cy/1e3, [.45 .65 1], 'EdgeColor', 'k');   % blue disk = Earth
    if s == 1
        [cx, cy] = circ(C.parkR);
        plot(ax, cx/1e3, cy/1e3, '--k');           % dashed parking orbit
        plot(ax, px(1)/1e3, py(1)/1e3, 'rp', 'MarkerSize', 14, ...   % first sample = burn location
             'MarkerFaceColor', 'r');
        text(ax, px(1)/1e3, py(1)/1e3 + 2, 'TLI burn', 'Color', 'r', ...
             'HorizontalAlignment', 'center');
    else
        plot(ax, px(end)/1e3, py(end)/1e3, 'rp', 'MarkerSize', 14, ...   % last sample = return perigee
             'MarkerFaceColor', 'r');
        text(ax, px(end)/1e3, py(end)/1e3 + 2, ...
             sprintf('perigee %.0f km alt.', rpe - C.Re), 'Color', 'r', ...
             'HorizontalAlignment', 'center');
    end
    axis(ax, 'equal'); xlabel(ax, 'thousand km'); ylabel(ax, 'thousand km');
    lbl(ax, ttl{s});
end

% ---- Figure 4: distance histories ---------------------------------------
f4 = figure('Name', 'Distances', 'Position', pos);
ax = subplot(2, 1, 1); hold(ax, 'on'); grid(ax, 'on');   % top panel: distance from Earth
plot(ax, tD, dE/1e3, 'LineWidth', 1.8);
xline(ax, tpm/DAY, '--r', 'periselene');           % vertical dashed line at flyby time
ylabel(ax, 'Distance from Earth (thousand km)');
lbl(ax, 'Distance from Earth');
ax = subplot(2, 1, 2); hold(ax, 'on'); grid(ax, 'on');   % bottom panel: distance from Moon
semilogy(ax, tD, dM, 'LineWidth', 1.8);            % log-scale y so both far and close distances are visible
set(ax, 'YScale', 'log');
yline(ax, C.Rm, ':k', 'lunar surface');            % horizontal line at the Moon's radius
xline(ax, tpm/DAY, '--r', sprintf('%.0f km altitude', rpm - C.Rm));
xlabel(ax, 'Days after TLI'); ylabel(ax, 'Distance from Moon (km)');
lbl(ax, 'Distance from Moon');

if cfg.saveFigures
    here = fileparts(mfilename('fullpath'));       % folder containing this script
    saveas(f1, fullfile(here, 'flyby_1_rotating.png'));    % fullfile builds a path with the right slashes
    saveas(f2, fullfile(here, 'flyby_2_moon_zoom.png'));
    saveas(f3, fullfile(here, 'flyby_3_earth_legs.png'));
    saveas(f4, fullfile(here, 'flyby_4_distances.png'));
end

%% ======================= local functions =================================
% Helper functions used above.  Each starts with "function" and ends with
% "end".  Variables inside a function are private to it; it only sees what
% is passed in as arguments.

function fr = planeFrame(moon, ta)
% Orbit-plane basis (e1, e2, nHat) and the burn-angle search center phi0.
% The spacecraft's path is (nearly) flat, so we describe it with a 2-D
% coordinate system inside that plane:
%   e1, e2 = two perpendicular unit vectors lying IN the plane
%   nHat   = unit vector perpendicular to (sticking out of) the plane
rMa = ppval(moon.pos, ta);  vMa = ppval(moon.vel, ta);   % Moon position & velocity at the guessed arrival time
nHat = cross(rMa, vMa);  nHat = nHat / norm(nHat);       % plane normal = position x velocity, scaled to length 1
rM0  = ppval(moon.pos, 0);                               % Moon position at launch
% Remove the part of rM0 that points out of the plane, leaving the part in the
% plane, then normalize.  (dot(a,b) projects one vector onto another.)
e1 = rM0 - nHat * dot(rM0, nHat);  e1 = e1 / norm(e1);   % toward Moon at TLI
e2 = cross(nHat, e1);                                    % 90 degrees from e1, within the plane
thA = atan2(dot(rMa, e2), dot(rMa, e1));  % Moon's in-plane angle at arrival (atan2 gives the angle of a point from its two coordinates)
fr.nHat = nHat(:);  fr.e1 = e1(:);  fr.e2 = e2(:);       % (:) forces each to be a column vector
fr.phi0 = thA + pi;      % burn roughly opposite the arrival point (pi radians = 180 deg)
end

function y0 = tliState(phi, dv, fr, C)
% Post-burn state: on the parking circle at angle phi, speed = circular + dv.
% Returns y0 = [x; y; z; vx; vy; vz], the standard "state vector" (6-by-1).
vc = sqrt(C.muE / C.parkR);                              % circular orbit speed at parking radius
% Position: a point on the circle at angle phi, written using the in-plane axes.
r = C.parkR * (cos(phi) * fr.e1 + sin(phi) * fr.e2);
% Velocity: perpendicular to the position (tangent to the circle), with
% magnitude = circular speed + burn dv.  (-sin, cos) is the tangent direction.
v = (vc + dv) * (-sin(phi) * fr.e1 + cos(phi) * fr.e2);
y0 = [r; v];                                             % stack position on top of velocity
end

function dy = eom(t, y, moon, C)
% Earth + Moon point-mass gravity in an Earth-centered frame.
% "eom" = equations of motion.  The ODE solver calls this thousands of times.
% Given time t and state y = [position; velocity], it returns dy = the time
% derivative of y = [velocity; acceleration].
r  = y(1:3);                         % spacecraft position (relative to Earth)
rm = ppval(moon.pos, t);             % Moon position at time t
d  = rm - r;                         % vector from spacecraft to Moon
% Acceleration = Earth's pull (toward Earth's center)
%              + Moon's pull on the spacecraft
%              - Moon's pull on Earth itself (the "indirect term").
% The last term is needed because our frame is centered on Earth, and Earth
% is itself accelerated by the Moon.
a  = -C.muE * r / norm(r)^3 + C.muM * (d / norm(d)^3 - rm / norm(rm)^3);
dy = [y(4:6); a];                    % d(position)/dt = velocity, d(velocity)/dt = a
end

function [val, term, dirn] = stopEvents(~, y, t, moon, C)
% Stop if we hit Earth, hit the Moon, or fly away.
% ODE "event" function: the solver watches each entry of "val" and acts when
% it crosses zero.  (The first input is unused, hence the ~.)
r  = y(1:3);
val  = [norm(r) - C.Re;                              % zero when we reach Earth's surface
        norm(r - ppval(moon.pos, t)) - C.Rm;         % zero when we reach the Moon's surface
        norm(r) - 5e5];                              % zero when we get 500,000 km from Earth
term = [1; 1; 1];                                    % 1 = terminate integration at that event
dirn = [-1; -1; 1];                                  % only trigger when decreasing (-1) or increasing (+1)
end

function sol = flyTo(y0, tEnd, tol, maxStep, moon, C)
% Numerically integrate the trajectory from t=0 to tEnd.
%   y0      : starting state
%   tol     : relative accuracy
%   maxStep : largest time step the solver may take (seconds)
opts = odeset('RelTol', tol, ...                     % odeset bundles solver options
              'AbsTol', [1e-6; 1e-6; 1e-6; 1e-9; 1e-9; 1e-9], ...   % absolute error limits (km for position, km/s for velocity)
              'MaxStep', maxStep, ...
              'Events', @(t, y) stopEvents([], y, t, moon, C));    % wrap stopEvents in the (t,y) form ODE solvers expect
% ode113 is a variable-order solver well suited to smooth, high-accuracy
% orbit problems.  The output "sol" is a struct holding times (sol.x) and
% states (sol.y), and can be evaluated anywhere with deval().
sol = ode113(@(t, y) eom(t, y, moon, C), [0 tEnd], y0, opts);
end

function [rpm, tpm, rpe, tpe] = encounterMetrics(sol, moon)
% Closest approach to the Moon, then closest approach to Earth afterwards.
% Outputs: rpm = periselene distance from Moon center (km), tpm = its time (s)
%          rpe = return perigee distance from Earth center (km), tpe = its time (s)
t = sol.x;  R = sol.y(1:3, :);                       % solver time steps and positions
% Distance to the Moon at each time step (find the smallest).
dm = sqrt(sum((R - ppval(moon.pos, t)).^2, 1));
[~, i] = min(dm);                                    % index of the closest sample
% The solver's time steps are coarse, so refine the minimum: fd(s) gives the
% exact distance to the Moon at time s, and fminbnd searches for its minimum
% between the samples on either side of i.  (max/min keep the index in range.)
fd = @(s) norm(deval(sol, s, 1:3) - ppval(moon.pos, s));
[tpm, rpm] = fminbnd(fd, t(max(i-1, 1)), t(min(i+1, numel(t))), ...
                     optimset('TolX', 1e-3));        % TolX = time tolerance (1 ms)
re   = sqrt(sum(R.^2, 1));                           % distance from Earth at each time step
idx  = find(t > tpm + 0.5 * 86400);                  % samples more than half a day AFTER the flyby
if numel(idx) < 3                      % never made it past the Moon
    rpe = 1e6;  tpe = t(end);  return                % give a huge "bad" answer so the solver rejects this trajectory
end
[~, k] = min(re(idx));  j = idx(k);                  % closest-to-Earth sample after the flyby
fe = @(s) norm(deval(sol, s, 1:3));                  % exact distance from Earth at time s
[tpe, rpe] = fminbnd(fe, t(max(j-1, 1)), t(min(j+1, numel(t))), ...
                     optimset('TolX', 1e-3));
end

function f = residual(x, fr, moon, C, tEnd)
% The "error vector" Newton's method tries to drive to zero.
% x = [burn angle; dv].  Fly that burn and compare the result to the targets.
sol = flyTo(tliState(x(1), x(2), fr, C), tEnd, 1e-10, 1800, moon, C);
[rpm, ~, rpe, ~] = encounterMetrics(sol, moon);
f = [rpm - (C.Rm + C.periAlt);       % periselene error: actual minus desired radius from Moon's center
     rpe - (C.Re + C.entryAlt)];     % return-perigee error: actual minus desired radius from Earth's center
end

function [x, ok, it] = newton2(fun, x, h, maxStep, tol)
% Damped Newton iteration for 2 equations in 2 unknowns, finite-difference
% Jacobian, step limiting and backtracking line search. No toolboxes.
%
% Idea: if f(x) is the error, then near a solution f(x+dx) ~ f(x) + J*dx,
% where J (the Jacobian) is the matrix of how each error changes with each
% unknown.  Setting that to zero gives dx = -J\f.  Repeat until f ~ 0.
%   h       : small step used to estimate J numerically
%   maxStep : cap on how far x may move in one iteration
%   tol     : stop when every error is smaller than this
ok = false;                                          % assume failure until proven otherwise
for it = 1:30                                        % at most 30 iterations
    f = fun(x);                                      % current errors
    if max(abs(f)) < tol, ok = true; return; end     % converged -> done
    J = zeros(2);                                    % 2-by-2 Jacobian matrix
    for k = 1:2                                      % one column per unknown
        xp = x;  xp(k) = xp(k) + h(k);               % nudge unknown k by a tiny amount
        J(:, k) = (fun(xp) - f) / h(k);              % slope = (change in errors) / (size of nudge)
    end
    % Give up if J is invalid (NaN/Inf) or nearly singular (rcond tiny = can't solve reliably).
    if any(~isfinite(J(:))) || rcond(J) < 1e-14, return; end
    dx = -J \ f;                                     % Newton step (backslash solves the linear system J*dx = -f)
    dx = max(min(dx, maxStep), -maxStep);            % clip each component to +/- maxStep
    lam = 1;  n0 = norm(f);                          % lam = fraction of the step to take; n0 = current error size
    % Backtracking line search: if the full step doesn't reduce the error,
    % try half, then a quarter, etc. (down to 1/64).
    while lam > 1/64 && norm(fun(x + lam * dx)) >= n0
        lam = lam / 2;
    end
    x = x + lam * dx;                                % take the (possibly shortened) step
end
ok = max(abs(fun(x))) < tol;                         % after 30 iterations, check one last time
end

function a = wrapTo2Pi_(a)
% Wrap an angle (radians) into the range 0 to 2*pi.
% (Same as the Mapping Toolbox's wrapTo2Pi, rewritten so no toolbox is needed.)
a = mod(a, 2*pi);
end

function s = ternary_(c, a, b)
% One-line if/else: returns a if condition c is true, otherwise b.
% (MATLAB has no built-in "c ? a : b" operator.)
if c, s = a; else, s = b; end
end

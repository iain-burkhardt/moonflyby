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

clear; clc; close all;

%% 1. User settings -------------------------------------------------------
cfg.launchUTC   = '2027-01-01 00:00:00';  % TLI burn epoch (UT)
cfg.parkAlt_km  = 185;     % circular parking-orbit altitude
cfg.periAlt_km  = 100;     % target lunar periselene altitude
cfg.entryAlt_km = 60;      % target Earth perigee altitude on return
cfg.transitGuess_days = 3; % rough Earth->Moon transit time (sets orbit plane)
cfg.maxFlight_days    = 9; % longest trajectory we will integrate
cfg.ephemDays         = 14;% length of Moon ephemeris to download
cfg.saveFigures       = false;  % true -> writes PNGs next to this file

%% 2. Constants -----------------------------------------------------------
C.muE = 398600.4418;   % Earth GM, km^3/s^2
C.muM = 4902.800066;   % Moon  GM, km^3/s^2
C.Re  = 6378.137;      % Earth radius, km
C.Rm  = 1737.4;        % Moon radius, km
C.parkR     = C.Re + cfg.parkAlt_km;
C.periAlt   = cfg.periAlt_km;
C.entryAlt  = cfg.entryAlt_km;
DAY = 86400;

%% 3. Moon ephemeris from Horizons ---------------------------------------
fmt = 'yyyy-MM-dd HH:mm:ss';
t0  = datetime(cfg.launchUTC, 'InputFormat', fmt);
fprintf('Downloading Moon ephemeris from JPL Horizons...\n');
T = PositionFetch('301', '500@399', char(t0, fmt), ...
                  char(t0 + days(cfg.ephemDays), fmt), '1 h');

tSec = (T.JD - T.JD(1)) * DAY;          % seconds after launch epoch
moon.pos = spline(tSec, T.Position_km.');   % 3-by-N data -> piecewise poly
moon.vel = spline(tSec, T.Velocity_kms.');
fprintf('  %d samples, Moon distance at launch: %.0f km\n', ...
        numel(tSec), norm(ppval(moon.pos, 0)));

%% 4. Orbit-plane frame ---------------------------------------------------
% The transfer orbit lies (approximately) in the plane containing Earth, the
% Moon's position at arrival, and the Moon's direction of motion.
ta = cfg.transitGuess_days * DAY;
fr = planeFrame(moon, ta);
fprintf('  TLI burn-point search centered at %.1f deg in parking orbit\n', ...
        wrapTo2Pi_(fr.phi0)*180/pi);

%% 5. Coarse grid search (burn angle x burn size) -------------------------
fprintf('Grid search for candidate trajectories...\n');
phiGrid = fr.phi0 + (-45:3:45)*pi/180;
dvGrid  = 3.06:0.01:3.24;                 % km/s added to circular speed
cand = zeros(numel(phiGrid) * numel(dvGrid), 3);   % [miss, phi, dv]
n = 0;
for i = 1:numel(phiGrid)
    for j = 1:numel(dvGrid)
        sol = flyTo(tliState(phiGrid(i), dvGrid(j), fr, C), ...
                    5 * DAY, 1e-7, 600, moon, C);
        RM  = ppval(moon.pos, sol.x);
        miss = min(sqrt(sum((sol.y(1:3, :) - RM).^2, 1)));
        n = n + 1;
        cand(n, :) = [miss, phiGrid(i), dvGrid(j)];
    end
end
cand = sortrows(cand, 1);
fprintf('  best raw miss distance: %.0f km\n', cand(1, 1));

%% 6. Refine with Newton iteration ---------------------------------------
% Unknowns x = [burn angle (rad), dv (km/s)].
% Residuals  = [periselene radius error; return-perigee radius error] (km).
tEnd = cfg.maxFlight_days * DAY;
fun  = @(x) residual(x, fr, moon, C, tEnd);
found = false;
for k = 1:min(12, size(cand, 1))
    fprintf('  Newton from candidate %d (miss %.0f km)... ', k, cand(k, 1));
    [x, ok, it] = newton2(fun, cand(k, 2:3).', [1e-6; 1e-8], ...
                          [3*pi/180; 0.02], 1e-2);
    if ok
        fprintf('converged in %d iterations.\n', it);
        found = true;
        break
    else
        fprintf('no.\n');
    end
end
if ~found
    error(['No free-return solution found for this date. Try a different ' ...
           'launchUTC, or widen the grid in section 5.']);
end

%% 7. Final high-accuracy trajectory -------------------------------------
y0  = tliState(x(1), x(2), fr, C);
sol = flyTo(y0, tEnd, 1e-10, 1800, moon, C);
[rpm, tpm, rpe, tpe] = encounterMetrics(sol, moon);

tt  = [linspace(0, tpe, 6000), tpm + (-7200:20:7200)];   % extra detail at flyby
tt  = unique(tt(tt >= 0 & tt <= tpe));            % TLI -> return perigee
Y   = deval(sol, tt);
R   = Y(1:3, :);
RM  = ppval(moon.pos, tt);
VM  = ppval(moon.vel, tt);

% Rotating frame: x = Earth->Moon, z = Moon orbit normal, y completes set.
xh = RM ./ sqrt(sum(RM.^2, 1));
zh = cross(RM, VM, 1);  zh = zh ./ sqrt(sum(zh.^2, 1));
yh = cross(zh, xh, 1);
proj = @(A, B) sum(A .* B, 1);
xr = proj(R, xh);  yr = proj(R, yh);                 % Earth-centered, rotating
Rrel = R - RM;                                       % Moon-centered
mx = proj(Rrel, xh);  my = proj(Rrel, yh);
dE = sqrt(sum(R.^2, 1));                             % Earth distance
dM = sqrt(sum(Rrel.^2, 1));                          % Moon distance
tD = tt / DAY;

[~, kpm] = min(abs(tt - tpm));
farSide  = mx(kpm) > 0;
vcirc = sqrt(C.muE / C.parkR);

fprintf('\n================ FREE-RETURN SOLUTION ================\n');
fprintf('TLI burn at   : %s UT  (%.1f deg around parking orbit)\n', ...
        char(t0, fmt), wrapTo2Pi_(x(1))*180/pi);
fprintf('TLI delta-v   : %.1f m/s  (parking speed %.3f km/s)\n', ...
        1000 * x(2), vcirc);
fprintf('Periselene    : %s UT, altitude %.1f km, %s of Moon\n', ...
        char(t0 + seconds(tpm), 'yyyy-MM-dd HH:mm'), rpm - C.Rm, ...
        ternary_(farSide, 'far side', 'near side'));
fprintf('Return perigee: %s UT, altitude %.1f km\n', ...
        char(t0 + seconds(tpe), 'yyyy-MM-dd HH:mm'), rpe - C.Re);
fprintf('Total flight  : %.2f days\n', tpe / DAY);
fprintf('======================================================\n');

%% 8. Figures -------------------------------------------------------------
pos = [80 80 1000 720];
circ = @(r) deal(r * cos(linspace(0, 2*pi, 361)), r * sin(linspace(0, 2*pi, 361)));
lbl = @(a, s) set(get(a, 'Title'), 'String', s, 'FontWeight', 'bold');

% ---- Figure 1: whole trip in the Earth-Moon rotating frame --------------
f1 = figure('Name', 'Trajectory (rotating frame)', 'Position', pos);
ax = axes(f1); hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');
patch(ax, [xr nan]/1e3, [yr nan]/1e3, [tD nan], ...
      'EdgeColor', 'interp', 'FaceColor', 'none', 'LineWidth', 2.2);
colormap(ax, parula); cb = colorbar(ax); cb.Label.String = 'Days after TLI';
moonX = norm(ppval(moon.pos, tpm)) / 1e3;
[cx, cy] = circ(66000/1e3);                       % Moon sphere of influence
plot(ax, moonX + cx, cy, ':', 'Color', [.5 .5 .5]);
text(ax, moonX, 66, 'Moon SOI (~66,000 km)', 'HorizontalAlignment', 'center', ...
     'Color', [.4 .4 .4]);
plot(ax, 0, 0, 'o', 'MarkerSize', 16, 'MarkerFaceColor', [.15 .4 .9], ...
     'MarkerEdgeColor', 'k');
plot(ax, moonX, 0, 'o', 'MarkerSize', 9, 'MarkerFaceColor', [.6 .6 .6], ...
     'MarkerEdgeColor', 'k');
text(ax, 0, -14, 'Earth', 'HorizontalAlignment', 'center');
text(ax, moonX, -14, 'Moon', 'HorizontalAlignment', 'center');
for d = 1:floor(tD(end))                          % daily tick marks
    [~, q] = min(abs(tD - d));
    plot(ax, xr(q)/1e3, yr(q)/1e3, 'k.', 'MarkerSize', 16);
    text(ax, xr(q)/1e3 + 4, yr(q)/1e3 + 6, sprintf('day %d', d), 'FontSize', 9);
end
axis(ax, 'equal'); xlabel(ax, 'x  (thousand km, toward Moon)');
ylabel(ax, 'y  (thousand km)');
lbl(ax, sprintf('Free-return trajectory, Earth-Moon rotating frame  (bodies not to scale)'));

% ---- Figure 2: zoom on the Moon (Moon-centered, to scale) ---------------
f2 = figure('Name', 'Lunar flyby zoom', 'Position', pos);
ax = axes(f2); hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');
w  = dM < 25000;                                   % window around the Moon
hh = (tt(w) - tpm) / 3600;                         % hours from periselene
patch(ax, [mx(w) nan], [my(w) nan], [hh nan], ...
      'EdgeColor', 'interp', 'FaceColor', 'none', 'LineWidth', 2.2);
colormap(ax, parula); cb = colorbar(ax); cb.Label.String = 'Hours from periselene';
[cx, cy] = circ(C.Rm);
fill(ax, cx, cy, [.7 .7 .7], 'EdgeColor', 'k');
[cx, cy] = circ(C.Rm + C.periAlt);
plot(ax, cx, cy, '--', 'Color', [.4 .4 .4]);
plot(ax, mx(kpm), my(kpm), 'rp', 'MarkerSize', 14, 'MarkerFaceColor', 'r');
text(ax, mx(kpm) + 800, my(kpm) + 1200, ...
     sprintf('periselene\n%.0f km altitude', rpm - C.Rm), 'Color', 'r');
for hr = -6:1:6                                    % hourly ticks
    [~, q] = min(abs(tt - (tpm + hr*3600)));
    if dM(q) < 25000
        plot(ax, mx(q), my(q), 'k.', 'MarkerSize', 14);
        text(ax, mx(q) + 500, my(q), sprintf('%+d h', hr), 'FontSize', 9);
    end
end
quiver(ax, -6000, 0, -4000, 0, 0, 'k', 'LineWidth', 1.5, 'MaxHeadSize', 2);
text(ax, -6000, -1200, 'toward Earth', 'HorizontalAlignment', 'center');
axis(ax, 'equal'); xlabel(ax, 'x  (km, Earth->Moon direction)');
ylabel(ax, 'y  (km)');
lbl(ax, 'Lunar flyby, Moon-centered (Moon drawn to scale)');

% ---- Figure 3: Earth departure and return, inertial orbit plane ---------
f3 = figure('Name', 'Near-Earth legs', 'Position', pos);
px = proj(R, repmat(fr.e1, 1, size(R, 2)));
py = proj(R, repmat(fr.e2, 1, size(R, 2)));
legs = {tt <= tpm, tt > tpm};
ttl  = {'Departure: parking orbit and TLI burn', 'Return: entry perigee'};
for s = 1:2
    ax = subplot(1, 2, s); hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');
    m = legs{s} & dE < 30000;
    plot(ax, px(m)/1e3, py(m)/1e3, 'LineWidth', 2.2);
    [cx, cy] = circ(C.Re);
    fill(ax, cx/1e3, cy/1e3, [.45 .65 1], 'EdgeColor', 'k');
    if s == 1
        [cx, cy] = circ(C.parkR);
        plot(ax, cx/1e3, cy/1e3, '--k');
        plot(ax, px(1)/1e3, py(1)/1e3, 'rp', 'MarkerSize', 14, ...
             'MarkerFaceColor', 'r');
        text(ax, px(1)/1e3, py(1)/1e3 + 2, 'TLI burn', 'Color', 'r', ...
             'HorizontalAlignment', 'center');
    else
        plot(ax, px(end)/1e3, py(end)/1e3, 'rp', 'MarkerSize', 14, ...
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
ax = subplot(2, 1, 1); hold(ax, 'on'); grid(ax, 'on');
plot(ax, tD, dE/1e3, 'LineWidth', 1.8);
xline(ax, tpm/DAY, '--r', 'periselene');
ylabel(ax, 'Distance from Earth (thousand km)');
lbl(ax, 'Distance from Earth');
ax = subplot(2, 1, 2); hold(ax, 'on'); grid(ax, 'on');
semilogy(ax, tD, dM, 'LineWidth', 1.8);
set(ax, 'YScale', 'log');
yline(ax, C.Rm, ':k', 'lunar surface');
xline(ax, tpm/DAY, '--r', sprintf('%.0f km altitude', rpm - C.Rm));
xlabel(ax, 'Days after TLI'); ylabel(ax, 'Distance from Moon (km)');
lbl(ax, 'Distance from Moon');

if cfg.saveFigures
    here = fileparts(mfilename('fullpath'));
    saveas(f1, fullfile(here, 'flyby_1_rotating.png'));
    saveas(f2, fullfile(here, 'flyby_2_moon_zoom.png'));
    saveas(f3, fullfile(here, 'flyby_3_earth_legs.png'));
    saveas(f4, fullfile(here, 'flyby_4_distances.png'));
end

%% ======================= local functions =================================

function fr = planeFrame(moon, ta)
% Orbit-plane basis (e1, e2, nHat) and the burn-angle search center phi0.
rMa = ppval(moon.pos, ta);  vMa = ppval(moon.vel, ta);
nHat = cross(rMa, vMa);  nHat = nHat / norm(nHat);
rM0  = ppval(moon.pos, 0);
e1 = rM0 - nHat * dot(rM0, nHat);  e1 = e1 / norm(e1);   % toward Moon at TLI
e2 = cross(nHat, e1);
thA = atan2(dot(rMa, e2), dot(rMa, e1));  % Moon's in-plane angle at arrival
fr.nHat = nHat(:);  fr.e1 = e1(:);  fr.e2 = e2(:);
fr.phi0 = thA + pi;      % burn roughly opposite the arrival point
end

function y0 = tliState(phi, dv, fr, C)
% Post-burn state: on the parking circle at angle phi, speed = circular + dv.
vc = sqrt(C.muE / C.parkR);
r = C.parkR * (cos(phi) * fr.e1 + sin(phi) * fr.e2);
v = (vc + dv) * (-sin(phi) * fr.e1 + cos(phi) * fr.e2);
y0 = [r; v];
end

function dy = eom(t, y, moon, C)
% Earth + Moon point-mass gravity in an Earth-centered frame.
r  = y(1:3);
rm = ppval(moon.pos, t);
d  = rm - r;
a  = -C.muE * r / norm(r)^3 + C.muM * (d / norm(d)^3 - rm / norm(rm)^3);
dy = [y(4:6); a];
end

function [val, term, dirn] = stopEvents(~, y, t, moon, C)
% Stop if we hit Earth, hit the Moon, or fly away.
r  = y(1:3);
val  = [norm(r) - C.Re; norm(r - ppval(moon.pos, t)) - C.Rm; norm(r) - 5e5];
term = [1; 1; 1];
dirn = [-1; -1; 1];
end

function sol = flyTo(y0, tEnd, tol, maxStep, moon, C)
opts = odeset('RelTol', tol, ...
              'AbsTol', [1e-6; 1e-6; 1e-6; 1e-9; 1e-9; 1e-9], ...
              'MaxStep', maxStep, ...
              'Events', @(t, y) stopEvents([], y, t, moon, C));
sol = ode113(@(t, y) eom(t, y, moon, C), [0 tEnd], y0, opts);
end

function [rpm, tpm, rpe, tpe] = encounterMetrics(sol, moon)
% Closest approach to the Moon, then closest approach to Earth afterwards.
t = sol.x;  R = sol.y(1:3, :);
dm = sqrt(sum((R - ppval(moon.pos, t)).^2, 1));
[~, i] = min(dm);
fd = @(s) norm(deval(sol, s, 1:3) - ppval(moon.pos, s));
[tpm, rpm] = fminbnd(fd, t(max(i-1, 1)), t(min(i+1, numel(t))), ...
                     optimset('TolX', 1e-3));
re   = sqrt(sum(R.^2, 1));
idx  = find(t > tpm + 0.5 * 86400);
if numel(idx) < 3                      % never made it past the Moon
    rpe = 1e6;  tpe = t(end);  return
end
[~, k] = min(re(idx));  j = idx(k);
fe = @(s) norm(deval(sol, s, 1:3));
[tpe, rpe] = fminbnd(fe, t(max(j-1, 1)), t(min(j+1, numel(t))), ...
                     optimset('TolX', 1e-3));
end

function f = residual(x, fr, moon, C, tEnd)
sol = flyTo(tliState(x(1), x(2), fr, C), tEnd, 1e-10, 1800, moon, C);
[rpm, ~, rpe, ~] = encounterMetrics(sol, moon);
f = [rpm - (C.Rm + C.periAlt); rpe - (C.Re + C.entryAlt)];
end

function [x, ok, it] = newton2(fun, x, h, maxStep, tol)
% Damped Newton iteration for 2 equations in 2 unknowns, finite-difference
% Jacobian, step limiting and backtracking line search. No toolboxes.
ok = false;
for it = 1:30
    f = fun(x);
    if max(abs(f)) < tol, ok = true; return; end
    J = zeros(2);
    for k = 1:2
        xp = x;  xp(k) = xp(k) + h(k);
        J(:, k) = (fun(xp) - f) / h(k);
    end
    if any(~isfinite(J(:))) || rcond(J) < 1e-14, return; end
    dx = -J \ f;
    dx = max(min(dx, maxStep), -maxStep);
    lam = 1;  n0 = norm(f);
    while lam > 1/64 && norm(fun(x + lam * dx)) >= n0
        lam = lam / 2;
    end
    x = x + lam * dx;
end
ok = max(abs(fun(x))) < tol;
end

function a = wrapTo2Pi_(a)
a = mod(a, 2*pi);
end

function s = ternary_(c, a, b)
if c, s = a; else, s = b; end
end

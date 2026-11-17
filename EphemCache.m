function T = EphemCache(body, center, tStart, tStop, step, forceRefresh)
% EPHEMCACHE  Cached wrapper around PositionFetch (NASA Horizons).
%
% Works exactly like PositionFetch, but saves every result to a .mat file
% in a "cache" folder next to this file. The next time the same data is
% requested, it is loaded from disk instead of calling the API.
%
% It also reuses a cached file that COVERS the requested range at the same
% step size (e.g. a cached full year can serve a one-week request), so you
% can fetch a wide window once and then run many launch dates offline.
%
% INPUTS:
%   body         - Horizons target ID      (e.g. '301' = Moon)
%   center       - Horizons center         (e.g. '500@399' = Earth center)
%   tStart       - 'yyyy-MM-dd HH:mm:ss'
%   tStop        - 'yyyy-MM-dd HH:mm:ss'
%   step         - Horizons step string    (e.g. '1 h', '10 m', '1 d')
%   forceRefresh - (optional) true = ignore cache and re-download
%
% OUTPUT:
%   T - same table PositionFetch returns: JD, Position_km, Velocity_kms
%
% EXAMPLE:
%   MoonEarth = EphemCache('301', '500@399', ...
%       '2027-01-01 00:00:00', '2027-01-15 00:00:00', '1 h');

if nargin < 6, forceRefresh = false; end

%% 1. Cache folder setup
% mfilename('fullpath') is the location of THIS file, so the cache always
% lands in the project folder no matter where MATLAB's current folder is.
cacheDir = fullfile(fileparts(mfilename('fullpath')), 'cache');
if ~exist(cacheDir, 'dir')
    mkdir(cacheDir);
end

% Requested time range as Julian dates (same time system Horizons returns)
fmt = 'yyyy-MM-dd HH:mm:ss';
jdStart = juliandate(datetime(tStart, 'InputFormat', fmt));
jdStop  = juliandate(datetime(tStop,  'InputFormat', fmt));

if jdStop <= jdStart
    error('EphemCache: tStop must be after tStart.');
end

% Tolerance for comparing times. ~3 minutes: covers floating-point rounding
% AND the ~69 s offset if Horizons labels rows in TDB instead of UT, while
% staying far smaller than any step size you'd use.
tol = 0.002;   % days

%% 2. Look for a cached file that covers this request
if ~forceRefresh
    files = dir(fullfile(cacheDir, 'ephem_*.mat'));

    for k = 1:numel(files)
        f = fullfile(cacheDir, files(k).name);

        % Load only the small metadata struct first (fast)
        s = load(f, 'meta');
        if ~isfield(s, 'meta'), continue; end
        m = s.meta;

        sameQuery = strcmp(m.body, body) && ...
                    strcmp(m.center, center) && ...
                    strcmp(m.step, step);

        covers = (m.jdStart <= jdStart + tol) && ...
                 (m.jdStop  >= jdStop  - tol);

        if sameQuery && covers
            s = load(f, 'T');
            T = s.T;

            % Trim to the requested window
            keep = (T.JD >= jdStart - tol) & (T.JD <= jdStop + tol);
            T = T(keep, :);

            fprintf('EphemCache: loaded %s [%s] from cache (%d rows)\n', ...
                body, center, height(T));
            return;
        end
    end
end

%% 3. Not cached -> download from Horizons and save
fprintf('EphemCache: fetching %s [%s] from Horizons...\n', body, center);

try
    T = PositionFetch(body, center, tStart, tStop, step);
catch err
    error(['EphemCache: Horizons request failed and no cached data ' ...
           'covers this range.\nOriginal error: %s'], err.message);
end

% Metadata stored alongside the table so later calls can check coverage
meta.body    = body;
meta.center  = center;
meta.step    = step;
meta.tStart  = tStart;
meta.tStop   = tStop;
meta.jdStart = jdStart;
meta.jdStop  = jdStop;
meta.fetched = char(datetime('now'));

% Build a file name that is safe on every OS (no spaces, colons, @)
key = sprintf('ephem_%s_%s_%s_%s_%s', body, center, tStart, tStop, step);
key = regexprep(key, '[^A-Za-z0-9]', '_');
fileName = fullfile(cacheDir, [key '.mat']);

save(fileName, 'T', 'meta');
fprintf('EphemCache: saved %d rows to %s\n', height(T), fileName);

end

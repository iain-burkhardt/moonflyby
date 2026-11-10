function T = PositionFetch(body, center, tStart, tStop, step)
if nargin < 1, body   = '301';        end   
if nargin < 2, center = '500@399';    end   
if nargin < 3, tStart = '2027-01-01'; end
if nargin < 4, tStop  = '2027-01-31'; end
if nargin < 5, step   = '1 h';        end

url  = 'https://ssd.jpl.nasa.gov/api/horizons.api';
opts = weboptions('Timeout', 60);
resp = webread(url, opts, ...
    'format',     'json', ...
    'COMMAND',    ['''' body ''''], ...
    'OBJ_DATA',   '''NO''', ...
    'MAKE_EPHEM', '''YES''', ...
    'EPHEM_TYPE', '''VECTORS''', ...
    'CENTER',     ['''' center ''''], ...
    'START_TIME', ['''' tStart ''''], ...
    'STOP_TIME',  ['''' tStop ''''], ...
    'STEP_SIZE',  ['''' step ''''], ...
    'REF_PLANE',  '''ECLIPTIC''', ...
    'OUT_UNITS',  '''KM-S''', ...
    'VEC_TABLE',  '''2''', ...
    'CSV_FORMAT', '''NO''');

txt = resp.result;
if ~contains(txt, '$$SOE')
    error('Horizons returned no data:\n%s', txt);
end
blk = regexp(txt, '\$\$SOE(.*?)\$\$EOE', 'tokens', 'once');
blk = blk{1};

num = '([-+]?\d+\.?\d*(?:[Ee][-+]?\d+)?)';
jd = str2double(regexp(blk, [num '\s*=\s*A\.D\.'], 'tokens'));
x  = grabAll(blk, '(?<![A-Z])X\s*=\s*',  num);
y  = grabAll(blk, '(?<![A-Z])Y\s*=\s*',  num);
z  = grabAll(blk, '(?<![A-Z])Z\s*=\s*',  num);
vx = grabAll(blk, 'VX\s*=\s*', num);
vy = grabAll(blk, 'VY\s*=\s*', num);
vz = grabAll(blk, 'VZ\s*=\s*', num);

jd = cellfun(@(c) str2double(c{1}), regexp(blk, [num '\s*=\s*A\.D\.'], 'tokens'))';

T = table(jd, [x y z], [vx vy vz], ...
    'VariableNames', {'JD_TDB','Position_km','Velocity_kms'});
end

function v = grabAll(s, label, num)
t = regexp(s, [label num], 'tokens');
v = cellfun(@(c) str2double(c{1}), t)';
end


function [distanceKm, positionKm] = MoonDistance(dateStr, timeStr)

tStart = datetime([dateStr ' ' timeStr], ...
    'InputFormat', 'yyyy-MM-dd HH:mm');

tStop = tStart + hours(1);

T = PositionFetch('301', '500@399', ...
    datestr(tStart, 'yyyy-mm-dd HH:MM'), ...
    datestr(tStop, 'yyyy-mm-dd HH:MM'), '1 h');

positionKm = T.Position_km(1,:);

distanceKm = norm(positionKm);

fprintf('\nMoon Position: %s\n', ...
    datestr(tStart, 'dd-mmm-yyyy HH:MM'));

fprintf('Distance from Earth center: %.2f km\n', ...
    distanceKm);

end

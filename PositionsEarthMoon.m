
function T = PositionFetch(body, center, tStart, tStop, step)
% POSITIONFETCH Retrieves position and velocity data from NASA Horizons.
%
% INPUTS:
%   body   - Horizons target ID (default: '301' = Moon)
%   center - Reference center (default: '500@399' = Earth center)
%   tStart - Start date and time (default: '2027-01-01 00:00:00')
%   tStop  - End date and time (default: '2027-01-02 00:00:00')
%   step   - Time interval (default: '1 h')
%
% OUTPUT:
%   T - Table containing:
%       JD          Julian date
%       Position_km Position vector [X Y Z] in km
%       Velocity_kms Velocity vector [VX VY VZ] in km/s

%% 1. Set default inputs

if nargin < 1, body = '301'; end
if nargin < 2, center = '500@399'; end
if nargin < 3, tStart = '2027-01-01 00:00:00'; end
if nargin < 4, tStop = '2027-01-02 00:00:00'; end
if nargin < 5, step = '1 h'; end

%% 2. Configure NASA Horizons API

url = 'https://ssd.jpl.nasa.gov/api/horizons.api';

options = weboptions('Timeout', 60);

% Request vector ephemeris data
response = webread(url, options, ...
    'format', 'json', ...
    'COMMAND', ['''' body ''''], ...
    'OBJ_DATA', '''NO''', ...
    'MAKE_EPHEM', '''YES''', ...
    'EPHEM_TYPE', '''VECTORS''', ...
    'CENTER', ['''' center ''''], ...
    'START_TIME', ['''' tStart ''''], ...
    'STOP_TIME', ['''' tStop ''''], ...
    'STEP_SIZE', ['''' step ''''], ...
    'TIME_TYPE', '''UT''', ...
    'REF_SYSTEM', '''ICRF''', ...
    'REF_PLANE', '''FRAME''', ...
    'VEC_CORR', '''NONE''', ...
    'OUT_UNITS', '''KM-S''', ...
    'VEC_TABLE', '''2''', ...
    'VEC_LABELS', '''YES''', ...
    'CSV_FORMAT', '''NO''');

%% 3. Extract ephemeris text

if ~isfield(response, 'result')
    error('Horizons response does not contain a result.');
end

ephemeris = response.result;

% Locate the beginning and end of the data section
dataBlock = regexp(ephemeris, ...
    '\$\$SOE(.*?)\$\$EOE', 'tokens', 'once');

if isempty(dataBlock)
    error('No ephemeris data found in Horizons response:\n%s', ...
        ephemeris);
end

dataBlock = dataBlock{1};

%% 4. Extract numerical data

% General pattern for scientific notation and decimal numbers
numberPattern = '([-+]?\d*\.?\d+(?:[Ee][-+]?\d+)?)';

% Julian dates
jdTokens = regexp(dataBlock, ...
    [numberPattern '\s*=\s*A\.D\.'], 'tokens');

JD = cellfun(@(c) str2double(c{1}), jdTokens)';

% Position coordinates (km)
X = grabAll(dataBlock, '(?<![A-Z])X\s*=\s*', numberPattern);
Y = grabAll(dataBlock, '(?<![A-Z])Y\s*=\s*', numberPattern);
Z = grabAll(dataBlock, '(?<![A-Z])Z\s*=\s*', numberPattern);

% Velocity components (km/s)
VX = grabAll(dataBlock, 'VX\s*=\s*', numberPattern);
VY = grabAll(dataBlock, 'VY\s*=\s*', numberPattern);
VZ = grabAll(dataBlock, 'VZ\s*=\s*', numberPattern);

%% 5. Validate extracted data

n = numel(JD);

if n == 0
    error('No valid Julian dates were extracted.');
end

columnLengths = [numel(X), numel(Y), numel(Z), ...
                 numel(VX), numel(VY), numel(VZ)];

if any(columnLengths ~= n)
    error('Inconsistent ephemeris data: vector lengths do not match.');
end

%% 6. Construct output table

Position_km = [X, Y, Z];
Velocity_kms = [VX, VY, VZ];

T = table(JD, Position_km, Velocity_kms);

end


%% Helper function: Extract all values matching a label

function values = grabAll(text, label, numberPattern)

tokens = regexp(text, [label numberPattern], 'tokens');

values = cellfun(@(c) str2double(c{1}), tokens)';

end

% plot attempt


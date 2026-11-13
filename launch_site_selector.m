%% launch_site_selector.m
% =========================================================================
% PART 1: LAUNCH SITE SELECTION
% Lunar Free-Return Trajectory Project
% =========================================================================
% PURPOSE:
%   Opens a small window containing a dropdown menu of launch sites. When the
%   user picks a site, the program displays that site's latitude, longitude,
%   and altitude above sea level, both in the window and in the Command
%   Window. When the user clicks "Confirm Launch Site", the choice is stored
%   in a struct called "launchSite" so later parts of the project can use it.
%
% NOTES ON THE DATA:
%   - Latitude and longitude are in decimal degrees.
%   - Latitude is positive in the Northern Hemisphere.
%   - Longitude is NEGATIVE for West of the Prime Meridian (all US sites).
%   - Altitude is in meters above mean sea level.
%   - Values are approximate pad/site locations. Verify against your
%     course's required sources if needed.
%
% REQUIREMENTS:
%   MATLAB R2016b or newer (needed for uifigure and for local functions
%   defined at the end of a script file).
% =========================================================================

% "clear" removes all variables from the workspace so old values from a
% previous run can't interfere with this one.
clear;

% "clc" clears the Command Window text so the output is easy to read.
clc;

% "close all" closes any figure windows left over from earlier runs.
close all;

%% ------------------------------------------------------------------------
%  SECTION 1: LAUNCH SITE DATABASE
% -------------------------------------------------------------------------
% We store all the site data in one "cell array" called "sites".
% A cell array is a table-like container that can hold different data types
% (here: text AND numbers) in the same structure, which a normal numeric
% matrix cannot do.
%
% Each ROW is one launch site. Each COLUMN is one piece of information:
%     Column 1: site name (text)
%     Column 2: latitude  in degrees (positive = North)
%     Column 3: longitude in degrees (negative = West)
%     Column 4: altitude above sea level in meters
%
% The "..." at the end of a line is not used here because the braces { }
% allow the list to continue on the following lines. Each row is separated
% by a new line (a semicolon would also work).
sites = {
    'Kennedy Space Center (KSC), Florida',                    28.6084,  -80.6043,    3
    'Cape Canaveral Space Launch Complex, Florida',           28.5619,  -80.5772,    3
    'Vandenberg Space Force Base, California',                34.6321, -120.6108,  112
    'Wallops Flight Facility, Virginia',                      37.8337,  -75.4879,    3
    'Kodiak Launch Complex (Pacific Spaceport), Alaska',      57.4352, -152.3398,   12
    'SpaceX Starbase, Texas',                                 25.9972,  -97.1560,    2
    'Blue Origin Launch Site, Texas',                         31.4228, -104.7580, 1350
    'Spaceport America, New Mexico',                          32.9904, -106.9750, 1401
    'Mojave Air and Space Port, California',                  35.0594, -118.1517,  855
};

% Pull out just the first column (the names) into its own list.
% In "sites(:,1)":
%     the colon  ":"  means "all rows"
%     the number "1"  means "column 1"
% Parentheses () keep the result as a cell array, which is exactly the
% format the dropdown menu needs for its list of choices.
siteNames = sites(:,1);

%% ------------------------------------------------------------------------
%  SECTION 2: BUILD THE GRAPHICAL USER INTERFACE (GUI)
% -------------------------------------------------------------------------

% Create the main window.
% "uifigure" makes a window designed to hold modern UI components such as
% dropdowns and buttons. The extra inputs come in Name/Value pairs:
%     'Name'     -> the text shown in the window's title bar
%     'Position' -> [left bottom width height] in pixels. This means the
%                   window's lower-left corner is 200 px from the left and
%                   200 px from the bottom of the screen, and the window is
%                   520 px wide by 300 px tall.
% The handle (reference) to the window is saved in "fig" so we can add
% things to it and control it later.
fig = uifigure('Name', 'Launch Site Selection', ...
               'Position', [200 200 520 300]);

% Add a text label above the dropdown to tell the user what to do.
% The first input (fig) says which window the label belongs to.
%     'Text'       -> the words displayed
%     'Position'   -> [left bottom width height] measured INSIDE the window
%     'FontWeight' -> 'bold' makes the text heavier
uilabel(fig, ...
        'Text', 'Select a launch site:', ...
        'Position', [30 240 200 22], ...
        'FontWeight', 'bold');

% Create the dropdown menu itself.
%     'Items' -> the list of choices (our site names)
%     'Value' -> which item is selected when the window first opens.
%                siteNames{1} uses curly braces { } to pull the TEXT out of
%                the first cell (the first site, KSC).
%     'Position' -> placed just below the label, 460 px wide so that the
%                   longest site name fits.
% The handle is saved in "dd" so we can read which item is selected.
dd = uidropdown(fig, ...
                'Items', siteNames, ...
                'Value', siteNames{1}, ...
                'Position', [30 210 460 25]);

% Create a second label that will display the results (lat, lon, altitude).
% It starts out with empty text; the update function fills it in.
%     'VerticalAlignment' -> 'top' makes text start at the top of the box
%                            and grow downward, like normal writing.
%     'FontSize'          -> text size in points.
resultLabel = uilabel(fig, ...
                      'Position', [30 40 460 150], ...
                      'VerticalAlignment', 'top', ...
                      'FontSize', 14, ...
                      'Text', '');

%% ------------------------------------------------------------------------
%  SECTION 3: CONNECT THE DROPDOWN TO AN ACTION (CALLBACK)
% -------------------------------------------------------------------------
% A "callback" is a function MATLAB runs automatically when the user does
% something, in this case when they change the dropdown choice.
%
% "ValueChangedFcn" is the dropdown property that holds that function.
%
% The "@(src, ~) ..." is an ANONYMOUS FUNCTION (a small one-line function
% with no name):
%     src -> the component that triggered the event (the dropdown)
%     ~   -> the event data, which we don't need, so "~" ignores it
% It then calls our own function "updateSite" (defined at the bottom of
% this file) and hands it the dropdown, the data table, and the result label.
dd.ValueChangedFcn = @(src, ~) updateSite(src, sites, resultLabel);

% Callbacks only run when the user CHANGES something. To make the window
% show information for the first site as soon as it opens, we call the
% function once manually.
updateSite(dd, sites, resultLabel);

%% ------------------------------------------------------------------------
%  SECTION 4: CONFIRM BUTTON AND PAUSING THE SCRIPT
% -------------------------------------------------------------------------
% Create a button the user clicks when they're happy with their choice.
%     'Text'             -> the label on the button
%     'Position'         -> centered near the bottom of the window
%     'ButtonPushedFcn'  -> the callback to run when clicked. Here
%                           "uiresume(fig)" tells MATLAB to un-pause the
%                           script that is waiting on the line below.
% "~, ~" means we ignore both inputs MATLAB passes to the callback.
uibutton(fig, ...
         'Text', 'Confirm Launch Site', ...
         'Position', [175 10 170 28], ...
         'ButtonPushedFcn', @(~, ~) uiresume(fig));

% "uiwait" pauses the script right here until uiresume is called (button
% click) or the window is closed. Without this pause, the script would
% reach the end immediately and never give the user time to choose.
uiwait(fig);

% SAFETY CHECK: if the user closed the window with the X instead of clicking
% Confirm, the dropdown "dd" no longer exists and reading from it would
% cause an error. "isvalid" checks whether the window still exists.
% The "~" means NOT, so this reads: "if the window is NOT valid, stop."
% "return" ends the script cleanly.
if ~isvalid(fig)
    disp('Window closed before a launch site was confirmed.');
    return;
end

%% ------------------------------------------------------------------------
%  SECTION 5: SAVE THE CONFIRMED CHOICE FOR LATER PARTS OF THE PROJECT
% -------------------------------------------------------------------------
% Find which row of the table matches the selected name.
%     dd.Value                  -> the text of the selected dropdown item
%     strcmp(sites(:,1), ...)   -> compares every name in column 1 to the
%                                  selected text; gives true (1) for the
%                                  match and false (0) for all others
%     find(...)                 -> returns the position (row number) of the
%                                  true value
idx = find(strcmp(sites(:,1), dd.Value));

% Store the selected site's information in a STRUCT. A struct groups related
% values under one name, with named "fields" accessed using a dot. Later
% code can then simply use launchSite.lat_deg, launchSite.alt_m, etc.
% Curly braces { } pull the actual value out of the cell array.
launchSite.name     = sites{idx,1};   % site name (text)
launchSite.lat_deg  = sites{idx,2};   % latitude in degrees
launchSite.lon_deg  = sites{idx,3};   % longitude in degrees
launchSite.alt_m    = sites{idx,4};   % altitude in meters above sea level

% Print the confirmed selection to the Command Window.
% "fprintf" prints formatted text. Format codes act as placeholders:
%     %s    -> insert text
%     %.4f  -> insert a number with 4 digits after the decimal point
%     %.1f  -> insert a number with 1 digit after the decimal point
%     \n    -> start a new line
fprintf('\nConfirmed launch site: %s\n', launchSite.name);
fprintf('  Latitude : %.4f deg\n', launchSite.lat_deg);
fprintf('  Longitude: %.4f deg\n', launchSite.lon_deg);
fprintf('  Altitude : %.1f m above sea level\n', launchSite.alt_m);

%% ------------------------------------------------------------------------
%  LOCAL FUNCTION: updateSite
% -------------------------------------------------------------------------
% In a script file, local functions must be placed at the END of the file.
% This function is called every time the dropdown changes (and once at
% startup). It looks up the selected site and updates the display.
%
% INPUTS:
%     dropdown -> the dropdown menu component (so we can read its Value)
%     sites    -> the cell array of site data
%     label    -> the text label where results are displayed
function updateSite(dropdown, sites, label)

    % Find the row number of the currently selected site (same method as
    % in Section 5).
    idx = find(strcmp(sites(:,1), dropdown.Value));

    % Pull the numbers for that row into easy-to-read variable names.
    lat = sites{idx,2};   % latitude in degrees
    lon = sites{idx,3};   % longitude in degrees
    alt = sites{idx,4};   % altitude in meters

    % Build the text shown in the window using "sprintf", which works like
    % fprintf but RETURNS the text instead of printing it.
    %
    % Details:
    %   - abs(lat) and abs(lon) give positive numbers because we write the
    %     compass letter (N or W) after them instead of using a minus sign.
    %   - char(176) is the degree symbol (the ° character).
    %   - [char(176) 'N'] joins the degree symbol and the letter N into one
    %     piece of text.
    %   - "\n\n" makes a blank line; "\n" makes a normal line break.
    %   - The "..." continues the statement onto the next line.
    label.Text = sprintf(['Site: %s\n\n' ...
                          'Latitude:  %.4f%s\n' ...
                          'Longitude: %.4f%s\n' ...
                          'Altitude:  %.1f m above sea level'], ...
                          sites{idx,1}, ...
                          abs(lat), [char(176) 'N'], ...
                          abs(lon), [char(176) 'W'], ...
                          alt);

    % Also print a one-line summary to the Command Window each time the
    % selection changes. Here the longitude is shown with its sign
    % (negative = West), which is the form you'll use in calculations.
    fprintf('Selected: %s | Lat %.4f, Lon %.4f, Alt %.1f m\n', ...
            sites{idx,1}, lat, lon, alt);
end

% =====================================================================
% WHAT DOES THIS PROGRAM DO? (the super simple version)
% =====================================================================
% The Sun is a big glowing ball. The Earth goes around the Sun, and the
% Moon goes around the Earth.
%
% This little program:
%   1. Asks NASA's computers where the Earth and Moon are, once every
%      hour, for one week (January 1 to January 8, 2027).
%   2. Hands those answers to a drawing helper called PlotEarthMoon,
%      which makes the picture.
%
% (The steps are: ask NASA, then draw. That's it!)
%
% Words you might not know:
%   - "PositionFetch" : a helper machine (written in a different file)
%                       that goes and gets positions from NASA.
%   - "PlotEarthMoon" : another helper machine (also in a different
%                       file) that draws pictures from those positions.
%   - Both helpers must be saved where MATLAB can find them, or this
%     program will say "I don't know that word!"
% =====================================================================

% Erase all the old things MATLAB is remembering (variables), like
% wiping a whiteboard clean so old answers don't get mixed up with
% new ones.
clear;
% Clean the writing in the Command Window (like erasing a chalkboard).
clc;
% Close any picture windows that are still open from before.
close all;

% The day and time we want to START watching: midnight, January 1, 2027.
% It's in quote marks because it is text (words), not a number.
tStart = '2027-01-01 00:00:00';
% The day and time we want to STOP watching: midnight, January 8, 2027.
% So we watch exactly 7 days (one week).
tStop = '2027-01-08 00:00:00';
% How big a jump in time between each position: '1 h' means 1 hour.
% So we get one position for every hour of the week
% (24 hours x 7 days = 168 positions, plus the one at the very end).
step = '1 h';

% Ask NASA: "Where is the Earth compared to the Sun?"
% The numbers are secret codes NASA uses:
%   '399'   = Earth
%   '500@10' = "measured from the center of the Sun" (10 = the Sun)
% We hand the helper the start time, stop time, and step size from
% above. The answer comes back and is saved in a box named "EarthSun".
EarthSun = PositionFetch('399', '500@10', tStart, tStop, step);

% Ask NASA: "Where is the Moon compared to the Sun?"
%   '301' = the Moon
% This is the path the Moon travels as it rides along around the Sun.
% The answer is saved in a box named "MoonSun".
MoonSun = PositionFetch('301', '500@10', tStart, tStop, step);

% Ask NASA: "Where is the Moon compared to the Earth?"
%   '500@399' = "measured from the center of the Earth"
% This is the little circle the Moon makes around us. The answer is
% saved in a box named "MoonEarth".
MoonEarth = PositionFetch('301', '500@399', tStart, tStop, step);

% Give all three boxes of answers to the drawing helper, which makes
% the picture of the Earth and Moon from them.
PlotEarthMoon(EarthSun, MoonSun, MoonEarth);

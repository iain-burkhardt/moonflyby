% =====================================================================
% WHAT DOES THIS PROGRAM DO? (the super simple version)
% =====================================================================
% Imagine the Sun is a big glowing ball in the middle of a room.
% The Earth runs in a big circle around the Sun, and the Moon runs in a
% little circle around the Earth. While the Earth goes around the Sun,
% the Moon tags along for the ride!
%
% This program:
%   1. Asks NASA's computers (a service called "JPL Horizons") WHERE the
%      Earth and Moon are on every day for one whole year (2027).
%   2. Draws two pictures side by side:
%        LEFT picture : the Earth and Moon traveling around the Sun.
%        RIGHT picture: the Moon circling around the Earth (zoomed in a
%                       lot so you can actually see it).
%   3. Moves the dots a tiny bit each day, like a flip-book cartoon,
%      and saves every picture into a movie file you can watch later.
%
% Words you might not know:
%   - "function" : a little machine that does a job when you press go.
%   - "AU"       : "Astronomical Unit". It is the distance from the
%                  Earth to the Sun. We use it as a space ruler.
%   - "km"       : kilometers, a smaller ruler for closer things.
%   - "Julian date": a way of counting days by just using one big number.
% =====================================================================

% This line says "Here begins a machine named AnimateEarthMoon."
% It takes nothing in and gives nothing back; it just does its job.
function AnimateEarthMoon()

% Close any old picture windows that are still open, so we start fresh.
close all;
% Clean the writing in the Command Window (like erasing a chalkboard).
clc;

%% 1. Settings

% The day and time we want to START watching (midnight, January 1, 2027).
% It is written inside quote marks because it is text (words), not math.
tStart = '2027-01-01 00:00:00';
% The day and time we want to STOP watching (midnight, January 1, 2028).
% So we watch exactly one whole year.
tStop  = '2028-01-01 00:00:00';
% How big a jump in time between each picture: '1 d' means 1 day.
% So we will get one position for each day of the year.
step   = '1 d';

%% 2. Fetch data

% Tell the person watching the screen what we are doing right now.
disp('Fetching Earth-Sun positions...');
% Ask the computers at NASA: "Where is the Earth ('399') compared to the
% Sun ('500@10')?" The numbers are secret codes NASA uses:
%   399 = Earth, 301 = Moon, 10 = Sun, 500@ means "measured from the
%   center of". PositionFetch is a helper machine (written somewhere
%   else) that goes and gets the answer. We hand it the start time, stop
%   time, and step size from above, and the answer is stored in
%   "EarthSun".
EarthSun = PositionFetch('399', '500@10', ...
    tStart, tStop, step);

% Tell the watcher we are now getting the Moon's position next.
disp('Fetching Moon-Sun positions...');
% Same idea: "Where is the Moon ('301') compared to the Sun ('500@10')?"
% This is the path the Moon draws while it travels around the Sun.
MoonSun = PositionFetch('301', '500@10', ...
    tStart, tStop, step);

% Tell the watcher we are getting the last piece of information.
disp('Fetching Moon-Earth positions...');
% "Where is the Moon ('301') compared to the Earth ('500@399')?"
% This is the little circle the Moon makes around the Earth.
MoonEarth = PositionFetch('301', '500@399', ...
    tStart, tStop, step);

%% 3. Extract coordinates

% One AU (the Earth-to-Sun distance) written in kilometers.
% It is about 149.6 million kilometers! We use it to shrink giant
% kilometer numbers into friendly small AU numbers.
AU = 149597870.7;

% From the Earth-Sun answer, pull out the Position_km table.
%   (:,1:2) means "take ALL the rows, but only columns 1 and 2".
%   Column 1 is X (left-right) and column 2 is Y (up-down). We skip
%   column 3 (Z, which is toward-you/away-from-you) because our drawing
%   is flat like paper.
% Then divide by AU so the numbers are in AU instead of kilometers.
earth = EarthSun.Position_km(:,1:2) / AU;
% Same trick for the Moon's position compared to the Sun, also in AU.
moon = MoonSun.Position_km(:,1:2) / AU;
% Moon's position compared to the Earth. We do NOT divide by AU here,
% because the Moon is so close to Earth that kilometers are the better
% ruler for this picture.
lunar = MoonEarth.Position_km(:,1:2);

% Turn the Julian date numbers (one big counting number per day) into
% real calendar dates we can read, like "01-Jan-2027".
dates = datetime(EarthSun.JD, ...
    'ConvertFrom', 'juliandate');

% Check data alignment
% Sometimes the three lists might end up with slightly different numbers
% of days. To be safe, find the SHORTEST list and call its length "N".
% size(x,1) means "how many rows" and numel means "how many things".
N = min([size(earth,1), size(moon,1), ...
         size(lunar,1), numel(dates)]);

% Now cut every list down to exactly N rows, so they all match perfectly
% (like making sure every kid in line has a partner).
earth = earth(1:N,:);
moon = moon(1:N,:);
lunar = lunar(1:N,:);
dates = dates(1:N);

%% 4. Figure setup

% Make a new picture window (a "figure") to draw in.
%   'Name'     : the title in the window's top bar.
%   'Color'    : the background color, a very dark navy blue (like
%                space!). Colors are mixes of [red green blue], each
%                from 0 (none) to 1 (lots).
%   'Position' : [left, bottom, width, height] in pixels, saying where
%                the window sits and how big it is (1450 wide, 700 tall).
% We save the window in "fig" so we can refer to it later.
fig = figure('Name', 'Earth-Moon Animation', ...
    'Color', [0.035 0.045 0.08], ...
    'Position', [100 100 1450 700]);

% Make a movie-maker named "video". It will save a file called
% EarthMoonAnimation.avi using the "Motion JPEG AVI" style, which is
% just a way of squishing pictures into a movie file.
video = VideoWriter('EarthMoonAnimation.avi', ...
    'Motion JPEG AVI');

% Play the movie at 30 pictures (frames) every second.
video.FrameRate = 30;

% Ensure video is closed if an error occurs
% First, open the movie file so we are allowed to put pictures into it.
open(video);
% This is like leaving a note: "If this machine stops for ANY reason,
% even a crash, please close the movie file." onCleanup runs the
% instruction (@() close(video)) automatically when the machine ends.
% This way the movie file doesn't get left broken.
videoCleanup = onCleanup(@() close(video));

%% 5. Colors

% Here we make a paint box! Each color is [red green blue], 0 to 1.

% Background color: the same dark navy blue as the window (our "space").
bg = [0.035 0.045 0.08];
% Text color: a soft white with a tiny bit of blue.
white = [0.9 0.92 0.96];
% Grid-line color: a medium bluish gray.
gray = [0.35 0.4 0.48];

% The Earth's color: a bright ocean blue.
earthColor = [0.15 0.48 1.0];
% The Moon's color: a pale, silvery gray-white.
moonColor = [0.85 0.88 0.94];
% The color of the Moon's trail around the Earth: warm orange.
lunarOrbitColor = [0.95 0.65 0.25];

%% 6. Left plot: Earth and Moon around Sun

% Make a "subplot" which is one box in a grid of boxes. (1,2,1) means:
% a grid with 1 row and 2 columns, and we are using box number 1 (the
% left one). We name this drawing area "ax1" (short for "axes 1").
ax1 = subplot(1,2,1);

% "hold on" means: keep everything we draw. Without it, each new drawing
% would erase the last one. We say it for ax1 specifically.
hold(ax1, 'on');
% Turn on the grid lines (like graph paper).
grid(ax1, 'on');
% Make one step to the right the SAME length as one step up, so circles
% look round and not squished like an egg.
axis(ax1, 'equal');

% Paint the details of this drawing area:
%   'Color'     : the inside background color (space blue).
%   'XColor'    : the color of the bottom ruler and its numbers.
%   'YColor'    : the color of the side ruler and its numbers.
%   'GridColor' : the color of the graph-paper lines.
%   'GridAlpha' : how see-through the grid is (0.25 = faint, so it does
%                 not shout over the planets).
set(ax1, ...
    'Color', bg, ...
    'XColor', white, ...
    'YColor', white, ...
    'GridColor', gray, ...
    'GridAlpha', 0.25);

% Earth orbital path
% Draw the Earth's whole year-long path as a line.
%   earth(:,1) = every X position, earth(:,2) = every Y position.
%   '-'        = a solid line.
%   'Color'    = a medium blue.   'LineWidth' = how thick (1.5).
% We keep the drawing in "hEarthOrbit" (the "h" stands for "handle", like
% a handle on a suitcase that lets us grab it later).
hEarthOrbit = plot(ax1, earth(:,1), earth(:,2), ...
    '-', 'Color', [0.2 0.45 0.85], ...
    'LineWidth', 1.5);

% Moon orbital path around Sun
% Draw the Moon's whole year-long path around the Sun as a thin gray
% line. It almost sits on top of the Earth's path, because the Moon
% stays close to the Earth.
hMoonOrbit = plot(ax1, moon(:,1), moon(:,2), ...
    '-', 'Color', [0.55 0.55 0.65], ...
    'LineWidth', 1);

% Sun
% Draw the Sun as one big dot at the center, position (0, 0).
%   'o'               = a circle shape.
%   'MarkerSize'      = how big (20 is large).
%   'MarkerFaceColor' = the inside color: golden yellow.
%   'MarkerEdgeColor' = the outline color: light yellow.
hSun = plot(ax1, 0, 0, 'o', ...
    'MarkerSize', 20, ...
    'MarkerFaceColor', [1 0.8 0.1], ...
    'MarkerEdgeColor', [1 0.95 0.5]);

% Moving Earth
% Draw the Earth as a blue dot, starting at day 1's position
% (earth(1,1) = X on day 1, earth(1,2) = Y on day 1).
% Later, in the animation loop, we will slide this dot along its path.
% The dot has a white outline ('w' = white).
hEarth = plot(ax1, earth(1,1), earth(1,2), ...
    'o', 'MarkerSize', 13, ...
    'MarkerFaceColor', earthColor, ...
    'MarkerEdgeColor', 'w', ...
    'LineWidth', 1.2);

% Moving Moon
% Draw the Moon as a smaller silver dot, starting at day 1's position
% around the Sun. It has a black outline ('k' = black). We will slide
% it along later too.
hMoon = plot(ax1, moon(1,1), moon(1,2), ...
    'o', 'MarkerSize', 10, ...
    'MarkerFaceColor', moonColor, ...
    'MarkerEdgeColor', 'k', ...
    'LineWidth', 1.2);

% Label the bottom ruler "X (AU)" and the side ruler "Y (AU)" so people
% know the numbers are measured in AU. Labels are white to show on dark.
xlabel(ax1, 'X (AU)', 'Color', white);
ylabel(ax1, 'Y (AU)', 'Color', white);

% Give this picture a title across the top, in white, with big letters.
title(ax1, 'Earth and Moon Around Sun', ...
    'Color', white, 'FontSize', 14);

% Make a legend: a little key that tells you what each thing is.
% The first list holds the drawings, the second list holds the names, in
% the same order. The legend sits below the picture ('southoutside'),
% with white text, a space-blue background, and a gray border.
legend(ax1, ...
    [hEarthOrbit, hMoonOrbit, hSun, hEarth, hMoon], ...
    {'Earth orbit', 'Moon orbit', 'Sun', 'Earth', 'Moon'}, ...
    'TextColor', white, ...
    'Color', bg, ...
    'EdgeColor', gray, ...
    'Location', 'southoutside');

% A little extra empty space (0.2 AU) around the edges so the Earth's
% path does not touch the border of the picture.
margin = 0.2;

% Set how far left and right the picture shows: from the smallest X the
% Earth ever has, minus the margin, to the biggest X plus the margin.
xlim(ax1, [min(earth(:,1))-margin, ...
    max(earth(:,1))+margin]);

% Do the same for up and down, using the Y positions.
ylim(ax1, [min(earth(:,2))-margin, ...
    max(earth(:,2))+margin]);

%% 7. Right plot: Earth-Moon system

% Now the RIGHT box: 1 row, 2 columns, box number 2.
% We name it "ax2".
ax2 = subplot(1,2,2);

% Keep everything we draw, show the grid, and make circles look round
% (the same three steps we did for the left picture).
hold(ax2, 'on');
grid(ax2, 'on');
axis(ax2, 'equal');

% Paint this box with the same space-blue theme as the left one.
set(ax2, ...
    'Color', bg, ...
    'XColor', white, ...
    'YColor', white, ...
    'GridColor', gray, ...
    'GridAlpha', 0.25);

% Moon orbital trail (starts empty)
% Draw an orange line, but at first it has NOTHING in it (NaN means
% "not a number", so nothing is drawn). During the animation we will
% fill it in bit by bit, like a crayon leaving a trail behind the Moon.
hTrail = plot(ax2, NaN, NaN, ...
    '-', 'Color', lunarOrbitColor, ...
    'LineWidth', 2);

% Earth at origin
% Draw a big blue Earth right in the middle at (0, 0). In this picture
% the Earth stays still and the Moon moves around it.
hEarth2 = plot(ax2, 0, 0, 'o', ...
    'MarkerSize', 28, ...
    'MarkerFaceColor', earthColor, ...
    'MarkerEdgeColor', 'w', ...
    'LineWidth', 1.5);

% Earth label
% Write the word "Earth" right next to the Earth dot (the two spaces
% before the word nudge it a little to the right) in bold white letters.
text(ax2, 0, 0, '  Earth', ...
    'Color', white, ...
    'FontSize', 11, ...
    'FontWeight', 'bold');

% Moving Moon
% Draw the Moon as a silver dot at its day-1 spot around the Earth.
% It will move each day in the animation loop.
hLunarMoon = plot(ax2, lunar(1,1), lunar(1,2), ...
    'o', 'MarkerSize', 15, ...
    'MarkerFaceColor', moonColor, ...
    'MarkerEdgeColor', 'w', ...
    'LineWidth', 1.5);

% Label the rulers in kilometers this time (not AU).
xlabel(ax2, 'X (km)', 'Color', white);
ylabel(ax2, 'Y (km)', 'Color', white);

% Title for the right picture. "Expanded View" means we zoomed in on
% the Earth and Moon a LOT. In real life the Moon is far tinier and
% farther away compared to the Sun-sized picture on the left!
title(ax2, 'Moon Around Earth (Expanded View)', ...
    'Color', white, 'FontSize', 14);

% Make the legend for the right picture: it explains the orange trail,
% the Earth, and the Moon. Styled the same as the left legend.
legend(ax2, ...
    [hTrail, hEarth2, hLunarMoon], ...
    {'Moon orbital trail', 'Earth', 'Moon'}, ...
    'TextColor', white, ...
    'Color', bg, ...
    'EdgeColor', gray, ...
    'Location', 'southoutside');

% Figure out how big the picture should be:
%   lunar(:) squishes all the Moon's positions into one long list,
%   abs() makes every number positive (ignores left/right, up/down),
%   max() finds the biggest one = the farthest the Moon ever gets,
%   * 1.35 adds 35% extra room so the Moon never touches the edge.
axisLimit = max(abs(lunar(:))) * 1.35;

% Make the picture go from -axisLimit to +axisLimit in BOTH directions,
% so the Earth sits perfectly in the middle of a square view.
xlim(ax2, [-axisLimit axisLimit]);
ylim(ax2, [-axisLimit axisLimit]);

%% 8. Animation

% Tell the watcher the show is starting!
disp('Starting animation...');

% A "for loop" repeats the same steps again and again.
% "k" counts the days: first k=1, then k=2, then 3, ... all the way up
% to N (the last day). Each time around the loop = one day = one frame
% of our movie, like turning one page of a flip-book.
for k = 1:N

    % Update Earth around Sun
    % Slide the left picture's blue Earth dot to its position on day k.
    % 'XData' is its left-right spot and 'YData' is its up-down spot.
    set(hEarth, ...
        'XData', earth(k,1), ...
        'YData', earth(k,2));

    % Update Moon around Sun
    % Slide the left picture's silver Moon dot to where it is on day k.
    set(hMoon, ...
        'XData', moon(k,1), ...
        'YData', moon(k,2));

    % Update Moon around Earth
    % Slide the right picture's Moon dot to where it is on day k,
    % measured from the Earth in the middle.
    set(hLunarMoon, ...
        'XData', lunar(k,1), ...
        'YData', lunar(k,2));

    % Gradually draw Moon's orbital trail
    % Make the orange trail go from day 1 up to day k. (1:k means
    % "rows 1 through k".) As k grows, the trail gets longer, like a
    % snail leaving a slime path behind it.
    set(hTrail, ...
        'XData', lunar(1:k,1), ...
        'YData', lunar(1:k,2));

    % Update date
    % Write a big title across the TOP of the whole window that shows
    % today's date for this frame (like "17 Mar 2027"). datestr turns
    % the date into readable words, 'dd mmm yyyy' is the style:
    % day, short month name, year. The square brackets glue the words
    % 'Earth-Moon System: ' and the date together into one sentence.
    % sgtitle = "super title" (a title for all the pictures at once).
    sgtitle(['Earth-Moon System: ', ...
        datestr(dates(k), 'dd mmm yyyy')], ...
        'Color', white, ...
        'FontSize', 17, ...
        'FontWeight', 'bold');

    % Render frame
    % "Draw it now!" Tell the computer to actually paint all our
    % changes on the screen right this second.
    drawnow;

    % Save video frame
    % getframe(fig) takes a photograph of the window as it looks right
    % now. writeVideo(video, ...) puts that photo into the movie file
    % as the next page of the flip-book.
    writeVideo(video, getframe(fig));

% This "end" says: that's the end of the steps to repeat. Go back up
% and do the next day, until all N days are done.
end

%% 9. Finish

% We have put in all the pictures, so close the movie file. This saves
% it properly so it can be played.
close(video);

% Tell the watcher we are all done and where to find the movie.
disp('Animation complete!');
disp('Saved as EarthMoonAnimation.avi');

% This "end" matches the "function" at the very top. It means:
% the AnimateEarthMoon machine is finished. The end!
end

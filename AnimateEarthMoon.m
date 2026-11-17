
function AnimateEarthMoon()
% ANIMATEEARTHMOON
% Generates an animation of the Earth-Moon system over the 2027 calendar
% year using position and velocity data retrieved from JPL Horizons.
%
% The animation contains two coordinate-system views:
%   1. Heliocentric view: Earth and Moon positions relative to the Sun,
%      expressed in astronomical units (AU).
%   2. Geocentric view: Moon position relative to Earth, expressed in km.
%
% The program retrieves ephemeris data at daily intervals, constructs
% static orbital paths, and animates the bodies by updating the XData
% and YData properties of existing MATLAB graphics objects.
%
% Each animation frame is captured and written to an AVI video file.
%
% DEPENDENCIES:
%   PositionFetch.m - Retrieves ephemeris data from JPL Horizons.
%
% OUTPUT:
%   EarthMoonAnimation.avi - Animation of the Earth-Moon system.

    close all;
    clc;

    %% 1. Simulation configuration

    % Define the time interval covered by the simulation.
    % The timestamps use the format YYYY-MM-DD HH:MM:SS.
    % The interval includes January 1, 2027, through January 1, 2028.
    tStart = '2027-01-01 00:00:00';
    tStop  = '2028-01-01 00:00:00';

    % Specify the sampling interval used by JPL Horizons.
    % A one-day interval produces approximately one position sample
    % per day throughout the simulation.
    step = '1 d';

    %% 2. Retrieve ephemeris data

    % Retrieve the Earth's heliocentric position.
    % PositionFetch(body, center, startTime, stopTime, step) queries
    % JPL Horizons for the position and velocity of a specified body
    % relative to a specified reference center.
    %
    % Horizons target and center identifiers:
    %   399     Earth
    %   301     Moon
    %   10      Sun
    %   500@10  Center of the Sun
    %   500@399 Center of the Earth
    %
    % The resulting table contains Julian dates, position vectors,
    % and velocity vectors. Position vectors are expressed in km.
    disp('Fetching Earth-Sun positions...');
    EarthSun = PositionFetch('399', '500@10', ...
        tStart, tStop, step);

    % Retrieve the Moon's heliocentric position.
    % This is the Moon's position relative to the Sun, not its position
    % relative to Earth. Consequently, its path will be similar to
    % Earth's heliocentric orbit, with a small monthly displacement.
    disp('Fetching Moon-Sun positions...');
    MoonSun = PositionFetch('301', '500@10', ...
        tStart, tStop, step);

    % Retrieve the Moon's geocentric position.
    % These coordinates describe the Moon's position relative to
    % Earth's center and are used in the expanded Earth-Moon view.
    disp('Fetching Moon-Earth positions...');
    MoonEarth = PositionFetch('301', '500@399', ...
        tStart, tStop, step);

    %% 3. Extract and prepare coordinate data

    % Astronomical unit (AU), defined as exactly 149,597,870.7 km.
    % Converting heliocentric coordinates from km to AU produces
    % more manageable values for plotting distances on an orbital scale.
    AU = 149597870.7;

    % Extract the first two Cartesian components of each heliocentric
    % position vector. Position_km is an N-by-3 matrix, where each row
    % represents a position sample and the columns correspond to X, Y,
    % and Z coordinates.
    %
    % The colon selects every row, while 1:2 selects only the X and Y
    % columns. The Z component is omitted to produce a two-dimensional
    % projection of the orbital motion.
    %
    % Divide by AU to convert the coordinates from km to AU.
    earth = EarthSun.Position_km(:,1:2) / AU;
    moon = MoonSun.Position_km(:,1:2) / AU;

    % Retain the Moon's geocentric coordinates in km.
    % At the Earth-Moon scale, kilometers are a more convenient unit
    % than AU because the Earth-Moon separation is approximately
    % 384,400 km.
    lunar = MoonEarth.Position_km(:,1:2);

    % Convert the Julian dates returned by Horizons into MATLAB
    % datetime values. Julian dates represent time as a continuous
    % numerical count of days, making them useful for astronomical
    % calculations and comparisons.
    dates = datetime(EarthSun.JD, ...
        'ConvertFrom', 'juliandate');

    % Determine the number of samples shared by all four data arrays.
    % This prevents indexing errors if the ephemeris requests return
    % slightly different numbers of samples.
    %
    % size(matrix,1) returns the number of rows, while numel returns
    % the total number of elements in an array.
    %
    % Note: This truncation assumes that corresponding rows represent
    % the same epochs. It does not independently verify timestamp
    % alignment between the three Horizons requests.
    N = min([size(earth,1), size(moon,1), ...
             size(lunar,1), numel(dates)]);

    % Restrict each dataset to the first N samples so that the arrays
    % have matching lengths and can be indexed using the same loop index.
    earth = earth(1:N,:);
    moon = moon(1:N,:);
    lunar = lunar(1:N,:);
    dates = dates(1:N);

    %% 4. Figure and video initialization

    % Create the main MATLAB figure window.
    % The Position property specifies [left, bottom, width, height]
    % in pixels. The figure background uses an RGB color specification,
    % where each component ranges from 0 to 1.
    fig = figure('Name', 'Earth-Moon Animation', ...
        'Color', [0.035 0.045 0.08], ...
        'Position', [100 100 1450 700]);

    % Initialize a VideoWriter object to encode the animation as an AVI
    % file using Motion JPEG compression.
    video = VideoWriter('EarthMoonAnimation.avi', ...
        'Motion JPEG AVI');

    % Set the playback rate to 30 frames per second.
    % This controls playback speed, not the temporal spacing of the
    % astronomical samples. Each frame still represents one day.
    video.FrameRate = 30;

    % Open the video stream before writing any frames.
    open(video);

    % Register a cleanup operation that closes the video object when
    % this function exits, including when an error interrupts execution.
    % onCleanup executes its associated function when the cleanup object
    % is destroyed, providing protection against an improperly closed
    % output file.
    videoCleanup = onCleanup(@() close(video));

    %% 5. Visualization parameters

    % Define RGB color values for the figure background, text, grid,
    % Earth, Moon, and lunar trajectory.
    % Each RGB vector specifies the relative intensities of red, green,
    % and blue, with values between 0 (minimum) and 1 (maximum).
    bg = [0.035 0.045 0.08];
    white = [0.9 0.92 0.96];
    gray = [0.35 0.4 0.48];

    earthColor = [0.15 0.48 1.0];
    moonColor = [0.85 0.88 0.94];
    lunarOrbitColor = [0.95 0.65 0.25];

    %% 6. Left subplot: heliocentric Earth-Moon system

    % Create the first axes object using a 1-by-2 subplot layout.
    % subplot(1,2,1) selects the first position in a layout consisting
    % of one row and two columns.
    ax1 = subplot(1,2,1);

    % Enable hold mode so that subsequent plotting commands add graphics
    % objects to the existing axes instead of replacing previous plots.
    hold(ax1, 'on');
    grid(ax1, 'on');

    % Enforce equal scaling on the X and Y axes. This ensures that
    % equal numerical distances are represented by equal visual
    % distances, preserving the geometry of the orbital projection.
    axis(ax1, 'equal');

    % Configure the axes appearance. Color controls the plotting area's
    % background, XColor and YColor control the axis labels and ticks,
    % and GridColor/GridAlpha control the grid's appearance.
    set(ax1, ...
        'Color', bg, ...
        'XColor', white, ...
        'YColor', white, ...
        'GridColor', gray, ...
        'GridAlpha', 0.25);

    % Plot the Earth's heliocentric trajectory using all available
    % position samples. The resulting line represents the sampled
    % orbital path over the simulation interval.
    %
    % Store the returned graphics handle in hEarthOrbit. A graphics
    % handle provides a reference to the plotted object, allowing
    % its properties to be accessed or modified later.
    hEarthOrbit = plot(ax1, earth(:,1), earth(:,2), ...
        '-', 'Color', [0.2 0.45 0.85], ...
        'LineWidth', 1.5);

    % Plot the Moon's heliocentric trajectory.
    % Since the Moon revolves around Earth while Earth revolves around
    % the Sun, the Moon's heliocentric path is similar to Earth's orbit,
    % but contains an additional monthly oscillation.
    hMoonOrbit = plot(ax1, moon(:,1), moon(:,2), ...
        '-', 'Color', [0.55 0.55 0.65], ...
        'LineWidth', 1);

    % Represent the Sun at the origin of the heliocentric coordinate
    % system. The marker is a visualization symbol rather than a
    % geometrically scaled representation of the Sun's physical radius.
    hSun = plot(ax1, 0, 0, 'o', ...
        'MarkerSize', 20, ...
        'MarkerFaceColor', [1 0.8 0.1], ...
        'MarkerEdgeColor', [1 0.95 0.5]);

    % Create the moving Earth marker at the first sampled position.
    % Its XData and YData properties will be updated during the
    % animation loop to represent the Earth's changing position.
    hEarth = plot(ax1, earth(1,1), earth(1,2), ...
        'o', 'MarkerSize', 13, ...
        'MarkerFaceColor', earthColor, ...
        'MarkerEdgeColor', 'w', ...
        'LineWidth', 1.2);

    % Create the moving Moon marker using its heliocentric coordinates.
    % This marker is independent of the Moon marker in the second subplot:
    % the two markers represent the same body in different reference frames.
    hMoon = plot(ax1, moon(1,1), moon(1,2), ...
        'o', 'MarkerSize', 10, ...
        'MarkerFaceColor', moonColor, ...
        'MarkerEdgeColor', 'k', ...
        'LineWidth', 1.2);

    % Label the coordinate axes. Since the heliocentric coordinates
    % were converted to AU, the axis labels use AU rather than km.
    xlabel(ax1, 'X (AU)', 'Color', white);
    ylabel(ax1, 'Y (AU)', 'Color', white);

    title(ax1, 'Earth and Moon Around Sun', ...
        'Color', white, 'FontSize', 14);

    % Construct a legend using explicit graphics handles.
    % Passing handles rather than relying on plotting order makes it
    % possible to specify exactly which objects appear in the legend
    % and the order in which they are displayed.
    legend(ax1, ...
        [hEarthOrbit, hMoonOrbit, hSun, hEarth, hMoon], ...
        {'Earth orbit', 'Moon orbit', 'Sun', 'Earth', 'Moon'}, ...
        'TextColor', white, ...
        'Color', bg, ...
        'EdgeColor', gray, ...
        'Location', 'southoutside');

    % Determine the displayed coordinate limits from the Earth's
    % heliocentric position data. A small margin is added so the
    % orbital path is not drawn directly against the axes boundaries.
    margin = 0.2;

    xlim(ax1, [min(earth(:,1))-margin, ...
        max(earth(:,1))+margin]);

    ylim(ax1, [min(earth(:,2))-margin, ...
        max(earth(:,2))+margin]);

    %% 7. Right subplot: geocentric Earth-Moon system

    % Create the second axes object in the same 1-by-2 subplot layout.
    % This view uses geocentric coordinates, so Earth's center is
    % located at the origin and the Moon's position is measured relative
    % to Earth rather than relative to the Sun.
    ax2 = subplot(1,2,2);

    hold(ax2, 'on');
    grid(ax2, 'on');
    axis(ax2, 'equal');

    % Apply the same visual configuration used in the first subplot.
    set(ax2, ...
        'Color', bg, ...
        'XColor', white, ...
        'YColor', white, ...
        'GridColor', gray, ...
        'GridAlpha', 0.25);

    % Initialize an empty line object for the Moon's orbital trail.
    % NaN values prevent an initial line from being drawn.
    % The animation loop will progressively populate the line's
    % XData and YData properties with the Moon's previous positions.
    hTrail = plot(ax2, NaN, NaN, ...
        '-', 'Color', lunarOrbitColor, ...
        'LineWidth', 2);

    % Plot Earth at the origin of the geocentric coordinate system.
    % Earth remains stationary in this view because all lunar coordinates
    % are measured relative to Earth's center.
    hEarth2 = plot(ax2, 0, 0, 'o', ...
        'MarkerSize', 28, ...
        'MarkerFaceColor', earthColor, ...
        'MarkerEdgeColor', 'w', ...
        'LineWidth', 1.5);

    % Add a text annotation identifying the central body.
    text(ax2, 0, 0, '  Earth', ...
        'Color', white, ...
        'FontSize', 11, ...
        'FontWeight', 'bold');

    % Initialize the moving Moon marker using its first geocentric
    % position sample. Its coordinates are updated each animation frame.
    hLunarMoon = plot(ax2, lunar(1,1), lunar(1,2), ...
        'o', 'MarkerSize', 15, ...
        'MarkerFaceColor', moonColor, ...
        'MarkerEdgeColor', 'w', ...
        'LineWidth', 1.5);

    xlabel(ax2, 'X (km)', 'Color', white);
    ylabel(ax2, 'Y (km)', 'Color', white);

    title(ax2, 'Moon Around Earth (Expanded View)', ...
        'Color', white, 'FontSize', 14);

    % Create the legend for the geocentric view using the graphics
    % handles corresponding to the lunar trail, Earth, and Moon.
    legend(ax2, ...
        [hTrail, hEarth2, hLunarMoon], ...
        {'Moon orbital trail', 'Earth', 'Moon'}, ...
        'TextColor', white, ...
        'Color', bg, ...
        'EdgeColor', gray, ...
        'Location', 'southoutside');

    % Calculate a symmetric viewing range from the maximum absolute
    % geocentric coordinate value in the dataset.
    %
    % lunar(:) converts the coordinate matrix into a single column
    % vector. max(abs(...)) therefore finds the largest absolute
    % X or Y coordinate across all samples.
    %
    % Multiplying by 1.35 adds 35% extra space around the trajectory.
    axisLimit = max(abs(lunar(:))) * 1.35;

    % Apply identical limits to both axes, keeping Earth centered
    % and ensuring that the viewing area has equal X and Y dimensions.
    xlim(ax2, [-axisLimit axisLimit]);
    ylim(ax2, [-axisLimit axisLimit]);

    %% 8. Animation loop

    disp('Starting animation...');

    % Iterate over every available position sample.
    % Each iteration corresponds to one daily ephemeris sample and
    % produces one frame in the output video.
    %
    % Rather than deleting and recreating graphics objects on every
    % iteration, the program updates the properties of the existing
    % graphics handles. This is generally more efficient and preserves
    % the figure's axes, labels, legends, and other static elements.
    for k = 1:N

        % Update the Earth's heliocentric position.
        % XData and YData determine the marker's coordinates within ax1.
        set(hEarth, ...
            'XData', earth(k,1), ...
            'YData', earth(k,2));

        % Update the Moon's heliocentric position in the first subplot.
        set(hMoon, ...
            'XData', moon(k,1), ...
            'YData', moon(k,2));

        % Update the Moon's geocentric position in the second subplot.
        % Although this is the same physical body as hMoon, its
        % coordinates come from the Earth-centered reference frame.
        set(hLunarMoon, ...
            'XData', lunar(k,1), ...
            'YData', lunar(k,2));

        % Update the lunar trail to include every position sample
        % from the beginning of the simulation through the current day.
        % The indexing expression 1:k selects rows 1 through k.
        % This produces a progressively growing trajectory.
        set(hTrail, ...
            'XData', lunar(1:k,1), ...
            'YData', lunar(1:k,2));

        % Update the figure-level title to display the date associated
        % with the current position sample.
        %
        % datestr converts a datetime value into formatted character
        % data. The format 'dd mmm yyyy' produces dates such as
        % '01 Jan 2027'. sgtitle applies a title to the entire figure,
        % rather than to just one subplot.
        sgtitle(['Earth-Moon System: ', ...
            datestr(dates(k), 'dd mmm yyyy')], ...
            'Color', white, ...
            'FontSize', 17, ...
            'FontWeight', 'bold');

        % Force MATLAB to process pending graphics updates so that
        % the current frame is rendered before it is captured.
        drawnow;

        % Capture the current figure as an image frame and append it
        % to the AVI video stream. getframe captures the rendered figure,
        % while writeVideo writes the resulting frame to the file.
        writeVideo(video, getframe(fig));

    end

    %% 9. Finalize output

    % Close the video stream to finalize the AVI file and ensure that
    % the written frames are properly saved.
    close(video);

    disp('Animation complete!');
    disp('Saved as EarthMoonAnimation.avi');

end

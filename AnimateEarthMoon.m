
function AnimateEarthMoon()

%% 1. Settings

tStart = '2027-01-01 00:00:00';
tStop  = '2028-01-01 00:00:00';
step   = '1 d';

%% 2. Fetch data

disp('Fetching Earth-Sun positions...');
EarthSun = PositionFetch('399', '500@10', ...
    tStart, tStop, step);

disp('Fetching Moon-Sun positions...');
MoonSun = PositionFetch('301', '500@10', ...
    tStart, tStop, step);

disp('Fetching Moon-Earth positions...');
MoonEarth = PositionFetch('301', '500@399', ...
    tStart, tStop, step);

%% 3. Extract coordinates

% Convert kilometers to astronomical units
AU = 149597870.7;

earth = EarthSun.Position_km(:,1:2) / AU;
moon = MoonSun.Position_km(:,1:2) / AU;

% Moon position relative to Earth (km)
lunar = MoonEarth.Position_km(:,1:2);

% Dates
dates = datetime(EarthSun.JD, ...
    'ConvertFrom', 'juliandate');

% Check data alignment
N = min([size(earth,1), size(moon,1), ...
         size(lunar,1), numel(dates)]);

earth = earth(1:N,:);
moon = moon(1:N,:);
lunar = lunar(1:N,:);
dates = dates(1:N);

%% 4. Create figure

fig = figure('Name', 'Earth-Moon Orbital Animation', ...
    'Color', 'w', ...
    'Position', [100 100 1200 600]);

% Video settings
video = VideoWriter('EarthMoonAnimation.avi', 'Motion JPEG AVI');
video.FrameRate = 30;
open(video);

%% 5. Left plot: Solar system

subplot(1,2,1);

hold on;
grid on;
axis equal;

% Full orbital paths
plot(earth(:,1), earth(:,2), ...
    'Color', [0.8 0.8 0.8]);

plot(moon(:,1), moon(:,2), ...
    'Color', [0.8 0.8 0.8]);

% Sun
plot(0, 0, 'yo', ...
    'MarkerSize', 14, ...
    'MarkerFaceColor', 'y');

% Moving objects
hEarth = plot(earth(1,1), earth(1,2), ...
    'bo', 'MarkerSize', 9, ...
    'MarkerFaceColor', 'b');

hMoon = plot(moon(1,1), moon(1,2), ...
    'ko', 'MarkerSize', 6, ...
    'MarkerFaceColor', 'k');

xlabel('X (AU)');
ylabel('Y (AU)');
title('Earth and Moon Around Sun');

legend('Earth orbit', 'Moon orbit', ...
    'Sun', 'Earth', 'Moon');

% Fixed axis limits
margin = 0.2;
xlim([min(earth(:,1))-margin, max(earth(:,1))+margin]);
ylim([min(earth(:,2))-margin, max(earth(:,2))+margin]);

%% 6. Right plot: Earth-Moon system

subplot(1,2,2);

hold on;
grid on;
axis equal;

% Moon's orbital path
plot(lunar(:,1), lunar(:,2), ...
    'Color', [0.8 0.8 0.8]);

% Earth at origin
plot(0, 0, 'bo', ...
    'MarkerSize', 12, ...
    'MarkerFaceColor', 'b');

% Moving Moon
hLunarMoon = plot(lunar(1,1), lunar(1,2), ...
    'ko', 'MarkerSize', 8, ...
    'MarkerFaceColor', 'k');

xlabel('X (km)');
ylabel('Y (km)');
title('Moon Around Earth');

legend('Moon orbit', 'Earth', 'Moon');

axisLimit = max(abs(lunar(:))) * 1.2;
xlim([-axisLimit axisLimit]);
ylim([-axisLimit axisLimit]);

%% 7. Animation loop

for k = 1:N

    % Update positions
    set(hEarth, ...
        'XData', earth(k,1), ...
        'YData', earth(k,2));

    set(hMoon, ...
        'XData', moon(k,1), ...
        'YData', moon(k,2));

    set(hLunarMoon, ...
        'XData', lunar(k,1), ...
        'YData', lunar(k,2));

    % Update date
    sgtitle(['Earth-Moon System: ', ...
        char(datestr(dates(k), 'dd mmm yyyy'))]);

    % Render frame
    drawnow;

    % Save frame
    writeVideo(video, getframe(fig));

end

%% 8. Finish

close(video);

disp('Animation complete!');
disp('Saved as EarthMoonAnimation.mp4');

end

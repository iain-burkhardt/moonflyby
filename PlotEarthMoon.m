function PlotEarthMoon(EarthSun, MoonSun, MoonEarth)

% Extract position data
earthPos = EarthSun.Position_km;
moonPos = MoonSun.Position_km;
moonEarthPos = MoonEarth.Position_km;

% Create figure
figure('Name', 'Earth and Moon Orbits');

hold on;
grid on;
axis equal;

% Plot Earth's orbit path (light grey)
plot(earthPos(:,1), earthPos(:,2), ...
    'Color', [0.8 0.8 0.8], ...
    'LineWidth', 1.5);

% Plot Moon's orbit path around the Sun (light grey)
plot(moonPos(:,1), moonPos(:,2), ...
    'Color', [0.8 0.8 0.8], ...
    'LineWidth', 1.5);

% Plot Earth's current position
plot(earthPos(1,1), earthPos(1,2), ...
    'bo', 'MarkerSize', 10, ...
    'MarkerFaceColor', 'b');

% Plot Moon's current position
plot(moonPos(1,1), moonPos(1,2), ...
    'ko', 'MarkerSize', 7, ...
    'MarkerFaceColor', 'k');

% Draw Moon's orbit around Earth, centered on Earth
theta = linspace(0, 2*pi, 300);

moonOrbitX = earthPos(1,1) + ...
    norm(moonEarthPos(1,:)) * cos(theta);

moonOrbitY = earthPos(1,2) + ...
    norm(moonEarthPos(1,:)) * sin(theta);

plot(moonOrbitX, moonOrbitY, ...
    'Color', [0.8 0.8 0.8], ...
    'LineStyle', '--');

% Labels
xlabel('X (km)');
ylabel('Y (km)');

title('Earth and Moon - Top Down View');

legend('Earth orbit around Sun', ...
    'Moon orbit around Sun', ...
    'Earth', 'Moon', ...
    'Moon orbit around Earth');

hold off;

end


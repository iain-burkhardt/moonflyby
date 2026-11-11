clear;
clc;
close all;

tStart = '2027-01-01 00:00:00';
tStop = '2027-01-08 00:00:00';
step = '1 h';

EarthSun = PositionFetch('399', '500@10', tStart, tStop, step);
MoonSun = PositionFetch('301', '500@10', tStart, tStop, step);
MoonEarth = PositionFetch('301', '500@399', tStart, tStop, step);

PlotEarthMoon(EarthSun, MoonSun, MoonEarth);

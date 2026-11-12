# moonflyby

Final project for MCEN 1030 by Anthony Deluca, Iain Burkhardt, and Gabe Dozois

## Project Goal
- Pick a launch date and site, then pull both Earth and Moon positions from different API's for that moment.  We're then going to compute a realistic flight path that leaves Earth, and swings around the Moon and then comes home using an assumed gravity assist.
- 1. Parking Orbit: Launched into a circular orbit at the set altitude and inclination
  2. Translunar Injection: Burn that puts the spacecraft on a path to intercept the moon
  3. Lunar Flyby: Pass the Moon at the target altitude; its gravity bends the path home
  4. Earth Return: Coast back and hit the target perigree within the time limit.
 
## Inputs
- We have planned inputs that will change the rockets' trajectory and flight path in order to provide the most realistic sense of what will happen if that were the real case.  These inputs include:
  1. Launch date & time in date, hours (sets Earth & Moon positions relative to the Sun)
  2. Launch Site in Latitude and Longitude
  3. Parking orbit altitude in km
  4. Parking orbit inclination in degrees
  5. Target lunar flyby altitude in km
  6. Target return perigree altitude in km
  7. Maximum mission duration in days & hours

## Outputs
- We have planned outputs that will show the result of the entered information and will return the best flight path for fuel & time efficiency.  It will return these values in a .csv file (x, y, z position and velocity at every time step) and a .json file (Summary of the mission results). These inputs include:
  1. Total time of flight in days & hours
  2. Pass/Fail, checked against the input targets and the time limit
  3. Return Pedigree, altitude in km and time in days & hours
     
## Figures

## Validation

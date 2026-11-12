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
- We have planned different figures to represent the multiple aspects that come with rocket trajectories.  These figures include:
- Inertial Trejectory (Full path in the earth-centered inertial frame)
- Rotating-frame trajectory (Earth-moon rotating frame - shows the figure eight flight path)
- Distance from Earth (range vs. time for the whole mission)
- Lunar altitude (Height above the Moon vs. time, zoomed on the flyby)
- Animation (The flight path played out over time)

## Validation
- We need to validate our information with a sanity check.  Our sanity check is comparing our data gathered to the data of Artemis II's launch date, orbit, and targets, then compare against NASA's path:
  1. Total time of flight
  2. Lunar flyby altitude
  3. Return pedigree
  4. Overall path shape
- However there are some likely sources of error which include:
  1. Simplified gravity model vs. full n-body
  2. Instant burns vs. finite-length burns
  3. Ephemeris accuracy and time-step size
  4. Ignored effects: Earth oblateness, solar gravity, radiation pressure
  5. No mid-course corrections

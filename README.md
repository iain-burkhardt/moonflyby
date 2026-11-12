# moonflyby

Final project for MCEN 1030 by Anthony Deluca, Iain Burkhardt, and Gabe Dozois

## Project Goal
- Pick a launch date and site, then pull both Earth and Moon positions from different API's for that moment.  We're then going to compute a realistic flight path that leaves Earth, and swings around the Moon and then comes home using an assumed gravity assist.
- 1. Parking Orbit: Launched into a circular orbit at the set altitude and inclination
  2. Translunar Injection: Burn that puts the spacecraft on a path to intercept the moon
  3. Lunar Flyby: Pass the Moon at the target altitude; its gravity bends the path home
  4. Earth Return: Coast back and hit the target perigree within the time limit.

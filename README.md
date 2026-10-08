# Daughter Of The Wind

A flying game for the Scareathon arcade, after the flying scenes in Nausicaä: a girl on a white
glider, a sky full of clouds, and a fleet of giant metal airships. Godot 4.7, built for the web.

This is the first pass: the flight, the glider, the cloud system and the airships. There is no
goal or score yet.

## Flying

| | Keys | Gamepad | Touch |
| --- | --- | --- | --- |
| Bank left / right | A / D or arrows | left stick | drag on the left of the screen |
| Pull up | S or Down | stick back | drag down |
| Dive | W or Up | stick forward | drag up |
| Jet boost | Space | A or right trigger | hold the right of the screen |
| Air brake | Shift | B or left trigger | |
| Restart | R | | |
| Weather: clear / fair / heavy | 1 / 2 / 3 | | |

It flies like a glider. Diving buys speed and pulling up spends it. Bank to turn. Left alone it
settles into a gentle glide, sinking about 2 m/s, so to stay up you need lift: the air rises under
every cumulus and cloud tower, and the jet gives a few seconds of push before it has to recharge.
Sink into the sea of clouds and the wind lifts you back out.

## Tests

    godot --headless --fixed-fps 60 --path . -s res://tests/flight_test.gd
    godot --headless --fixed-fps 60 --path . -s res://tests/cloud_test.gd
    godot --headless --fixed-fps 60 --path . -s res://tests/fleet_test.gd
    godot --fixed-fps 60 --path . -s res://tests/shots.gd -- <folder for screenshots>

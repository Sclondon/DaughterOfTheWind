# Daughter Of The Wind

A flying game for the Scareathon arcade, after the flying scenes in Nausicaä: a girl on a white
glider, a sky full of clouds, and a fleet of giant metal airships. Godot 4.7, built for the web.

There are two levels so far, and no goal or score yet:

- **Sea of Clouds**: an endless cloud deck with a convoy of airships crossing it.
- **The Windward Coast**: the sea to the west and, to the east, towering cliffs that run north
  and south for ever. The cliffs climb in great steps, with terraced fields, hamlets and
  windmills on every ledge. One gentle valley runs down through them to a beach, with the
  castle and its town in it, a stream, flower meadows and giant old trees. The sea off the
  cliffs is a maze of rock spires and arches to weave through. The sea wind is pushed up by
  the cliffs, so you can soar along them without losing height.

After the two levels, the level button (or L) goes to the **Diorama**: a small test room for
looking at the cel shading. The glider hangs in a steady wind over a turntable with a few plain
shapes beside it and small clouds drifting past. Drag to turn the camera all the way round,
over the top and underneath; wheel or pinch to zoom; the flying keys work the flaps; Z / X or
the button walk the sun round the sky.

You can fly as the glider or as a witch on a broomstick; the flying is the same. The glider's
pilot is a girl who stands on it holding the handles: she stands bent over them in level
flight, crouches in a climb, and hangs on with her legs trailing when it drops away under her.
Her short hair and her scarf flap in the wind.

Both levels have a war going on in them: two fleets of airships, one grey-blue and one rust-red,
sailing side by side and firing on each other, with H-shaped fighters from each side tangling
round them. All of them shoot at you too. Shells burst near where you were heading, so flying
straight gets you hit and turning does not, and a ship's guns cannot see under its own hull.
You have five hearts, which mend if you stay unhurt; lose them all and you start again.

Everything is cel shaded in the manner of Breath of the Wild: two flat tones with coloured
shade and a thin bright rim, no outlines and no textures.

## Flying

| | Keys | Gamepad | Touch |
| --- | --- | --- | --- |
| Bank left / right | A / D or arrows | left stick | drag on the left of the screen |
| Pull up | S or Down | stick back | drag down |
| Dive | W or Up | stick forward | drag up |
| Jet boost | Space | A or right trigger | hold the right of the screen |
| Air brake | Shift | B or left trigger | |
| Restart | R | | |
| Next level | L | | the button in the top corner |
| Glider / witch | G | | the button under it |
| Weather: clear / fair / heavy | 1 / 2 / 3 | | |

It flies like a glider. Diving buys speed and pulling up spends it. Bank to turn. Left alone it
settles into a gentle glide, sinking about 2 m/s, so to stay up you need lift: the air rises under
every cumulus and cloud tower, and the jet gives a few seconds of push before it has to recharge.
Sink into the sea of clouds and the wind lifts you back out.

## Tests

    godot --headless --fixed-fps 60 --path . -s res://tests/flight_test.gd
    godot --headless --fixed-fps 60 --path . -s res://tests/cloud_test.gd
    godot --headless --fixed-fps 60 --path . -s res://tests/fleet_test.gd
    godot --headless --fixed-fps 60 --path . -s res://tests/coast_test.gd
    godot --headless --fixed-fps 60 --path . -s res://tests/diorama_test.gd
    godot --headless --path . -s res://tests/hair_test.gd
    godot --fixed-fps 60 --path . -s res://tests/shots.gd -- <folder for screenshots> [coast]

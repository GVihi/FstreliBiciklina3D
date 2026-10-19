FSTRELI BICIKLINA 3D  -  v10 (Godot 4.3+, GDScript)

RUN
  1. Open Godot 4 (standard build, not .NET) -> Import -> select project.godot
     (the first open imports the 51 audio files, give it a few seconds)
  2. Press F5

CONTROLS
  WASD move         Shift run          Ctrl / C crouch
  Mouse aim         LMB shoot          RMB aim down sights (hold)
  R reload          Q / wheel / 1 / 2  switch darts <-> melee (a giant gummy worm)
  M sound on/off    V voices on/off    F11 fullscreen
  F9 graphics quality: high -> no MSAA -> no MSAA and no sun shadows (use it if it still stutters)
  Esc release mouse / pause (click to resume)       F8 reset high score
  Space dash (brief invulnerability: a dodge that would have hit you = PERFECT DODGE)
  Ctrl while sprinting = slide      Tab settings      F10 outlines on/off
  Upgrade / shop screens: click a card or press 1-4, Enter / click CONTINUE to go on
  Gamepad: left stick move, right stick aim (with aim assist), RT shoot, LT aim, A dash,
           X reload, Y switch weapon, B crouch/slide, Start pause

WHAT IS IN (everything from the web v4)
  riders (pro / sprinter / courier / ARMOURED purple that dismount and charge you)
  thrown desk phones (dodge by moving, shoot them, or bat them back with the melee weapon)
  bosses: rogue lawnmower, mesh wifi node, minister / president
  hype bar (8 s of x2 points and faster fire), combo shouts, cheerleaders
  pickups: R rapid fire, B fat darts, S slow motion, O shield, + life, $ cash
  between-round upgrades (pick 1 of 3), gummy worm melee, pedestrians, 4 lighting themes
  synthesised sound effects + spoken lines from your own recordings (audio/voice/)

WHAT CHANGED IN v10
  - The pink oval is now just "Melee", and it is a giant, ribbed, rubbery pink gummy worm.

WHAT CHANGED IN v9
  - Shop: ~35 items instead of 12, in four kinds: PATCH UP, NEXT ROUND packs (one-round boosts you can buy
    again every shop), UPGRADES (go up in levels, each level dearer) and PERKS (once only, they pair into duos:
    now 7 duos). Prices rise with the round AND with every purchase you have made. REROLL [R] (X on a pad)
    re-deals the shelf for a growing fee. At a normal income you can afford about one item a round.
  - Bosses: much more health, +32% per round. The weak spot is armour (grey crossed-out ring) until the boss is
    winding up an attack or dizzy, so you have to bait it. New patterns unlock with phases and rounds:
    COMBO (2-3 re-aimed dashes), SLAM (red circle on the ground: leave it or dash through) and VOLLEY (a fan
    of phones). The dizzy window shrinks and bosses get faster every round. Angry cyclists grow tougher too.
  - Voices now have a sound per speaker: narrator = loudspeaker with echo, cyclists = gritty shout, civilians =
    muffled, bosses = low, dirty and boomy. F7 switches the effects off and on so you can compare.
    Edit _setup_voice_buses() and VOICE_CAT / VOICE_GAIN_DB in scripts/sfx.gd to change them.
  - Fix: the full-screen outline pass was painting over every see-through object in the world (boss lunge
    strips, the slam circle, the warning rings under phones). They draw on top of it now.

WHAT CHANGED IN v8 (balance)
  - No more barrier: you can walk anywhere on the roundabout (fountain and buildings are solid).
    Standing on the road is dangerous: a rider that reaches you knocks you down.
  - Bosses and angry cyclists never leave. They chase you across the whole arena (a little slower than
    your sprint, so running always works), telegraph a straight lunge on the floor, and come again until
    they are dead. A lunge that misses overshoots or slams into the fountain / a wall and leaves them dizzy.
  - Phones home in on you until the last moment, land in a wider circle, and are thrown more often.
  - Ammo: 6 darts (was 8), slower reload, fewer ammo drops, and passive dart regeneration only at S rank.
  - Cash: much smaller payouts, growing 8% per round; shop prices grow 14% per round. Every shop has at
    least one affordable item.
  - New upgrades (SPEEDLOADER, RUNNING SHOES, POCKET MAGNET), new perks (ADRENALINE, DEADEYE, SCAVENGER,
    SECOND WIND) and three new duos (GHOST, HEADHUNTER, LIFE INSURANCE).
  - Your recorded voice lines are included.
  Tuning knobs, all near the top of scripts/main.gd: MAXSHELLS, SHOP_POOL costs, DROPS, BOSS_INFO speed,
  and add_cash() calls.

WHAT CHANGED IN v7
  - The arena is now a ROUNDABOUT: you stand on the central island, the ring road circles you,
    buildings all round, riders enter and leave through the tunnel behind you. Mouse look is 360 degrees.
  - Off-screen threats show as arrows at the screen edge (red = boss, yellow = phone) and on a radar top-left.
  - Text-to-speech is gone. Every spoken line is a silent placeholder WAV in audio/voice/;
    record over a file (same name) and it plays. audio/voice/VOICE_LINES.txt lists the text of each line.
    Several files with the same prefix (taunt_0, taunt_1 ...) are picked at random. V toggles voices.

WHAT CHANGED IN v6 (gameplay + look)
  - Rubber deflect: swing just as a phone arrives and it flies back at the thrower (hit-stop)
  - Chargers and bosses commit: red floor telegraph, straight dash, crash into the fountain or a wall and
    ~2 s dizzy. Dash out of the red lane. Bosses have phases, weak spot and a stagger bar.
  - Dash + slide; kills drop ammo / cash / lives; style meter D..S multiplies score
  - Cash shop between rounds with perks that combine into duos (MATADOR, BOUNTY HUNTER, QUICK DRAW)
  - Settings (Tab): FOV, sensitivity, toggle-ADS, aim assist, volume, outlines; saved to disk
  - Toon shading, outlines (full-screen depth pass) and bloom

WHAT CHANGED IN v5 (performance + audio only)
  Stutter
    - meshes and materials are shared instead of rebuilt on every spawn (util.gd cache)
    - one-of-everything warm-up behind a black screen at start-up, so shaders compile before play
    - darts and particles are recycled; tiny parts no longer cast shadows
    - sun shadows: one shadow map (was 4 splits), 30 m range, 2048 map; MSAA 4x -> 2x
    - HUD text is shaped once and re-drawn (was re-shaped twice per string per frame)
    - the OS voice is looked up at start-up, not during the first spoken line
  Audio
    - samples are baked DRY; one shared reverb on the "SFX" bus (sfx.gd) replaces the baked noise reverb
    - spoken-line pitch is compressed towards 1.0 (OS voices turned 0.6..1.5 into chipmunk / demon)
    - engine / boss loop pitch glides instead of jumping every frame

SOUND
  The web game synthesises its sounds at runtime. tools/bake_audio.py re-implements those exact
  recipes offline and writes DRY audio/*.wav (already included; add --wet for the old baked reverb). To regenerate after tweaking:
      python3 tools/bake_audio.py          (needs numpy + scipy)
  Voices are your own recordings: see audio/voice/VOICE_LINES.txt. Press V to turn voices off.

EXPORT A WINDOWS .EXE
  Project -> Export -> Add... -> Windows Desktop (download templates when asked)
  -> tick "Embed PCK" -> Export Project

FILES
  scripts/main.gd    rules and game flow         scripts/world.gd   the arena (ring.gd = street-to-circle maths)
  scripts/models.gd  all procedural 3D models    scripts/hud.gd     overlay, boss bars, upgrade cards
  scripts/sfx.gd     sample + voice playback      scripts/util.gd    mesh and ray helpers
  tools/bake_audio.py  offline audio synth       audio/             baked wav files

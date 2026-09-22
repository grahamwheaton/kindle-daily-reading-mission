# Artwork for the Kindle

Everything here is shown on a **Kindle 4 from 2011**: a 600x800 e-ink screen
with **sixteen shades of grey, no colour, no backlight**. Art drawn for a phone
screen turns to mud on it. These are the rules that keep it looking like the
picture that was drawn.

## Instructions to paste when generating artwork

> This image will be displayed on a 2011 Kindle e-ink screen: 600x800 pixels,
> greyscale only, sixteen shades of grey, no colour and no backlight. Please
> generate it to suit that:
>
> - **Portrait, 3:4 ratio** (e.g. 1086x1448 or 1200x1600). Never square or
>   landscape, and never a different ratio: the screen is exactly 3:4.
> - **Black and white line art with flat grey fills.** Bold outlines and solid
>   shapes. Think screen print, woodcut or comic inking.
> - **Strong contrast.** Near-black darks and near-white lights, with only a
>   few mid greys between them. Avoid soft, even, mid-grey tones: they all
>   collapse into the same shade on this screen.
> - **No colour.** Design in greyscale from the start rather than relying on a
>   conversion, because two colours of equal brightness become one grey.
> - **No gradients, glows, blur, soft shadows, mist or fog.** Sixteen shades
>   cannot render a smooth fade and it will band into stripes.
> - **No fine texture.** No cross-hatching, stippling, thin parallel lines,
>   noise or film grain. It becomes dirt once the picture is scaled down.
> - **Thick lines.** Nothing thinner than about 3 pixels at the size you
>   generate, or it disappears.
> - **Large, bold text**, few words, in a heavy sans-serif. Small or thin
>   lettering is unreadable. Keep text clear of the edges.
> - **Keep the important part in the middle.** Leave a margin all round; do not
>   run detail to the edge.
> - **Few elements, clearly separated.** A simple, strong composition beats a
>   detailed one, which turns to noise.
>
> Return a PNG or a high-quality JPEG. Do not add a border or frame.

## Turning generated art into the file the Kindle uses

```bash
python3 tools/prepare-screen-image.py artwork.png assets/sleep-screen.png
```

It fits the art to 600x800 on white without stretching, sharpens what the
downscale softened, and rounds to the sixteen greys the panel shows. It then
compares the result's brightness against the artwork and **refuses to write a
file that has come out far darker or lighter**, because a conversion that goes
wrong tends to go wrong spectacularly: an earlier attempt used Pillow's palette
quantisation and produced a solarised mess that looked nothing like the
picture.

Always look at the output before installing it.

## Installing a sleep screen

```bash
installer/rupert-screensaver.sh install sleep.png   # on the Kindle
installer/rupert-screensaver.sh restore             # put Amazon's back
```

It sets both sleep screens: KOReader's, used when the Kindle sleeps with the
dashboard or a story open, and the framework's twenty stock screensavers, used
when it sleeps at the Home screen. The originals are backed up to
`/mnt/us/rupert-mission/screensaver-backup` before anything is replaced.

## Mission and Big Read illustrations

The same drawing rules apply, at different sizes:

| | Size |
| --- | --- |
| Sleep screen | 600x800 |
| Mission cover, Big Read cover | 600x800 |
| Big Read page picture | up to 600x500 |

Mission illustrations are inlined into `mission.html` as base64; Big Read
pictures are files beside `story.json`. See `missions/README.md` and
`bigreads/README.md` in the content repository.

# The demo video

A fifteen second film of the build at the top of the project README: a Laravel
app with a React front end, installed and built once in order and once in
chains, with the terminal output and the waterfall side by side.

![The video](dist/parallel-build.gif)

| File | What it is |
| --- | --- |
| `dist/parallel-build.mp4` | 1080x1080, 30fps, 14.7s, h264 + silent AAC. The one to post. |
| `dist/parallel-build-4x5.mp4` | 1080x1350, the same film, for feeds that give a tall frame more room. |
| `dist/parallel-build.gif` | 540x540, 10fps. For a README, where an mp4 will not play. |
| `dist/parallel-build-poster.png` | The last frame, for a link preview or a slide. |

## What is in it

1. **In order.** `composer install`, then `npm ci`, then `npm run build`, the way
   a `set -e` script runs them. The npm row is drawn with the time it spends
   waiting on composer hatched out, because that is the whole of the problem.
   1:55.
2. **The change.** The `build.sh` that does it, which is `. ./parallel.sh`, two
   `chain` calls and a `run`.
3. **In chains.** The same build, the same rate of play, so it is over sooner on
   screen for the same reason it is over sooner on a machine. composer and npm
   both start at zero, npm finishes its install and its bundle while composer is
   still going, and every line in the terminal is labelled with the chain that
   wrote it, in that chain's colour. 1:00.
4. **The number.** 1:55 to 1:00, and where to get the file.

## Where the numbers and the output come from

The terminal output is real. A `laravel/react-starter-kit` was cloned, locked,
and had `composer install`, `npm ci` and `npm run build` run on it, each on its
own, with the output kept: the package names, the versions, the vite asset table
and its byte counts are all that build's. Lines were thinned to the ones that fit
a terminal this size, and composer's `Cloning ... from cache` was put back to the
`Extracting archive` it prints when it can reach the CDN, which it could not from
the container this was captured in.

The durations — 60s, 35s and 20s — are not that container's, where the npm
registry is a few milliseconds away and a `composer install` falls back to
cloning every package over git. They are the shape of a cold build on a real
machine, where a full `composer install` is the long pole and npm gets through
both of its steps while composer is still running. Everything the video claims
follows from those three numbers: 1:55 in order, 1:00 in chains, 1.9x.

They live in `src/build-data.ts`, with the output, and changing them changes the
whole film — the bars, the clock, the totals and the speedup are all derived.

## Rendering it

```sh
npm install
npm run dev                 # Remotion Studio, for scrubbing
npx remotion render ParallelBuild dist/parallel-build.mp4 \
    --pixel-format=yuv420p --image-format=png --crf=18
npx remotion render ParallelBuildPortrait dist/parallel-build-4x5.mp4 \
    --pixel-format=yuv420p --image-format=png --crf=18
npx remotion render ParallelBuild dist/parallel-build.gif \
    --codec=gif --every-nth-frame=3 --scale=0.5 --number-of-gif-loops=0
```

Remotion drives a headless Chrome. On a machine that has one already, point it
there rather than letting Remotion fetch its own:

```sh
npx remotion render ParallelBuild dist/parallel-build.mp4 \
    --browser-executable=/path/to/headless_shell
```

## The pieces

| File | What it does |
| --- | --- |
| `src/build-data.ts` | The build: three steps, their durations, and every line each one printed. |
| `src/timeline.ts` | Turns that into two timelines — in order and in chains — as terminal lines and waterfall bars. |
| `src/Demo.tsx` | The four acts and where each one starts. Both builds play at the same seconds-per-frame. |
| `src/scenes/` | An act of the build, the code card, and the closing frame. |
| `src/components/` | The terminal, the waterfall, the header, the backdrop. |
| `src/theme.ts` | The palette. The chain colours are the cyan and magenta `parallel.sh` hands out to the first two chains declared. |

## Logos

`public/logos/logo-composer-transparent5.png` is Composer's, from
[getcomposer.org](https://getcomposer.org). `public/logos/npm-logo-red.svg` is
npm's, from [github.com/npm/logos](https://github.com/npm/logos). Both are used
to identify the tools the video is about; neither project endorses this one.

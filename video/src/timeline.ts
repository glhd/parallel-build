import type {Row} from './components/Terminal';
import type {Track} from './components/Waterfall';
import {theme} from './theme';
import {BUILD} from './build-data';

export type Event = {
	/** When the line was printed, in build seconds. */
	t: number;
	row: Row;
};

const COLOR = {
	composer: theme.composer,
	npm: theme.npm,
} as const;

export const LABEL = {
	composer: 'composer',
	npm: 'npm',
} as const;

export const LABEL_WIDTH = Math.max(LABEL.composer.length, LABEL.npm.length);

type Step = {readonly seconds: number; readonly lines: readonly {readonly at: number; readonly text: string}[]};

/**
 * Place a step's captured output on the build clock. `at` is where in the step
 * the line was printed, so composer trickles for its whole install and `npm ci`
 * still says nothing until the moment it is done.
 */
const place = (
	step: Step,
	start: number,
	chain: keyof typeof LABEL | null
): Event[] =>
	step.lines.map(({at, text}) => ({
		t: start + at * step.seconds,
		row: {
			label: chain === null ? null : LABEL[chain],
			color: chain === null ? theme.term.fg : COLOR[chain],
			text,
		},
	}));

const {composer, npmCi, npmBuild} = BUILD.steps;

export const SEQUENTIAL_TOTAL = composer.seconds + npmCi.seconds + npmBuild.seconds;
export const PARALLEL_TOTAL = BUILD.parallelSeconds;

/** In order: nothing overlaps, so every step starts where the one before it stopped. */
const seqComposerEnd = composer.seconds;
const seqNpmCiEnd = seqComposerEnd + npmCi.seconds;
const seqNpmBuildEnd = seqNpmCiEnd + npmBuild.seconds;

export const BEFORE_EVENTS: Event[] = [
	...place(composer, 0, null),
	...place(npmCi, seqComposerEnd, null),
	...place(npmBuild, seqNpmCiEnd, null),
].sort((a, b) => a.t - b.t);

/** In chains: both chains start at zero, and `npm run build` follows `npm ci`. */
const parNpmCiEnd = npmCi.seconds;
const parNpmBuildEnd = parNpmCiEnd + npmBuild.seconds;

export const AFTER_EVENTS: Event[] = [
	...place(composer, 0, 'composer'),
	...place(npmCi, 0, 'npm'),
	...place(npmBuild, parNpmCiEnd, 'npm'),
].sort((a, b) => a.t - b.t);

export const BEFORE_TRACKS: Track[] = [
	{
		label: 'composer',
		color: theme.composer,
		logo: 'composer',
		segments: [{name: 'composer install', start: 0, end: seqComposerEnd}],
	},
	{
		label: 'npm',
		color: theme.npm,
		logo: 'npm',
		segments: [
			{name: 'waiting on composer', start: 0, end: seqComposerEnd, waiting: true},
			{name: 'npm ci', start: seqComposerEnd, end: seqNpmCiEnd},
			{name: 'vite build', start: seqNpmCiEnd, end: seqNpmBuildEnd},
		],
	},
];

export const AFTER_TRACKS: Track[] = [
	{
		label: 'composer',
		color: theme.composer,
		logo: 'composer',
		segments: [{name: 'composer install', start: 0, end: composer.seconds}],
	},
	{
		label: 'npm',
		color: theme.npm,
		logo: 'npm',
		segments: [
			{name: 'npm ci', start: 0, end: parNpmCiEnd},
			{name: 'vite build', start: parNpmCiEnd, end: parNpmBuildEnd},
		],
	},
];

export const SPAN = SEQUENTIAL_TOTAL;

/** How many lines are on screen at `clock`, fractionally, so the scroll is smooth. */
export const revealedAt = (events: Event[], clock: number) => {
	let i = 0;
	while (i < events.length && events[i].t <= clock) i++;
	if (i === 0) return 0;
	if (i >= events.length) return events.length;
	const prev = events[i - 1].t;
	const next = events[i].t;
	return i + (next > prev ? (clock - prev) / (next - prev) : 0);
};

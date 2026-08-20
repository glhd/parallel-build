import React from 'react';
import {AbsoluteFill, interpolate, useCurrentFrame} from 'remotion';
import {Backdrop} from './components/Backdrop';
import {BuildAct} from './scenes/BuildAct';
import {CodeBeat} from './scenes/CodeBeat';
import {Payoff} from './scenes/Payoff';
import {
	AFTER_EVENTS,
	AFTER_TRACKS,
	BEFORE_EVENTS,
	BEFORE_TRACKS,
	PARALLEL_TOTAL,
	SEQUENTIAL_TOTAL,
} from './timeline';
import {theme} from './theme';

/**
 * The acts, in frames. Both builds run at the same rate — build seconds per
 * frame — so the second one is over sooner on screen for the same reason it is
 * over sooner in real life.
 */
export const ACTS = {
	beforeStart: 0,
	beforeRun: 132, // frames the sequential build gets to play out
	beforeEnd: 162,
	codeStart: 162,
	codeEnd: 232,
	afterStart: 232,
	afterEnd: 350,
	payoffStart: 350,
	total: 440,
} as const;

const RATE = SEQUENTIAL_TOTAL / ACTS.beforeRun; // build seconds per frame
const AFTER_RUN = Math.round(PARALLEL_TOTAL / RATE);

const fade = (frame: number, a: number, b: number, c: number, d: number) =>
	interpolate(frame, [a, b, c, d], [0, 1, 1, 0], {
		extrapolateLeft: 'clamp',
		extrapolateRight: 'clamp',
	});

export const Demo: React.FC = () => {
	const frame = useCurrentFrame();

	const beforeClock = interpolate(
		frame,
		[0, ACTS.beforeRun],
		[0, SEQUENTIAL_TOTAL],
		{extrapolateLeft: 'clamp', extrapolateRight: 'clamp'}
	);
	const afterClock = interpolate(
		frame,
		[ACTS.afterStart + 4, ACTS.afterStart + 4 + AFTER_RUN],
		[0, PARALLEL_TOTAL],
		{extrapolateLeft: 'clamp', extrapolateRight: 'clamp'}
	);

	const beforeSettle = interpolate(frame, [ACTS.beforeRun, ACTS.beforeRun + 12], [0, 1], {
		extrapolateLeft: 'clamp',
		extrapolateRight: 'clamp',
	});
	const afterSettle = interpolate(
		frame,
		[ACTS.afterStart + 4 + AFTER_RUN, ACTS.afterStart + 16 + AFTER_RUN],
		[0, 1],
		{extrapolateLeft: 'clamp', extrapolateRight: 'clamp'}
	);

	return (
		<AbsoluteFill>
			<Backdrop />

			<AbsoluteFill style={{opacity: fade(frame, 0, 10, ACTS.beforeEnd - 12, ACTS.beforeEnd)}}>
				<BuildAct
					pill="IN ORDER"
					pillColor={theme.red}
					headline="A Laravel build, one step at a time"
					sub="composer, then npm, then vite — because the script says so"
					terminalTitle="build.sh"
					events={BEFORE_EVENTS}
					tracks={BEFORE_TRACKS}
					clock={beforeClock}
					total={SEQUENTIAL_TOTAL}
					settle={beforeSettle}
					labelled={false}
				/>
			</AbsoluteFill>

			<AbsoluteFill
				style={{
					opacity: fade(
						frame,
						ACTS.codeEnd - 14,
						ACTS.codeEnd - 2,
						ACTS.afterEnd - 12,
						ACTS.afterEnd
					),
				}}
			>
				<BuildAct
					pill="IN CHAINS"
					pillColor={theme.green}
					headline="The same build, in two chains"
					sub="every line says which chain wrote it, as it is written"
					terminalTitle="build.sh — parallel.sh"
					events={AFTER_EVENTS}
					tracks={AFTER_TRACKS}
					clock={afterClock}
					total={PARALLEL_TOTAL}
					settle={afterSettle}
					labelled
				/>
			</AbsoluteFill>

			<AbsoluteFill
				style={{
					opacity: fade(frame, ACTS.codeStart, ACTS.codeStart + 10, ACTS.codeEnd - 14, ACTS.codeEnd),
					pointerEvents: 'none',
				}}
			>
				<CodeBeat frame={frame - ACTS.codeStart} fade={1} />
			</AbsoluteFill>

			<AbsoluteFill
				style={{
					opacity: interpolate(
						frame,
						[ACTS.payoffStart - 10, ACTS.payoffStart + 4],
						[0, 1],
						{extrapolateLeft: 'clamp', extrapolateRight: 'clamp'}
					),
				}}
			>
				<Backdrop />
				<Payoff
					frame={frame - ACTS.payoffStart}
					sequential={SEQUENTIAL_TOTAL}
					parallel={PARALLEL_TOTAL}
				/>
			</AbsoluteFill>
		</AbsoluteFill>
	);
};

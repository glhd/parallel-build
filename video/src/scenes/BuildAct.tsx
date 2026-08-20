import React from 'react';
import {AbsoluteFill, useVideoConfig} from 'remotion';
import {Header} from '../components/Header';
import {Terminal} from '../components/Terminal';
import {Waterfall, fmt, type Track} from '../components/Waterfall';
import {LABEL_WIDTH, revealedAt, SPAN, type Event} from '../timeline';
import {mono, sans, theme} from '../theme';
import {PAGE} from '../layout';

type Props = {
	pill: string;
	pillColor: string;
	headline: string;
	sub: string;
	terminalTitle: string;
	events: Event[];
	tracks: Track[];
	/** Where the build has got to, in build seconds. */
	clock: number;
	total: number;
	/** 0 until the build is done, then eases to 1 for the total-time badge. */
	settle: number;
	labelled: boolean;
};

export const BuildAct: React.FC<Props> = ({
	pill,
	pillColor,
	headline,
	sub,
	terminalTitle,
	events,
	tracks,
	clock,
	total,
	settle,
	labelled,
}) => {
	const {height} = useVideoConfig();
	const revealed = revealedAt(events, clock);
	const rows = events.map((e) => e.row);
	// Everything but the terminal is a fixed height; the terminal takes what is
	// left, up to the point where a taller window stops adding anything.
	const terminalHeight = Math.min(PAGE.terminalMax, height - PAGE.chromeHeight);
	// The total sits outside the flow, so a taller frame needs to be told about it
	// or the stack settles too low.
	const slack = Math.max(0, height - PAGE.chromeHeight - PAGE.terminalMax);
	const balance = Math.min(74, slack);

	return (
		<AbsoluteFill
			style={{
				padding: `${PAGE.padTop}px ${PAGE.padX}px ${PAGE.padTop + balance}px`,
				display: 'flex',
				flexDirection: 'column',
				justifyContent: 'center',
			}}
		>
			<Header pill={pill} pillColor={pillColor} headline={headline} sub={sub} />

			<div style={{height: PAGE.gap}} />

			<Terminal
				rows={rows}
				revealed={revealed}
				labelWidth={labelled ? LABEL_WIDTH : 0}
				title={terminalTitle}
				height={terminalHeight}
				fontSize={16}
				lineHeight={24}
			/>

			<div style={{height: PAGE.gap + 20}} />

			<div style={{position: 'relative'}}>
				<Waterfall tracks={tracks} clock={clock} span={SPAN} />

				{/* Once the build is done, the number it took lands next to the bars. */}
				<div
					style={{
						position: 'absolute',
						right: 0,
						top: '100%',
						marginTop: 14,
						display: 'flex',
						alignItems: 'baseline',
						gap: 12,
						opacity: settle,
						transform: `translateY(${(1 - settle) * 14}px)`,
					}}
				>
					<span
						style={{
							fontFamily: sans,
							fontSize: 19,
							fontWeight: 600,
							color: theme.textDim,
							letterSpacing: 0.4,
						}}
					>
						TOTAL
					</span>
					<span
						style={{
							fontFamily: mono,
							fontSize: 46,
							fontWeight: 700,
							color: pillColor,
							letterSpacing: -1,
						}}
					>
						{fmt(total)}
					</span>
				</div>
			</div>
		</AbsoluteFill>
	);
};

import React from 'react';
import {Img, interpolate, staticFile} from 'remotion';
import {mono, sans, theme} from '../theme';

export type Segment = {
	name: string;
	start: number;
	end: number;
	/** A wait is time the step spent doing nothing but waiting on another step. */
	waiting?: boolean;
};

export type Track = {
	label: string;
	color: string;
	logo: 'composer' | 'npm';
	segments: Segment[];
};

type Props = {
	tracks: Track[];
	/** Where the playhead is, in build seconds. */
	clock: number;
	/** The full width of the axis, in build seconds. Shared by both layouts so the bars stay comparable. */
	span: number;
	gutter?: number;
	rowHeight?: number;
	barHeight?: number;
	opacity?: number;
};

const LOGOS: Record<Track['logo'], string> = {
	composer: 'logos/logo-composer-transparent5.png',
	npm: 'logos/npm-logo-red.svg',
};

export const fmt = (seconds: number) => {
	const s = Math.max(0, Math.round(seconds));
	return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
};

export const Waterfall: React.FC<Props> = ({
	tracks,
	clock,
	span,
	gutter = 250,
	rowHeight = 100,
	barHeight = 58,
	opacity = 1,
}) => {
	const ticks = [];
	for (let t = 0; t <= span; t += 30) ticks.push(t);

	return (
		<div style={{position: 'relative', opacity}}>
			{tracks.map((track) => (
				<div
					key={track.label}
					style={{height: rowHeight, display: 'flex', alignItems: 'center'}}
				>
					<div
						style={{
							width: gutter,
							flexShrink: 0,
							display: 'flex',
							alignItems: 'center',
							gap: 14,
							paddingRight: 20,
							justifyContent: 'flex-end',
						}}
					>
						<Img
							src={staticFile(LOGOS[track.logo])}
							style={{
								height: track.logo === 'npm' ? 30 : 54,
								width: 'auto',
								filter: 'saturate(1.05)',
							}}
						/>
						<div
							style={{
								fontFamily: mono,
								fontSize: 19,
								fontWeight: 700,
								color: track.color,
								whiteSpace: 'nowrap',
							}}
						>
							{track.label}
						</div>
					</div>

					<div style={{flex: 1, position: 'relative', height: barHeight}}>
						<div
							style={{
								position: 'absolute',
								inset: 0,
								borderRadius: 10,
								background: 'rgba(255,255,255,0.028)',
							}}
						/>
						{track.segments.map((seg) => {
							// Each bar grows with the playhead, so the picture is drawn as the build runs.
							const drawnEnd = Math.min(clock, seg.end);
							if (drawnEnd <= seg.start) return null;
							const left = (seg.start / span) * 100;
							const width = ((drawnEnd - seg.start) / span) * 100;
							const done = clock >= seg.end;
							return (
								<div
									key={seg.name}
									style={{
										position: 'absolute',
										left: `${left}%`,
										width: `${width}%`,
										top: 0,
										height: barHeight,
										borderRadius: 10,
										overflow: 'hidden',
										background: seg.waiting
											? 'repeating-linear-gradient(-45deg, rgba(255,255,255,0.075) 0 9px, rgba(255,255,255,0.015) 9px 18px)'
											: `linear-gradient(180deg, ${track.color}, ${track.color}bb)`,
										border: seg.waiting
											? '1px dashed rgba(255,255,255,0.22)'
											: '1px solid rgba(255,255,255,0.13)',
										display: 'flex',
										alignItems: 'center',
										paddingLeft: 16,
										boxShadow: seg.waiting
											? 'none'
											: `0 6px 22px ${track.color}33`,
									}}
								>
									<span
										style={{
											fontFamily: mono,
											fontSize: 15,
											fontWeight: 600,
											whiteSpace: 'nowrap',
											color: seg.waiting ? theme.textFaint : 'rgba(6,10,15,0.88)',
											opacity: interpolate(
												clock - seg.start,
												[0, Math.min(4, (seg.end - seg.start) / 3)],
												[0, 1],
												{extrapolateLeft: 'clamp', extrapolateRight: 'clamp'}
											),
										}}
									>
										{seg.name}
									</span>
									{!done ? (
										<div
											style={{
												position: 'absolute',
												right: 0,
												top: 0,
												bottom: 0,
												width: 3,
												background: 'rgba(255,255,255,0.75)',
											}}
										/>
									) : null}
								</div>
							);
						})}
					</div>
				</div>
			))}

			<div style={{display: 'flex', marginTop: 6}}>
				<div style={{width: gutter, flexShrink: 0}} />
				<div style={{flex: 1, position: 'relative', height: 26}}>
					<div
						style={{
							position: 'absolute',
							top: 0,
							left: 0,
							right: 0,
							height: 1,
							background: 'rgba(255,255,255,0.09)',
						}}
					/>
					{ticks.map((t) => (
						<div
							key={t}
							style={{
								position: 'absolute',
								left: `${(t / span) * 100}%`,
								top: 0,
								fontFamily: mono,
								fontSize: 14,
								color: theme.textFaint,
								transform: 'translateX(-50%)',
								paddingTop: 6,
							}}
						>
							{fmt(t)}
						</div>
					))}
				</div>
			</div>

			{/* The playhead, and the clock it drags along behind it. */}
			<div
				style={{
					position: 'absolute',
					left: gutter,
					right: 0,
					top: -10,
					bottom: 30,
					pointerEvents: 'none',
				}}
			>
				<div
					style={{
						position: 'absolute',
						left: `${Math.min(100, (clock / span) * 100)}%`,
						top: 0,
						bottom: 0,
						width: 2,
						background: 'rgba(255,255,255,0.30)',
					}}
				>
					<div
						style={{
							position: 'absolute',
							top: -34,
							left: 0,
							transform: 'translateX(-50%)',
							fontFamily: mono,
							fontSize: 20,
							fontWeight: 700,
							color: theme.text,
							background: 'rgba(255,255,255,0.08)',
							border: `1px solid ${theme.panelEdge}`,
							borderRadius: 8,
							padding: '3px 10px',
						}}
					>
						{fmt(clock)}
					</div>
				</div>
			</div>
		</div>
	);
};

import React from 'react';
import {interpolate} from 'remotion';
import {mono, theme} from '../theme';

export type Row = {
	/** The chain that wrote the line, or null for a line no chain owns. */
	label: string | null;
	color: string;
	text: string;
	/** Outcome lines get the `[!]` / `[.]` marker in plain text, as the library prints them. */
	marker?: '[!]' | '[.]';
	textColor?: string;
};

type Props = {
	rows: Row[];
	/** How many rows have been printed, fractional so the scroll can be smooth. */
	revealed: number;
	labelWidth: number;
	title: string;
	height: number;
	fontSize?: number;
	lineHeight?: number;
	separator?: string;
};

const Dot: React.FC<{color: string}> = ({color}) => (
	<div style={{width: 13, height: 13, borderRadius: 999, background: color}} />
);

export const Terminal: React.FC<Props> = ({
	rows,
	revealed,
	labelWidth,
	title,
	height,
	fontSize = 19,
	lineHeight = 29,
	separator = '│',
}) => {
	const chromeHeight = 46;
	const padY = 18;
	const bodyHeight = height - chromeHeight - padY * 2;
	const visibleLines = Math.floor(bodyHeight / lineHeight);

	const shown = Math.max(0, Math.min(rows.length, Math.floor(revealed)));
	// Scroll only once the output is taller than the window, and follow the
	// last line that has been printed rather than snapping a whole line at a time.
	const scroll = Math.max(0, revealed - visibleLines) * lineHeight;

	return (
		<div
			style={{
				height,
				borderRadius: 16,
				overflow: 'hidden',
				background: theme.term.bg,
				border: `1px solid ${theme.panelEdge}`,
				boxShadow: '0 30px 80px rgba(0,0,0,0.55)',
				display: 'flex',
				flexDirection: 'column',
			}}
		>
			<div
				style={{
					height: chromeHeight,
					flexShrink: 0,
					background: theme.term.chrome,
					display: 'flex',
					alignItems: 'center',
					padding: '0 18px',
					gap: 9,
					borderBottom: `1px solid ${theme.panelEdge}`,
				}}
			>
				<Dot color="#ff5f57" />
				<Dot color="#febc2e" />
				<Dot color="#28c840" />
				<div
					style={{
						flex: 1,
						textAlign: 'center',
						fontFamily: mono,
						fontSize: 16,
						color: theme.term.dim,
						letterSpacing: 0.2,
						marginLeft: -48,
					}}
				>
					{title}
				</div>
			</div>

			<div
				style={{
					flex: 1,
					overflow: 'hidden',
					padding: `${padY}px 24px`,
					// The line the scroll has half eaten fades out rather than being cut.
					maskImage:
						'linear-gradient(to bottom, transparent 0px, #000 26px, #000 100%)',
				}}
			>
				<div style={{transform: `translateY(${-scroll}px)`}}>
					{rows.slice(0, shown).map((row, i) => {
						// The newest line eases in rather than appearing at full strength.
						const age = revealed - i;
						const opacity = interpolate(age, [0, 0.6], [0, 1], {
							extrapolateLeft: 'clamp',
							extrapolateRight: 'clamp',
						});
						return (
							<div
								key={i}
								style={{
									height: lineHeight,
									display: 'flex',
									alignItems: 'center',
									fontFamily: mono,
									fontSize,
									whiteSpace: 'pre',
									opacity,
								}}
							>
								{row.marker ? (
									<>
										<span style={{color: theme.term.fg}}>{row.marker} </span>
										<span style={{color: row.color, fontWeight: 700}}>{row.label}</span>
										<span style={{color: row.textColor ?? theme.term.fg}}>
											{' '}
											{row.text}
										</span>
									</>
								) : (
									<>
										{row.label === null ? null : (
											<span style={{color: row.color, fontWeight: 700}}>
												{row.label.padStart(labelWidth)} {separator}{' '}
											</span>
										)}
										<span style={{color: row.textColor ?? theme.term.fg}}>{row.text}</span>
									</>
								)}
							</div>
						);
					})}
				</div>
			</div>
		</div>
	);
};

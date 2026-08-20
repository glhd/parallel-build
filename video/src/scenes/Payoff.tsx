import React from 'react';
import {AbsoluteFill, Img, interpolate, spring, staticFile, useVideoConfig} from 'remotion';
import {fmt} from '../components/Waterfall';
import {mono, sans, theme} from '../theme';

const Bar: React.FC<{
	label: string;
	seconds: number;
	span: number;
	color: string;
	grow: number;
	strike?: boolean;
}> = ({label, seconds, span, color, grow, strike}) => (
	<div style={{display: 'flex', alignItems: 'center', gap: 22, marginBottom: 20}}>
		<div
			style={{
				width: 132,
				textAlign: 'right',
				fontFamily: sans,
				fontSize: 22,
				fontWeight: 600,
				color: theme.textDim,
				whiteSpace: 'nowrap',
			}}
		>
			{label}
		</div>
		<div style={{flex: 1, position: 'relative', height: 46}}>
			<div
				style={{
					position: 'absolute',
					inset: 0,
					borderRadius: 10,
					background: 'rgba(255,255,255,0.03)',
				}}
			/>
			<div
				style={{
					position: 'absolute',
					left: 0,
					top: 0,
					height: 46,
					width: `${(seconds / span) * 100 * grow}%`,
					borderRadius: 10,
					background: `linear-gradient(180deg, ${color}, ${color}bb)`,
					boxShadow: `0 6px 26px ${color}44`,
				}}
			/>
		</div>
		<div
			style={{
				width: 128,
				fontFamily: mono,
				fontSize: 34,
				fontWeight: 700,
				color,
				textDecoration: strike ? 'line-through' : 'none',
				textDecorationThickness: strike ? 3 : undefined,
			}}
		>
			{fmt(seconds)}
		</div>
	</div>
);

export const Payoff: React.FC<{
	frame: number;
	sequential: number;
	parallel: number;
}> = ({frame, sequential, parallel}) => {
	const {fps} = useVideoConfig();
	const grow = spring({frame: frame - 4, fps, config: {damping: 200}, durationInFrames: 26});
	const speedup = (sequential / parallel).toFixed(1);

	const rise = (delay: number) =>
		spring({frame: frame - delay, fps, config: {damping: 200}, durationInFrames: 20});

	return (
		<AbsoluteFill
			style={{
				padding: '84px 76px 76px',
				display: 'flex',
				flexDirection: 'column',
				justifyContent: 'center',
			}}
		>
			<div style={{opacity: rise(0), transform: `translateY(${(1 - rise(0)) * 22}px)`}}>
				<div
					style={{
						fontFamily: sans,
						fontSize: 64,
						fontWeight: 800,
						color: theme.text,
						letterSpacing: -2.2,
						lineHeight: 1.05,
					}}
				>
					npm stops waiting
					<br />
					on composer.
				</div>
			</div>

			<div style={{height: 54}} />

			<div style={{opacity: rise(6)}}>
				<Bar
					label="in order"
					seconds={sequential}
					span={sequential}
					color={theme.textFaint}
					grow={grow}
					strike
				/>
				<Bar
					label="in chains"
					seconds={parallel}
					span={sequential}
					color={theme.green}
					grow={grow}
				/>
			</div>

			<div
				style={{
					marginTop: 26,
					display: 'flex',
					alignItems: 'center',
					gap: 20,
					opacity: rise(18),
				}}
			>
				<div
					style={{
						fontFamily: sans,
						fontSize: 40,
						fontWeight: 800,
						color: theme.green,
						letterSpacing: -1,
					}}
				>
					{speedup}× faster
				</div>
				<div
					style={{
						fontFamily: sans,
						fontSize: 22,
						fontWeight: 500,
						color: theme.textDim,
					}}
				>
					on the same machine, from the same script
				</div>
			</div>

			<div style={{height: 44}} />

			<div style={{opacity: rise(24), marginBottom: 46}}>
				{[
					'Every chain runs at once',
					'Every line says which chain wrote it',
					'The first failure stops the rest',
					'One POSIX sh file, nothing to install',
				].map((point, i) => (
					<div
						key={point}
						style={{
							display: 'flex',
							alignItems: 'center',
							gap: 16,
							marginBottom: 14,
							opacity: rise(24 + i * 3),
						}}
					>
						<span style={{color: theme.green, fontFamily: mono, fontSize: 24}}>+</span>
						<span
							style={{
								fontFamily: sans,
								fontSize: 25,
								fontWeight: 500,
								color: theme.text,
							}}
						>
							{point}
						</span>
					</div>
				))}
			</div>

			<div style={{opacity: rise(36)}}>
				<div
					style={{
						fontFamily: mono,
						fontSize: 17,
						color: theme.term.dim,
						background: 'rgba(255,255,255,0.04)',
						border: `1px solid ${theme.panelEdge}`,
						borderRadius: 12,
						padding: '18px 22px',
						whiteSpace: 'nowrap',
						overflow: 'hidden',
					}}
				>
					<span style={{color: theme.green}}>$</span>{' '}
					<span style={{color: theme.term.fg}}>curl -fsSLO</span>{' '}
					<span style={{color: theme.yellow}}>
						https://raw.githubusercontent.com/glhd/parallel-build/main/parallel.sh
					</span>
				</div>

				<div
					style={{
						marginTop: 24,
						display: 'flex',
						alignItems: 'center',
						justifyContent: 'space-between',
					}}
				>
					<div
						style={{
							fontFamily: mono,
							fontSize: 26,
							fontWeight: 700,
							color: theme.text,
						}}
					>
						github.com/glhd/parallel-build
					</div>
					<div style={{display: 'flex', alignItems: 'center', gap: 26, opacity: 0.9}}>
						<Img
							src={staticFile('logos/logo-composer-transparent5.png')}
							style={{height: 52}}
						/>
						<Img src={staticFile('logos/npm-logo-red.svg')} style={{height: 30}} />
					</div>
				</div>
			</div>
		</AbsoluteFill>
	);
};

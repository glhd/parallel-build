import React from 'react';
import {AbsoluteFill, interpolate, spring, useVideoConfig} from 'remotion';
import {mono, sans, theme} from '../theme';

type Tok = {t: string; c?: string};
type Line = {toks: Tok[]; added?: boolean};

const dim = theme.term.dim;
const str = theme.yellow;
const kw = theme.npm;
const fn = theme.composer;

const LINES: Line[] = [
	{toks: [{t: '#!/bin/sh', c: dim}]},
	{toks: [{t: 'set', c: kw}, {t: ' -e'}]},
	{toks: [{t: '. ./parallel.sh', c: fn}], added: true},
	{toks: []},
	{
		toks: [
			{t: 'chain', c: fn},
			{t: ' '},
			{t: '"composer install"', c: str},
			{t: ' \\'},
		],
		added: true,
	},
	{
		toks: [
			{t: '        '},
			{t: '"composer install --no-dev --prefer-dist"', c: str},
		],
		added: true,
	},
	{
		toks: [
			{t: 'chain', c: fn},
			{t: ' '},
			{t: '"npm build"', c: str},
			{t: ' '},
			{t: '"npm ci"', c: str},
			{t: ' '},
			{t: '"npm run build"', c: str},
		],
		added: true,
	},
	{toks: []},
	{toks: [{t: 'run', c: fn}], added: true},
];

export const CodeBeat: React.FC<{frame: number; fade: number}> = ({frame, fade}) => {
	const {fps} = useVideoConfig();

	return (
		<AbsoluteFill
			style={{
				alignItems: 'center',
				justifyContent: 'center',
				padding: 60,
				opacity: fade,
				background: 'rgba(7,9,13,0.86)',
				backdropFilter: 'blur(6px)',
			}}
		>
			<div
				style={{
					fontFamily: sans,
					fontSize: 44,
					fontWeight: 700,
					color: theme.text,
					letterSpacing: -0.9,
					marginBottom: 30,
					textAlign: 'center',
				}}
			>
				One file. Two chains.
			</div>

			<div
				style={{
					width: '100%',
					borderRadius: 18,
					background: theme.term.bg,
					border: `1px solid ${theme.panelEdge}`,
					boxShadow: '0 30px 90px rgba(0,0,0,0.6)',
					overflow: 'hidden',
				}}
			>
				<div
					style={{
						padding: '13px 22px',
						background: theme.term.chrome,
						fontFamily: mono,
						fontSize: 17,
						color: theme.term.dim,
						borderBottom: `1px solid ${theme.panelEdge}`,
					}}
				>
					build.sh
				</div>
				<div style={{padding: '26px 26px 30px'}}>
					{LINES.map((line, i) => {
						// The added lines arrive one after another, so the eye follows the change.
						const addedIndex = LINES.slice(0, i).filter((l) => l.added).length;
						const enter = line.added
							? spring({
									frame: frame - 3 - addedIndex * 3,
									fps,
									config: {damping: 200},
									durationInFrames: 10,
								})
							: 1;
						return (
							<div
								key={i}
								style={{
									display: 'flex',
									alignItems: 'center',
									minHeight: 40,
									fontFamily: mono,
									fontSize: 27,
									whiteSpace: 'pre',
									opacity: line.added ? enter : 1,
									transform: `translateX(${line.added ? (1 - enter) * -18 : 0}px)`,
									borderLeft: line.added
										? `3px solid ${theme.green}`
										: '3px solid transparent',
									background: line.added ? `${theme.green}0f` : 'transparent',
									paddingLeft: 16,
									marginLeft: -19,
								}}
							>
								{line.toks.map((tok, j) => (
									<span key={j} style={{color: tok.c ?? theme.term.fg}}>
										{tok.t}
									</span>
								))}
							</div>
						);
					})}
				</div>
			</div>

			<div
				style={{
					fontFamily: sans,
					fontSize: 24,
					fontWeight: 500,
					color: theme.textDim,
					marginTop: 28,
					textAlign: 'center',
				}}
			>
				POSIX sh. No dependencies. Source it and go.
			</div>
		</AbsoluteFill>
	);
};

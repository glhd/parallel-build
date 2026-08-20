import React from 'react';
import {mono, sans, theme} from '../theme';

export const Header: React.FC<{
	pill: string;
	pillColor: string;
	headline: string;
	sub: string;
}> = ({pill, pillColor, headline, sub}) => (
	<div style={{display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between'}}>
		<div>
			<div
				style={{
					fontFamily: sans,
					fontSize: 42,
					fontWeight: 700,
					color: theme.text,
					letterSpacing: -0.9,
					lineHeight: 1.12,
				}}
			>
				{headline}
			</div>
			<div
				style={{
					fontFamily: sans,
					fontSize: 21,
					fontWeight: 500,
					color: theme.textDim,
					marginTop: 7,
				}}
			>
				{sub}
			</div>
		</div>
		<div
			style={{
				fontFamily: mono,
				fontSize: 17,
				fontWeight: 700,
				letterSpacing: 1.6,
				color: pillColor,
				border: `1px solid ${pillColor}55`,
				background: `${pillColor}14`,
				borderRadius: 999,
				padding: '9px 20px',
				whiteSpace: 'nowrap',
				marginTop: 6,
			}}
		>
			{pill}
		</div>
	</div>
);

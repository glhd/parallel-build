import React from 'react';
import {AbsoluteFill} from 'remotion';
import {theme} from '../theme';

export const Backdrop: React.FC = () => (
	<AbsoluteFill style={{background: theme.page}}>
		<AbsoluteFill
			style={{
				background: `radial-gradient(120% 80% at 50% -10%, ${theme.pageGlow} 0%, ${theme.page} 62%)`,
			}}
		/>
		<AbsoluteFill
			style={{
				backgroundImage:
					'linear-gradient(rgba(255,255,255,0.022) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.022) 1px, transparent 1px)',
				backgroundSize: '54px 54px',
				maskImage: 'radial-gradient(80% 60% at 50% 40%, #000 0%, transparent 100%)',
			}}
		/>
	</AbsoluteFill>
);

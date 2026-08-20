import React, {useEffect, useState} from 'react';
import {Composition, continueRender, delayRender} from 'remotion';
import '@fontsource/inter/400.css';
import '@fontsource/inter/500.css';
import '@fontsource/inter/600.css';
import '@fontsource/inter/700.css';
import '@fontsource/inter/800.css';
import '@fontsource/jetbrains-mono/400.css';
import '@fontsource/jetbrains-mono/600.css';
import '@fontsource/jetbrains-mono/700.css';
import {Demo, ACTS} from './Demo';
import {PAGE} from './layout';

/** Nothing renders until the two fonts are on the page, or every frame lays out differently. */
const WithFonts: React.FC<{children: React.ReactNode}> = ({children}) => {
	const [handle] = useState(() => delayRender('Loading fonts'));
	const [ready, setReady] = useState(false);

	useEffect(() => {
		Promise.all([
			document.fonts.load('700 20px "JetBrains Mono"'),
			document.fonts.load('400 20px "JetBrains Mono"'),
			document.fonts.load('800 20px Inter'),
			document.fonts.load('500 20px Inter'),
		])
			.then(() => document.fonts.ready)
			.then(() => {
				setReady(true);
				continueRender(handle);
			});
	}, [handle]);

	return <>{ready ? children : null}</>;
};

export const RemotionRoot: React.FC = () => (
	<>
		<Composition
			id="ParallelBuild"
			component={() => (
				<WithFonts>
					<Demo />
				</WithFonts>
			)}
			durationInFrames={ACTS.total}
			fps={PAGE.fps}
			width={PAGE.width}
			height={PAGE.height}
		/>
		<Composition
			id="ParallelBuildPortrait"
			component={() => (
				<WithFonts>
					<Demo />
				</WithFonts>
			)}
			durationInFrames={ACTS.total}
			fps={PAGE.fps}
			width={PAGE.width}
			height={1350}
		/>
	</>
);
